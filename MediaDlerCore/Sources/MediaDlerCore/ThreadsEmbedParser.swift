import Foundation

/// Extracts direct CDN media URLs (videos + post images) from a Threads `/embed`
/// page's HTML. Avatars (profile-pic namespace) and static UI assets are skipped.
public enum ThreadsEmbedParser {
    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
    // Threads images live on *.cdninstagram.com, but videos are now served from
    // *.fbcdn.net (e.g. instagram.<dc>.fna.fbcdn.net). Match both, or video posts
    // resolve to zero media.
    private static let cdnRe = Re.compile(
        "https://[a-z0-9_.-]*(?:cdninstagram\\.com|fbcdn\\.net)/[^\"'\\\\ )<>]+",
        caseInsensitive: true
    )
    private static let profilePicRe = Re.compile("/t51\\.\\d+-19/")

    public static func parse(embedHtml: String, postUrl: String) -> [MediaItem] {
        let html = embedHtml
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
        let code = ThreadsUrl.postCode(postUrl) ?? "threads"

        var seen = Set<String>()
        var videos: [String] = []
        var images: [String] = []
        for match in Re.allMatches(cdnRe, in: html) {
            guard let r = Range(match.range, in: html) else { continue }
            let url = String(html[r])
            if url.contains("static.cdninstagram.com") { continue }
            let path = url.substringBefore("?")
            let ext = path.substringAfterLast(".", default: "").lowercased()
            if ext != "mp4" && !imageExts.contains(ext) { continue }
            if !seen.insert(path).inserted { continue }
            if ext == "mp4" {
                videos.append(url)
            } else if !Re.contains(profilePicRe, in: url) {
                images.append(url)
            }
        }

        var items: [MediaItem] = []
        for (i, u) in videos.enumerated() {
            let name = "ThreadsVideo_\(code)" + (videos.count > 1 ? "_\(i + 1)" : "")
            items.append(build(url: u, name: name, isImage: false))
        }
        for (i, u) in images.enumerated() {
            items.append(build(url: u, name: "ThreadsImage_\(code)_\(i + 1)", isImage: true))
        }
        return items
    }

    private static func build(url: String, name: String, isImage: Bool) -> MediaItem {
        let ext = url.substringBefore("?")
            .substringAfterLast(".", default: isImage ? "jpg" : "mp4")
            .lowercased()
        return MediaItem(
            sourceUrl: url,
            playlistIndex: nil,
            id: name,
            title: name,
            thumbnailUrl: isImage ? url : nil,
            durationSeconds: nil,
            isImage: isImage,
            formats: [
                MediaFormat(
                    formatId: "0",
                    ext: ext,
                    label: isImage ? "圖片" : "影片",
                    height: nil,
                    hasVideo: !isImage,
                    hasAudio: !isImage,
                    isImage: isImage,
                    filesizeBytes: nil
                )
            ]
        )
    }
}
