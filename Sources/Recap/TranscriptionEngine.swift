import AVFoundation
import Foundation
import RecapCore
import Speech

/// Transcribes one recording on this Mac with Apple's SpeechAnalyzer and SpeechTranscriber.
/// Nothing is uploaded: the engine and its language model run on the Mac (macOS 26 or later).
enum TranscriptionEngine {
    struct Progress: Sendable {
        var fraction: Double
        var newLines: [Line]
        var pendingText: String
    }

    struct Output: Sendable {
        var lines: [Line]
        var duration: Double
    }

    enum EngineError: LocalizedError {
        case unavailable
        case unsupportedLanguage(String)
        case modelNotInstalled(String)
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "On-device transcription isn't available on this Mac. Recap needs macOS 26 or later on a supported Mac."
            case .unsupportedLanguage(let name):
                return "\(name) isn't a language this Mac can transcribe."
            case .modelNotInstalled(let why):
                return "macOS couldn't download the speech model for this language. Check the internet connection and try again. (\(why))"
            case .noAudioFormat:
                return "The speech engine didn't offer an audio format to work with."
            }
        }
    }

    /// Languages the engine can transcribe, sorted by name.
    static func supportedLocales() async -> [Locale] {
        let all = await SpeechTranscriber.supportedLocales
        return all.sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
    }

    static func defaultLocale() async -> Locale {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en_US")
    }

    static func displayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Runs the whole job. Cancelling the calling task stops reading, stops the engine and
    /// abandons the wait for the last results.
    static func transcribe(url: URL, locale: Locale,
                           onProgress: @escaping @Sendable (Progress) -> Void) async throws -> Output {
        guard SpeechTranscriber.isAvailable else { throw EngineError.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw EngineError.unsupportedLanguage(displayName(locale))
        }

        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        try await ensureModel(for: transcriber, locale: supported)
        try Task.checkCancellation()

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.noAudioFormat
        }
        let audio = try await AudioFileSequence(url: url, format: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)

        let duration = audio.duration
        // Final results arrive on their own stream; collect them in a separate task.
        let collector = Task { () throws -> [Line] in
            var builder = LineBuilder()
            for try await result in transcriber.results {
                let words = Self.words(in: result)
                let closed = builder.add(words)
                let reached = words.last?.end ?? audio.position
                onProgress(Progress(fraction: fraction(reached, of: duration, read: audio.position),
                                    newLines: closed, pendingText: builder.pendingText))
            }
            if let last = builder.finish() {
                onProgress(Progress(fraction: 1, newLines: [last], pendingText: ""))
            }
            return builder.lines
        }

        return try await withTaskCancellationHandler {
            do {
                if let lastSample = try await analyzer.analyzeSequence(audio) {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
                if let failure = audio.failure { throw failure }
                try Task.checkCancellation()
                let lines = try await collector.value
                try Task.checkCancellation()
                return Output(lines: lines, duration: duration)
            } catch {
                collector.cancel()
                audio.cancel()
                await analyzer.cancelAndFinishNow()
                throw Task.isCancelled ? CancellationError() : error
            }
        } onCancel: {
            audio.cancel()
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Words with their times, from the audioTimeRange attribute on each run of the result's text.
    static func words(in result: SpeechTranscriber.Result) -> [Word] {
        var words: [Word] = []
        let text = result.text
        for run in text.runs {
            let piece = String(text[run.range].characters)
            guard let range = run.audioTimeRange else {
                // No time on this run: attach it to the previous word.
                if !words.isEmpty, !piece.trimmingCharacters(in: .whitespaces).isEmpty {
                    words[words.count - 1].text += piece.trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            let start = range.start.seconds, end = range.end.seconds
            for token in piece.split(whereSeparator: { $0.isWhitespace }) {
                words.append(Word(text: String(token), start: start, end: end))
            }
        }
        return words
    }

    static func fraction(_ reached: Double, of duration: Double, read: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(max(reached, read * 0.98) / duration, 0), 0.99)
    }

    private static func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .installed { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw EngineError.modelNotInstalled(error.localizedDescription)
        }
    }
}
