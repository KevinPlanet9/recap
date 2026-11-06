import Foundation

/// Turns seconds into the time strings Recap shows and exports.
/// Every conversion clamps first: a damaged file with a huge or invalid number must never crash.
public enum TimeFormat {
    /// The longest time Recap will show: 99 hours. Anything larger is treated as damaged and clamped.
    public static let maximumSeconds: Double = 99 * 3600 + 59 * 60 + 59.999

    /// Clamps to 0...maximumSeconds. NaN and infinity become 0.
    public static func clamp(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, 0), maximumSeconds)
    }

    /// Whole milliseconds, safe to convert to Int after clamping.
    public static func milliseconds(_ seconds: Double) -> Int {
        Int((clamp(seconds) * 1000).rounded(.down))
    }

    /// "4:05" under an hour, "1:04:05" from an hour on. Used on screen and in text exports.
    public static func display(_ seconds: Double) -> String {
        let total = milliseconds(seconds) / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "00:04:05,250" for SubRip (.srt).
    public static func srt(_ seconds: Double) -> String { stamp(seconds, separator: ",") }

    /// "00:04:05.250" for WebVTT (.vtt).
    public static func vtt(_ seconds: Double) -> String { stamp(seconds, separator: ".") }

    private static func stamp(_ seconds: Double, separator: String) -> String {
        let ms = milliseconds(seconds)
        let h = ms / 3_600_000, m = (ms % 3_600_000) / 60_000, s = (ms % 60_000) / 1000, f = ms % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, separator, f)
    }
}
