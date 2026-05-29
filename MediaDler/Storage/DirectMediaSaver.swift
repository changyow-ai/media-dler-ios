import Foundation
import Photos
import MediaDlerCore

enum DirectDownloadError: LocalizedError {
    case badURL
    case http(Int)
    case photosDenied

    var errorDescription: String? {
        switch self {
        case .badURL: return "媒體連結無效。"
        case .http(let code): return "下載失敗（HTTP \(code)）。"
        case .photosDenied: return "沒有「照片」新增權限，請到設定開啟。"
        }
    }
}

/// Downloads a direct media URL (e.g. a Threads cdninstagram link) and saves it
/// straight into the Photos library — video or image. Used for media that yt-dlp
/// doesn't handle, so it doesn't go through YtDlpEngine.
enum DirectMediaSaver {
    static func saveToPhotos(_ item: MediaItem) async throws {
        guard let url = URL(string: item.sourceUrl) else { throw DirectDownloadError.badURL }

        try await ensurePhotosPermission()

        var request = URLRequest(url: url)
        request.setValue(ThreadsService.userAgent, forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DirectDownloadError.http(http.statusCode)
        }

        // Give the temp file the right extension so Photos imports it correctly.
        let ext = item.formats.first?.ext ?? (item.isImage ? "jpg" : "mp4")
        let named = tempURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try? FileManager.default.moveItem(at: tempURL, to: named)
        defer { try? FileManager.default.removeItem(at: named) }

        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: item.isImage ? .photo : .video, fileURL: named, options: nil)
        }
    }

    private static func ensurePhotosPermission() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            throw DirectDownloadError.photosDenied
        }
    }
}
