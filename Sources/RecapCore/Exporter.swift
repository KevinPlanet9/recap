import Foundation

/// The five export formats.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt, md, srt, vtt, json

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public var label: String {
        switch self {
        case .txt: return "Plain Text (.txt)"
        case .md: return "Markdown (.md)"
        case .srt: return "Subtitles, SubRip (.srt)"
        case .vtt: return "Subtitles, WebVTT (.vtt)"
        case .json: return "JSON (.json)"
        }
    }
}

public enum Exporter {
    public static func render(_ transcript: Transcript, as format: ExportFormat) throws -> String {
        let t = transcript.sanitized()
        switch format {
        case .txt:
            return t.lines.map { "[\(TimeFormat.display($0.start))] \($0.text)" }.joined(separator: "\n") + "\n"
        case .md:
            var out = "# \(oneLine(t.title))\n\n"
            out += "_\(oneLine(t.sourceName)), transcribed \(dateLabel(t.createdAt)). On-device transcript: check names and numbers by ear._\n\n"
            out += t.lines.map { "**\(TimeFormat.display($0.start))** \(markdownSafe($0.text))  " }.joined(separator: "\n")
            return out + "\n"
        case .srt:
            return t.lines.enumerated().map { index, line in
                "\(index + 1)\n\(TimeFormat.srt(line.start)) --> \(TimeFormat.srt(cueEnd(line)))\n\(subtitleText(line.text))\n"
            }.joined(separator: "\n")
        case .vtt:
            let cues = t.lines.map { line in
                "\(TimeFormat.vtt(line.start)) --> \(TimeFormat.vtt(cueEnd(line)))\n\(subtitleText(line.text))\n"
            }
            return "WEBVTT\n\n" + cues.joined(separator: "\n")
        case .json:
            let export = JSONExport(title: t.title, source: t.sourceName, locale: t.locale,
                                    createdAt: t.createdAt, duration: t.duration,
                                    lines: t.lines.map { .init(start: $0.start, end: $0.end, text: $0.text) })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return String(decoding: try encoder.encode(export), as: UTF8.self) + "\n"
        }
    }

    /// Subtitle text on one line, with nothing that can end a cue or fake a timing line:
    /// no line breaks (a blank line ends a cue) and no "-->".
    public static func subtitleText(_ text: String) -> String {
        var out = oneLine(text)
        while out.contains("-->") { out = out.replacingOccurrences(of: "-->", with: "->") }
        return out.isEmpty ? "..." : out
    }

    /// A cue lasts at least a second so very short lines stay readable.
    static func cueEnd(_ line: Line) -> Double { max(line.end, line.start + 1) }

    static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Escapes characters Markdown would read as formatting at the start of a line or around words.
    static func markdownSafe(_ text: String) -> String {
        var out = ""
        for ch in oneLine(text) {
            if "\\`*_[]<>#|".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    struct JSONExport: Codable {
        struct Row: Codable { var start: Double; var end: Double; var text: String }
        var title: String
        var source: String
        var locale: String
        var createdAt: Date
        var duration: Double
        var lines: [Row]
    }
}
