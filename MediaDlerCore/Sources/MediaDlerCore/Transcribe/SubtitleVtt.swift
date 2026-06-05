import Foundation

/// Turns a WebVTT subtitle track into plain transcript text: drops the header,
/// cue numbers, timing lines and inline tags, then de-duplicates the rolling
/// repeated lines that YouTube auto-captions emit.
///
/// This is the "YouTube CC shortcut" path — when a site already has captions we
/// reuse them verbatim and skip the audio download + recognition entirely.
public enum SubtitleVtt {
    public static func toPlainText(_ vtt: String) -> String {
        var out: [String] = []
        for rawLine in vtt.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "WEBVTT" || line.hasPrefix("WEBVTT") { continue }
            // Header/metadata blocks emitted before the first cue.
            if line.hasPrefix("Kind:") || line.hasPrefix("Language:")
                || line.hasPrefix("NOTE") || line.hasPrefix("STYLE")
                || line.hasPrefix("REGION") { continue }
            // Cue timing line: "00:00:01.000 --> 00:00:04.000 align:start …"
            if line.contains("-->") { continue }
            // Bare cue index numbers.
            if Int(line) != nil { continue }
            line = stripTags(line)
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Collapse rolling duplicates (auto-caption windows repeat the last
            // line as the next cue's first line).
            if out.last == line { continue }
            out.append(line)
        }
        // A late pass removes a line fully contained at the tail of the prior
        // one (rolling captions where the previous line grew).
        return dedupeRolling(out).joined(separator: "\n")
    }

    /// Removes inline VTT/HTML tags: `<c>`, `</c>`, `<00:00:00.000>`, `<v Bob>`.
    static func stripTags(_ s: String) -> String {
        var result = ""
        var insideTag = false
        for ch in s {
            if ch == "<" { insideTag = true; continue }
            if ch == ">" { insideTag = false; continue }
            if !insideTag { result.append(ch) }
        }
        return result
    }

    /// Drops a line that is identical to the previous one after trimming, and
    /// drops a previous line fully repeated as a prefix of the next (the rolling
    /// auto-caption pattern). Conservative: only exact-equality and direct
    /// prefix-growth are removed, never partial fuzzy overlaps.
    static func dedupeRolling(_ lines: [String]) -> [String] {
        var out: [String] = []
        for line in lines {
            if let last = out.last {
                if last == line { continue }
                // Previous line grew into this one: keep only the longer.
                if line.hasPrefix(last) { out.removeLast() }
            }
            out.append(line)
        }
        return out
    }
}
