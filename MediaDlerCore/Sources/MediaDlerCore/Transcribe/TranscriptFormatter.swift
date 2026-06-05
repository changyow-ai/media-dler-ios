import Foundation

/// Breaks a raw (single-line) transcript into readable lines FOR DISPLAY ONLY.
/// The raw transcript is kept unbroken so the seam de-dup in `SegmentMerge`
/// keeps working on exact suffix==prefix; this formatter is applied only when
/// showing / copying / sharing.
///
/// Rules (ported from Android):
/// - Hard break right after a sentence-ending mark (。！？!?…), keeping any
///   trailing closing quotes/brackets on the same line.
/// - For long runs with no sentence end, soft break at the last clause
///   separator (，、,；;) before the wrap limit, else hard-break at the limit.
/// - Never fabricate a sentence boundary where the text has none.
public enum TranscriptFormatter {
    static let hardEnders: Set<Character> = ["。", "！", "？", "!", "?", "…"]
    static let softBreakers: Set<Character> = ["，", "、", ",", "；", ";", " ", "　"]
    static let closers: Set<Character> = ["」", "』", "”", "’", "）", ")", "】", "》", "\""]

    public static func format(_ raw: String, softWrapAt: Int = 40) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let chars = Array(trimmed)

        var lines: [String] = []
        var line: [Character] = []
        var lastSoftIndex: Int? = nil

        func flush() {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { lines.append(s) }
            line.removeAll(keepingCapacity: true)
            lastSoftIndex = nil
        }

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            line.append(ch)

            if hardEnders.contains(ch) {
                var j = i + 1
                while j < chars.count, closers.contains(chars[j]) {
                    line.append(chars[j])
                    j += 1
                }
                i = j
                flush()
                continue
            }

            if softBreakers.contains(ch) { lastSoftIndex = line.count }

            if line.count >= softWrapAt {
                if let idx = lastSoftIndex, idx > 0, idx < line.count {
                    let head = String(line[0..<idx]).trimmingCharacters(in: .whitespaces)
                    if !head.isEmpty { lines.append(head) }
                    line = Array(line[idx...])
                    lastSoftIndex = nil
                } else {
                    flush()
                }
            }
            i += 1
        }
        flush()
        return lines.joined(separator: "\n")
    }
}
