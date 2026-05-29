import Foundation
import Photos
import MediaDlerCore

/// The kind of content a finished temp file holds. Decides Photos asset type
/// and whether the app-folder fallback is forced (audio can't go to Photos).
enum MediaContentKind {
    case video, image, audio

    var defaultExt: String {
        switch self {
        case .video: return "mp4"
        case .image: return "jpg"
        case .audio: return "m4a"
        }
    }
}

/// Saves a downloaded media file to the Photos library, sharing the permission
/// dance across the engine and the direct (Threads) path.
enum PhotosSaver {
    static func save(fileURL: URL, isImage: Bool) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            throw DirectDownloadError.photosDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: isImage ? .photo : .video, fileURL: fileURL, options: nil)
        }
    }
}

/// Final resting place for a downloaded temp file, per the user's storage
/// choice. Audio always lands in the app folder (the Photos library can't hold
/// audio); video/images follow `destination`.
enum MediaSink {
    struct Saved {
        /// Set only when the file lives in the app folder (shareable + deletable).
        var localPath: String?
        /// Human-readable status shown in the history row.
        var outputUri: String
        var mimeType: String?
    }

    static func save(
        tempFile: URL,
        kind: MediaContentKind,
        title: String,
        destination: StorageDestination
    ) async throws -> Saved {
        let ext = tempFile.pathExtension.isEmpty ? kind.defaultExt : tempFile.pathExtension

        if kind == .audio || destination == .appFolder {
            guard let saved = DocumentsStorage.save(tempFile, preferredName: title) else {
                throw DirectDownloadError.badURL
            }
            return Saved(
                localPath: saved.path,
                outputUri: "已存到 App 資料夾 · \(saved.lastPathComponent)",
                mimeType: mime(kind, ext)
            )
        }

        try await PhotosSaver.save(fileURL: tempFile, isImage: kind == .image)
        return Saved(
            localPath: nil,
            outputUri: "已儲存到「照片」App",
            mimeType: mime(kind, ext)
        )
    }

    private static func mime(_ kind: MediaContentKind, _ ext: String) -> String {
        switch kind {
        case .video: return "video/\(ext)"
        case .image: return "image/\(ext)"
        case .audio: return "audio/\(ext)"
        }
    }
}
