import Foundation

/// A half-open-ish time slice `[startMs, endMs]` of the source audio. Windows
/// overlap by the planner's overlap amount so the seam between consecutive
/// transcriptions can be de-duplicated (`SegmentMerge`).
public struct TimeWindow: Equatable {
    public let index: Int
    public let startMs: Int64
    public let endMs: Int64

    public init(index: Int, startMs: Int64, endMs: Int64) {
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
    }

    public var durationMs: Int64 { endMs - startMs }
}

/// Splits a duration into overlapping windows. Platform-neutral: the engine
/// layer decodes only the PCM for each window (`decodeRange`) so memory stays
/// flat regardless of total length (the Android decision, ported verbatim).
///
/// - On-device whisper: large window + small overlap (e.g. 60s + 3s), used as
///   the checkpoint unit.
/// - Cloud OpenRouter: a hard cap drives the split (WAV 5min / m4a 10min)
///   because the upstream has a ~60s timeout and base64 inflates payloads.
public enum WindowPlanner {
    /// Plan overlapping windows over `totalMs`.
    ///
    /// - Parameters:
    ///   - totalMs: total audio duration in ms.
    ///   - windowMs: nominal window length (> 0).
    ///   - overlapMs: overlap between consecutive windows (>= 0, < windowMs).
    /// - Returns: ordered, contiguous-with-overlap windows covering `[0, totalMs]`.
    ///   Empty when `totalMs <= 0`. A single full-span window when the audio is
    ///   no longer than one window.
    public static func plan(totalMs: Int64, windowMs: Int64, overlapMs: Int64) -> [TimeWindow] {
        guard totalMs > 0, windowMs > 0 else { return [] }
        let overlap = max(0, min(overlapMs, windowMs - 1))
        if totalMs <= windowMs {
            return [TimeWindow(index: 0, startMs: 0, endMs: totalMs)]
        }
        let step = windowMs - overlap
        var windows: [TimeWindow] = []
        var start: Int64 = 0
        var index = 0
        while start < totalMs {
            let end = min(start + windowMs, totalMs)
            windows.append(TimeWindow(index: index, startMs: start, endMs: end))
            index += 1
            // The window that reaches the end is the last one.
            if end >= totalMs { break }
            start += step
        }
        return windows
    }
}
