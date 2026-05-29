import Foundation

public enum YtDlpInfoParser {
    private static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "bmp",
    ]

    /// Parse the JSON produced by `yt-dlp -J <url>` into a flat list of `MediaItem`.
    public static func parse(_ infoJson: String, requestUrl: String) -> [MediaItem] {
        guard let data = infoJson.data(using: .utf8),
              let root = try? JSONDecoder().decode(RawInfo.self, from: data) else {
            return []
        }
        let items: [MediaItem]
        if let entries = root.entries, !entries.isEmpty {
            items = entries.enumerated().compactMap { i, e in
                e?.toMediaItem(sourceUrl: requestUrl, playlistIndex: i + 1)
            }
        } else {
            items = [root.toMediaItem(sourceUrl: root.webpageUrl ?? requestUrl, playlistIndex: nil)]
        }
        // Drop items with nothing downloadable (e.g. nested-playlist containers).
        return items.filter { !$0.formats.isEmpty }
    }

    private static func syntheticFormat(ext: String, isImage: Bool) -> MediaFormat {
        MediaFormat(
            formatId: "best",
            ext: ext.isEmpty ? (isImage ? "jpg" : "mp4") : ext,
            label: isImage ? "Image" : "Video",
            height: nil,
            hasVideo: !isImage,
            hasAudio: !isImage,
            isImage: isImage,
            filesizeBytes: nil
        )
    }

    private static func buildLabel(
        isImage: Bool, hasVideo: Bool, hasAudio: Bool, height: Int?, ext: String
    ) -> String {
        if isImage { return "Image \(ext.uppercased())" }
        if hasVideo, let height { return "\(height)p \(ext)" + (hasAudio ? "" : " (video only)") }
        if hasVideo { return "Video \(ext)" + (hasAudio ? "" : " (video only)") }
        return "Audio \(ext)"
    }

    private struct RawInfo: Decodable {
        let type: String?
        let id: String?
        let title: String?
        let ext: String?
        let thumbnail: String?
        let duration: Double?
        let webpageUrl: String?
        let url: String?
        let formats: [RawFormat]?
        let entries: [RawInfo?]?

        enum CodingKeys: String, CodingKey {
            case type = "_type"
            case id, title, ext, thumbnail, duration, url, formats, entries
            case webpageUrl = "webpage_url"
        }

        func toMediaItem(sourceUrl: String, playlistIndex: Int?) -> MediaItem {
            let parsed = (formats ?? []).compactMap { $0.toMediaFormat() }
            let media = parsed.filter { $0.hasVideo || $0.hasAudio }
            let images = parsed.filter { $0.isImage }

            let isImage: Bool
            let chosen: [MediaFormat]
            if !media.isEmpty {
                isImage = false
                chosen = media
            } else if !images.isEmpty {
                isImage = true
                chosen = images
            } else if let url {
                let path = url.substringBefore("?").substringBefore("#")
                let e = ext ?? path.substringAfterLast("/").substringAfterLast(".", default: "")
                let img = imageExts.contains(e.lowercased())
                isImage = img
                chosen = [syntheticFormat(ext: e, isImage: img)]
            } else {
                isImage = false
                chosen = []
            }

            return MediaItem(
                sourceUrl: sourceUrl,
                playlistIndex: playlistIndex,
                id: id ?? "",
                title: title ?? id ?? "media",
                thumbnailUrl: thumbnail,
                durationSeconds: duration.map { Int64($0) },
                isImage: isImage,
                formats: chosen
            )
        }
    }

    private struct RawFormat: Decodable {
        let formatId: String?
        let ext: String?
        let vcodec: String?
        let acodec: String?
        let videoExt: String?
        let audioExt: String?
        let height: Int?
        let width: Int?
        let formatNote: String?
        let filesize: Int64?
        let filesizeApprox: Int64?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case ext, vcodec, acodec, height, width, filesize, url
            case formatId = "format_id"
            case formatNote = "format_note"
            case filesizeApprox = "filesize_approx"
            case videoExt = "video_ext"
            case audioExt = "audio_ext"
        }

        func toMediaFormat() -> MediaFormat? {
            let e = (ext ?? "").lowercased()
            let isImage = imageExts.contains(e)
            // An empty ext means "absent", not a real track (some extractors emit
            // video_ext == "" for audio-only streams) — treat it like "none".
            let hasVideo = (vcodec != nil && vcodec != "none") || (videoExt.map { $0 != "none" && !$0.isEmpty } ?? false)
            let hasAudio = (acodec != nil && acodec != "none") || (audioExt.map { $0 != "none" && !$0.isEmpty } ?? false)
            // Drop storyboards / non-media rows (e.g. mhtml previews).
            if !isImage && !hasVideo && !hasAudio { return nil }
            guard let fid = formatId else { return nil }
            return MediaFormat(
                formatId: fid,
                ext: e.isEmpty ? "bin" : e,
                label: buildLabel(isImage: isImage, hasVideo: hasVideo, hasAudio: hasAudio, height: height, ext: e),
                height: height,
                hasVideo: hasVideo,
                hasAudio: hasAudio,
                isImage: isImage,
                filesizeBytes: filesize ?? filesizeApprox,
                vcodec: vcodec,
                acodec: acodec
            )
        }
    }
}
