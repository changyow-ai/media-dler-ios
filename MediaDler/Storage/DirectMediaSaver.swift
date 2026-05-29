import Foundation
import MediaDlerCore

enum DirectDownloadError: LocalizedError {
    case badURL
    case http(Int)
    case photosDenied
    case truncated(received: Int64, expected: Int64)

    var errorDescription: String? {
        switch self {
        case .badURL: return "媒體連結無效。"
        case .http(let code): return "下載失敗（HTTP \(code)）。"
        case .photosDenied: return "沒有「照片」新增權限，請到設定開啟。"
        case .truncated(let received, let expected):
            return "下載不完整（收到 \(received) / 應有 \(expected) bytes），請重試。"
        }
    }
}

/// Downloads a direct media URL (e.g. a Threads cdninstagram/fbcdn link) to a
/// temp file and returns it — video or image. Used for media that yt-dlp doesn't
/// handle, so it doesn't go through YtDlpEngine. The caller routes the file to
/// Photos or the app folder via `MediaSink`.
enum DirectMediaSaver {
    /// Downloads `item` to a temp file with the right extension and returns it.
    static func download(_ item: MediaItem) async throws -> URL {
        guard let url = URL(string: item.sourceUrl) else { throw DirectDownloadError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(ThreadsService.userAgent, forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DirectDownloadError.http(http.statusCode)
        }

        // Give the temp file the right extension so Photos / the Files app
        // recognise it correctly.
        let ext = item.formats.first?.ext ?? (item.isImage ? "jpg" : "mp4")
        let named = tempURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try? FileManager.default.moveItem(at: tempURL, to: named)
        return named
    }
}
