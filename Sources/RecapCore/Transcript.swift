import Foundation

/// One recognized word with its place in the recording, in seconds.
public struct Word: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One line of the transcript: a sentence or a short run of speech, with the time it starts.
public struct Line: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: Int, start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A finished transcript as it is saved: JSON in the app's own container.
/// The recording itself is never copied; `bookmark` points back to it for playback.
public struct Transcript: Codable, Equatable, Identifiable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var title: String
    /// The recording's file name when it was transcribed, for display only.
    public var sourceName: String
    /// An app-scoped security bookmark to the recording, so a click on a time can play it later.
    public var bookmark: Data?
    public var locale: String
    public var createdAt: Date
    public var duration: Double
    public var lines: [Line]

    public init(id: UUID = UUID(), title: String, sourceName: String, bookmark: Data?, locale: String,
                createdAt: Date = Date(), duration: Double, lines: [Line]) {
        self.version = Transcript.currentVersion
        self.id = id
        self.title = title
        self.sourceName = sourceName
        self.bookmark = bookmark
        self.locale = locale
        // Whole seconds, so a saved transcript reads back exactly (the file stores ISO 8601 seconds).
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        self.duration = duration
        self.lines = lines
    }

    /// All the words, one line per row, for Copy All.
    public var plainText: String { lines.map(\.text).joined(separator: "\n") }

    /// Fixes values a damaged or edited file could carry: times out of range or reversed,
    /// ids that repeat. Keeps every line's text.
    public func sanitized() -> Transcript {
        var copy = self
        copy.duration = TimeFormat.clamp(duration)
        copy.lines = lines.enumerated().map { index, line in
            let start = TimeFormat.clamp(line.start)
            return Line(id: index, start: start, end: max(start, TimeFormat.clamp(line.end)), text: line.text)
        }
        return copy
    }

    /// The index of the line playing at `time`: the last line that starts at or before it.
    public func lineIndex(at time: Double) -> Int? {
        guard !lines.isEmpty, time.isFinite, time >= lines[0].start else { return nil }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].start <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// A title from a file name: "Board meeting.m4a" becomes "Board meeting".
public func transcriptTitle(forFileNamed name: String) -> String {
    var base = name
    if let dot = name.lastIndex(of: "."), name.distance(from: dot, to: name.endIndex) <= 6 { base = String(name[..<dot]) }
    base = base.trimmingCharacters(in: .whitespacesAndNewlines)
    return base.isEmpty ? "Untitled recording" : base
}
