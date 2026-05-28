import Foundation

public enum ThreadsUrl {
    private static let postRe = Re.compile(
        "https?://(?:www\\.)?threads\\.(?:net|com)/(@[^/?#]+/post/[^/?#]+)"
    )

    /// yt-dlp has no Threads extractor, but a post's `/embed` page exposes the
    /// media to the generic html5 extractor. Returns the embed URL for a Threads
    /// post URL (dropping tracking query params), or nil if it isn't one.
    public static func embedUrlOrNull(_ url: String) -> String? {
        guard let match = Re.firstMatch(postRe, in: url),
              let path = Re.group(match, 1, in: url) else { return nil }
        return "https://www.threads.net/\(path)/embed"
    }

    /// The post short-code (e.g. "DY3m2JQjXHZ") from a Threads URL, or nil.
    public static func postCode(_ url: String) -> String? {
        guard let match = Re.firstMatch(postRe, in: url),
              let path = Re.group(match, 1, in: url) else { return nil }
        return path.substringAfterLast("/")
    }
}
