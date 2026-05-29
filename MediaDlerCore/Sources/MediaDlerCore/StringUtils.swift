import Foundation

/// Kotlin-style substring helpers, so the ported parsers match the Android
/// `:core` semantics exactly.
extension String {
    /// Substring before the first `delimiter`, or the whole string if absent.
    func substringBefore(_ delimiter: Character) -> String {
        guard let idx = firstIndex(of: delimiter) else { return self }
        return String(self[startIndex..<idx])
    }

    /// Substring after the last `delimiter`, or the whole string if absent.
    func substringAfterLast(_ delimiter: Character) -> String {
        guard let idx = lastIndex(of: delimiter) else { return self }
        return String(self[index(after: idx)...])
    }

    /// Substring after the last `delimiter`, or `fallback` if absent.
    func substringAfterLast(_ delimiter: Character, default fallback: String) -> String {
        guard let idx = lastIndex(of: delimiter) else { return fallback }
        return String(self[index(after: idx)...])
    }
}

/// Returns the range of the first match, or all matches, for a precompiled pattern.
enum Re {
    static func compile(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        // Patterns are compile-time constants known to be valid.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    static func firstMatch(_ re: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func allMatches(_ re: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: text) else { return nil }
        return String(text[r])
    }

    static func contains(_ re: NSRegularExpression, in text: String) -> Bool {
        firstMatch(re, in: text) != nil
    }
}
