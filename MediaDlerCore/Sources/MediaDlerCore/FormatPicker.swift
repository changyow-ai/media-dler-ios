import Foundation

/// YoutubeDL-iOS performs format selection client-side: its `download`
/// `formatSelector` closure returns the concrete `Format` objects to fetch
/// (the library then merges a video-only + audio-only pair itself). This is
/// unlike the Android engine, which takes a yt-dlp `-f` string.
///
/// `FormatPicker` is the pure equivalent of Android's `FormatSelector`,
/// expressed as a choice of `format_id`s over the available `MediaFormat`s.
/// The engine maps those ids back to the library's `Format` structs.
public enum FormatPicker {
    /// The `format_id`s to download for `selection`, given all `formats`
    /// available for the item. An empty result means nothing suitable was
    /// found (the caller should surface an error).
    public static func pick(_ formats: [MediaFormat], selection: FormatSelection) -> [String] {
        switch selection {
        case .imageOriginal:
            return bestImage(formats).map { [$0.formatId] } ?? []
        case .audio:
            if let a = bestAudioOnly(formats) { return [a.formatId] }
            if let m = bestMuxed(formats) { return [m.formatId] }
            return []
        case .bestVideo:
            return pickVideo(formats, maxHeight: nil)
        case .cappedVideo(let h):
            return pickVideo(formats, maxHeight: h)
        case .specificFormat(let f):
            if f.isImage || f.hasAudio { return [f.formatId] }
            if let a = bestAudioOnly(formats) { return [f.formatId, a.formatId] }
            return [f.formatId]
        }
    }

    /// Pick the best video stream (optionally capped at `maxHeight`); if it is
    /// video-only, pair it with the best audio so the engine can merge.
    private static func pickVideo(_ formats: [MediaFormat], maxHeight: Int?) -> [String] {
        let videos = formats.filter { $0.hasVideo }
        guard !videos.isEmpty else {
            // No video at all — fall back to anything playable.
            if let m = bestMuxed(formats) { return [m.formatId] }
            if let a = bestAudioOnly(formats) { return [a.formatId] }
            return []
        }
        let capped: [MediaFormat]
        if let maxHeight {
            // Use inferredHeight so 'hd'/'sd'-style ids (no numeric height) are
            // capped consistently with how byQuality ranks them — otherwise a
            // height-less 'hd' (720p) reads as 0 and slips under any cap.
            let within = videos.filter { inferredHeight($0) <= maxHeight }
            capped = within.isEmpty ? videos : within
        } else {
            capped = videos
        }
        let photoCompatible = capped.filter(isPhotoCompatibleVideo)
        let candidates = photoCompatible.isEmpty ? capped : photoCompatible
        guard let best = candidates.max(by: byQuality) else { return [] }
        if best.hasAudio { return [best.formatId] }
        if let a = bestAudioOnly(formats) { return [best.formatId, a.formatId] }
        return [best.formatId]
    }

    private static func bestMuxed(_ formats: [MediaFormat]) -> MediaFormat? {
        formats.filter { $0.hasVideo && $0.hasAudio }.max(by: byQuality)
    }

    private static func bestAudioOnly(_ formats: [MediaFormat]) -> MediaFormat? {
        let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }
        // Prefer audio AVFoundation can actually mux into mp4 (AAC / m4a). The
        // in-app merge can't read Opus/webm, so only fall back to it when no
        // compatible audio stream exists.
        let compatible = audioOnly.filter(isAVFoundationCompatibleAudio)
        return (compatible.isEmpty ? audioOnly : compatible).max(by: byFilesize)
    }

    private static func isAVFoundationCompatibleAudio(_ format: MediaFormat) -> Bool {
        if ["m4a", "mp4", "aac"].contains(format.ext.lowercased()) { return true }
        guard let codec = format.acodec?.lowercased(), codec != "none" else { return false }
        return codec.hasPrefix("mp4a") || codec.hasPrefix("aac")
    }

    private static func bestImage(_ formats: [MediaFormat]) -> MediaFormat? {
        let images = formats.filter { $0.isImage }
        return images.max(by: byFilesize) ?? images.first
    }

    /// Higher resolution wins; ties broken by larger file size.
    private static func byQuality(_ a: MediaFormat, _ b: MediaFormat) -> Bool {
        let ha = inferredHeight(a), hb = inferredHeight(b)
        if ha != hb { return ha < hb }
        return (a.filesizeBytes ?? 0) < (b.filesizeBytes ?? 0)
    }

    private static func byFilesize(_ a: MediaFormat, _ b: MediaFormat) -> Bool {
        (a.filesizeBytes ?? 0) < (b.filesizeBytes ?? 0)
    }

    private static func isPhotoCompatibleVideo(_ format: MediaFormat) -> Bool {
        guard format.hasVideo, format.ext == "mp4" else { return false }
        guard let codec = format.vcodec?.lowercased(), codec != "none" else {
            return true
        }
        return codec.hasPrefix("avc1") || codec.hasPrefix("h264")
    }

    private static func inferredHeight(_ format: MediaFormat) -> Int {
        if let height = format.height { return height }
        switch format.formatId.lowercased() {
        case "hd": return 720
        case "sd": return 360
        default: return 0
        }
    }
}
