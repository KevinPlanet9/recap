import Foundation

/// Finds lines that contain every word of a search, ignoring case and accents.
public enum TranscriptSearch {
    public static func matches(_ query: String, in lines: [Line]) -> [Int] {
        let terms = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return Array(lines.indices) }
        return lines.indices.filter { index in
            let text = fold(lines[index].text)
            return terms.allSatisfy { text.contains($0) }
        }
    }

    /// Lowercase, without accents, with curly quotes made straight, so "Cafe" finds "café".
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }
}
