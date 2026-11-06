import Foundation

/// Groups words into lines as they arrive. A line ends at the end of a sentence, at a pause of
/// about 1.2 seconds, or when it reaches 20 seconds or 240 characters, whichever comes first.
public struct LineBuilder: Sendable {
    public struct Limits: Sendable {
        public var pause: Double = 1.2
        public var maxDuration: Double = 20
        public var maxCharacters: Int = 240
        public init() {}
    }

    public let limits: Limits
    public private(set) var lines: [Line] = []
    private var pending: [Word] = []

    public init(limits: Limits = Limits()) {
        self.limits = limits
    }

    /// Adds words in time order and returns the lines this closed, if any.
    @discardableResult
    public mutating func add(_ words: [Word]) -> [Line] {
        var closed: [Line] = []
        for raw in words {
            let text = raw.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = TimeFormat.clamp(raw.start)
            let word = Word(text: text, start: start, end: max(start, TimeFormat.clamp(raw.end)))
            if let last = pending.last {
                let gap = word.start - last.end
                let lineStart = pending[0].start
                let wouldBe = currentLength + 1 + word.text.count
                if gap >= limits.pause || word.end - lineStart > limits.maxDuration || wouldBe > limits.maxCharacters {
                    if let line = closePending() { closed.append(line) }
                }
            }
            pending.append(word)
            if LineBuilder.endsSentence(word.text), let line = closePending() {
                closed.append(line)
            }
        }
        return closed
    }

    /// Closes the last open line at the end of the recording.
    @discardableResult
    public mutating func finish() -> Line? { closePending() }

    /// The words of the line still being built, for showing progress.
    public var pendingText: String { LineBuilder.join(pending) }

    private var currentLength: Int { LineBuilder.join(pending).count }

    private mutating func closePending() -> Line? {
        guard let first = pending.first, let last = pending.last else { return nil }
        let line = Line(id: lines.count, start: first.start, end: last.end, text: LineBuilder.join(pending))
        lines.append(line)
        pending.removeAll()
        return line
    }

    static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201D}\u{2019})]"))
        guard let last = trimmed.last else { return false }
        return ".?!\u{2026}".contains(last)
    }

    /// Joins words with single spaces, without a space before closing punctuation the engine
    /// sometimes reports as its own word.
    static func join(_ words: [Word]) -> String {
        var out = ""
        for word in words {
            if out.isEmpty {
                out = word.text
            } else if let first = word.text.first, ",.;:?!%)\u{2026}".contains(first) {
                out += word.text
            } else {
                out += " " + word.text
            }
        }
        return out
    }
}
