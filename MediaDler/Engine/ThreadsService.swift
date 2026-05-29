import Foundation
import MediaDlerCore

/// yt-dlp has no Threads extractor, so we resolve Threads posts ourselves:
/// fetch the `/embed` page with a browser User-Agent and parse the direct
/// cdninstagram media URLs out of it (logic lives in MediaDlerCore). The
/// resulting MediaItems carry direct URLs and are downloaded by DirectMediaSaver
/// (not the yt-dlp engine).
enum ThreadsService {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func isThreads(_ urlString: String) -> Bool {
        ThreadsUrl.embedUrlOrNull(urlString) != nil
    }

    static func extract(_ urlString: String) async throws -> [MediaItem] {
        guard let embed = ThreadsUrl.embedUrlOrNull(urlString), let embedURL = URL(string: embed) else {
            return []
        }
        var request = URLRequest(url: embedURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        return ThreadsEmbedParser.parse(embedHtml: html, postUrl: urlString)
    }
}
