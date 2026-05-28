import Foundation

public enum UrlExtractor {
    private static let urlRe = Re.compile("https?://[^\\s<>\"'\\\\]+")
    private static let sentenceTrailing: Set<Character> = [".", ",", ";", ":", "!", "?", "\""]

    /// Returns the first http(s) URL in `text`, stripped of trailing prose
    /// punctuation, or nil.
    public static func firstUrl(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let match = Re.firstMatch(urlRe, in: text),
              let r = Range(match.range, in: text) else { return nil }
        var url = String(text[r])

        while let last = url.last, sentenceTrailing.contains(last) {
            url.removeLast()
        }
        // Strip a trailing bracket only when it is unbalanced (belongs to the
        // surrounding sentence), so paths like /wiki/Foo_(bar) stay intact.
        while let last = url.last {
            let unbalanced: Bool
            switch last {
            case ")": unbalanced = url.count(of: "(") < url.count(of: ")")
            case "]": unbalanced = url.count(of: "[") < url.count(of: "]")
            case "}": unbalanced = url.count(of: "{") < url.count(of: "}")
            default: unbalanced = false
            }
            if unbalanced { url.removeLast() } else { break }
        }
        return url.isEmpty ? nil : url
    }
}

private extension String {
    func count(of character: Character) -> Int {
        reduce(0) { $1 == character ? $0 + 1 : $0 }
    }
}
