import Foundation

/// Merges per-window transcripts into one continuous string, removing the
/// overlap that the planner deliberately introduced between windows.
///
/// Strategy (ported from Android): exact longest suffix==prefix. Because
/// consecutive windows share `overlapMs` of audio, their transcripts share a
/// run of identical characters at the seam; we find the longest such run and
/// drop the duplicate from the second segment. No fuzzy matching — the seam is
/// only removed when the characters line up exactly, which avoids inventing or
/// deleting words.
public enum SegmentMerge {
    /// Stitch ordered segments. Empty/whitespace-only segments are skipped.
    public static func merge(_ segments: [String]) -> String {
        var acc: [Character] = []
        for raw in segments {
            let seg = Array(raw)
            if seg.allSatisfy({ $0.isWhitespace }) { continue }
            if acc.isEmpty {
                acc = seg
                continue
            }
            let k = longestOverlap(acc, seg)
            acc.append(contentsOf: seg[k...])
        }
        return String(acc).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Length of the longest `k` where the last `k` chars of `a` equal the
    /// first `k` chars of `b`. Returns 0 when there is no shared seam.
    static func longestOverlap(_ a: [Character], _ b: [Character]) -> Int {
        let maxK = min(a.count, b.count)
        guard maxK > 0 else { return 0 }
        var k = maxK
        while k >= 1 {
            var match = true
            let aStart = a.count - k
            for i in 0..<k where a[aStart + i] != b[i] {
                match = false
                break
            }
            if match { return k }
            k -= 1
        }
        return 0
    }
}
