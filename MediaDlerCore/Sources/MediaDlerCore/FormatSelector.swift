import Foundation

public enum FormatSelector {
    /// yt-dlp CLI arguments (format selection / audio extraction) for a `selection`.
    public static func args(_ selection: FormatSelection) -> [String] {
        switch selection {
        case .imageOriginal:
            return []
        case .bestVideo:
            return ["-f", "bv*+ba/b"]
        case .cappedVideo(let h):
            // Prefer best <= cap; otherwise fall back to an uncapped video+audio
            // merge. DASH-only sites (e.g. Bilibili) have no muxed "b", so ending
            // in "/b" alone errors with "Requested format is not available".
            // -S res:H then picks the resolution closest to the cap.
            return ["-f", "bv*[height<=\(h)]+ba/b[height<=\(h)]/bv*+ba/b", "-S", "res:\(h)"]
        case .audio(let audioFormat):
            return ["-x", "--audio-format", audioFormat.ext, "-f", "ba/b"]
        case .specificFormat(let f):
            // For a video-only stream, merge best audio; never fall back to the
            // muted video-only stream — go straight to best combined.
            let sel = (f.hasAudio || f.isImage) ? f.formatId : "\(f.formatId)+ba/b"
            return ["-f", sel]
        }
    }
}
