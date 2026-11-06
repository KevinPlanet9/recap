import AppKit
import Foundation
import RecapCore
import Speech

/// Modes used by the checks. None of them opens a window.
///   Recap --transcribe <file> [--locale en_US] [--format txt|md|srt|vtt|json] [--cancel-after <seconds>]
///   Recap --smoke-test     exercise the core with no engine and no window
///   Recap --launch-check   start as the signed, sandboxed app would, check its folder and engine, quit
///   Recap --update-check   packaged app only: read the update feed through Sparkle's Downloader helper, quit
/// They all return before RecapApp starts, so the window and the updater never start in these modes.
enum CommandLineModes {
    /// Returns an exit code when a mode ran, or nil to start the app normally.
    static func run(_ args: [String]) -> Int32? {
        if args.contains("--smoke-test") { return smokeTest() }
        if let folder = value(after: "--render-screens", in: args) {
            return MainActor.assumeIsolated { ScreenRenderer.run(folder: folder) }
        }
        if let folder = value(after: "--render-frames", in: args) {
            return MainActor.assumeIsolated { ScreenRenderer.runFrames(folder: folder) }
        }
        if args.contains("--launch-check") { return blocking { await launchCheck() } }
        if args.contains("--update-check") { return MainActor.assumeIsolated { UpdateCheck.run() } }
        if let i = args.firstIndex(of: "--transcribe") {
            guard args.indices.contains(i + 1) else { return fail("Give a file after --transcribe.") }
            let file = URL(fileURLWithPath: args[i + 1])
            let locale = value(after: "--locale", in: args).map { Locale(identifier: $0) }
            let format = value(after: "--format", in: args).flatMap(ExportFormat.init(rawValue:)) ?? .txt
            let cancelAfter = value(after: "--cancel-after", in: args).flatMap(Double.init)
            return blocking { await transcribe(file, locale: locale, format: format, cancelAfter: cancelAfter) }
        }
        return nil
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }

    /// Runs async work from the synchronous entry point and waits for its exit code.
    private static func blocking(_ work: @escaping @Sendable () async -> Int32) -> Int32 {
        let box = ExitBox()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.code = await work()
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return box.code
    }

    private final class ExitBox: @unchecked Sendable { var code: Int32 = 1 }

    static func transcribe(_ file: URL, locale: Locale?, format: ExportFormat, cancelAfter: Double?) async -> Int32 {
        guard FileManager.default.isReadableFile(atPath: file.path) else { return fail("Can't read \(file.path).") }
        let chosen: Locale
        if let locale { chosen = locale } else { chosen = await TranscriptionEngine.defaultLocale() }
        let started = Date()
        let job = Task {
            try await TranscriptionEngine.transcribe(url: file, locale: chosen) { _ in }
        }
        if let cancelAfter {
            Task {
                try? await Task.sleep(for: .seconds(cancelAfter))
                job.cancel()
            }
        }
        do {
            let output = try await job.value
            let elapsed = Date().timeIntervalSince(started)
            FileHandle.standardError.write(Data(String(format: "Transcribed %.1f s of audio in %.1f s, %d lines\n",
                                                       output.duration, elapsed, output.lines.count).utf8))
            if output.lines.isEmpty {
                _ = fail("No speech found.")
                return 3
            }
            let transcript = Transcript(title: transcriptTitle(forFileNamed: file.lastPathComponent),
                                        sourceName: file.lastPathComponent, bookmark: nil,
                                        locale: chosen.identifier, duration: output.duration, lines: output.lines)
            print(try Exporter.render(transcript, as: format), terminator: "")
            return 0
        } catch is CancellationError {
            let elapsed = Date().timeIntervalSince(started)
            FileHandle.standardError.write(Data(String(format: "Cancelled after %.1f s\n", elapsed).utf8))
            return 4
        } catch {
            return fail(error.localizedDescription)
        }
    }

    static func smokeTest() -> Int32 {
        var builder = LineBuilder()
        builder.add([Word(text: "Smoke", start: 0, end: 0.4), Word(text: "test.", start: 0.5, end: 0.9)])
        let t = Transcript(title: "Smoke", sourceName: "smoke.m4a", bookmark: nil, locale: "en_US",
                           duration: 1, lines: builder.lines)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recap-smoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            for format in ExportFormat.allCases { _ = try Exporter.render(t, as: format) }
            let store = TranscriptStore(folder: folder)
            try store.save(t)
            guard try store.loadAll().transcripts.first == t else { return fail("Smoke test: saved transcript didn't read back.") }
            print("Smoke test passed")
            return 0
        } catch {
            return fail("Smoke test: \(error.localizedDescription)")
        }
    }

    static func launchCheck() async -> Int32 {
        do {
            let folder = try TranscriptStore.defaultFolder()
            let store = TranscriptStore(folder: folder)
            _ = try store.loadAll()
            let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            let languages = await SpeechTranscriber.supportedLocales.count
            print("Launch check passed: sandbox \(sandboxed ? "on" : "off"), store \(folder.path), engine \(SpeechTranscriber.isAvailable ? "available" : "unavailable"), \(languages) languages")
            return 0
        } catch {
            return fail("Launch check: \(error.localizedDescription)")
        }
    }
}
