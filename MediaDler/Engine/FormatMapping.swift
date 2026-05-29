import Foundation
import MediaDlerCore
import YoutubeDL

/// Bridges between YoutubeDL-iOS's `Format`/`Info` and MediaDlerCore's
/// platform-neutral `MediaFormat`/`MediaItem`.
enum FormatMapping {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "bmp"]

    static func mediaFormat(_ f: Format) -> MediaFormat {
        let ext = f.ext.lowercased()
        let isImage = imageExts.contains(ext)
        // Treat an empty ext as "absent", not as a real track: some extractors
        // emit video_ext == "" (rather than "none") for an audio-only stream,
        // which would otherwise misclassify it as having video.
        let hasVideo = (f.vcodec ?? "none") != "none" || (f.video_ext != "none" && !f.video_ext.isEmpty)
        let hasAudio = (f.acodec ?? "none") != "none" || (f.audio_ext != "none" && !f.audio_ext.isEmpty)
        let label: String
        if isImage {
            label = "圖片 \(ext.uppercased())"
        } else if hasVideo, let h = f.height {
            label = "\(h)p" + (hasAudio ? "" : " (僅影像)")
        } else if hasVideo {
            label = "影片 \(ext)" + (hasAudio ? "" : " (僅影像)")
        } else {
            label = "音訊 \(ext)"
        }
        return MediaFormat(
            formatId: f.format_id,
            ext: ext.isEmpty ? "bin" : ext,
            label: label,
            height: f.height,
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            isImage: isImage,
            filesizeBytes: f.filesize.map(Int64.init),
            vcodec: f.vcodec,
            acodec: f.acodec
        )
    }

    static func mediaItem(from info: Info, formats: [Format], sourceUrl: String) -> MediaItem {
        let mapped = formats.map(mediaFormat)
        let hasAV = mapped.contains { $0.hasVideo || $0.hasAudio }
        let isImage = !hasAV && mapped.contains { $0.isImage }
        return MediaItem(
            sourceUrl: sourceUrl,
            playlistIndex: nil,
            id: info.id,
            title: info.title,
            thumbnailUrl: info.thumbnail,
            durationSeconds: info.duration.map { Int64($0) },
            isImage: isImage,
            formats: mapped
        )
    }
}
