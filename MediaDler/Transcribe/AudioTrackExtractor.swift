import Foundation
import AVFoundation

enum AudioTrackExtractorError: LocalizedError {
    case cannotExport
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cannotExport: return "無法建立音訊匯出工作（格式可能不支援無損搬移）。"
        case .failed(let why): return "取出聲音失敗：\(why)"
        }
    }
}

/// Losslessly extracts the audio track of a video into an `.m4a` using
/// `AVAssetExportSession` passthrough (no re-encoding). The `.m4a` output
/// container only holds audio, so the video track is dropped automatically —
/// the bytes of the audio track are moved verbatim (Android's remux decision).
enum AudioTrackExtractor {
    static func extract(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AudioTrackExtractorError.cannotExport
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        export.outputURL = out
        export.outputFileType = .m4a

        return try await withCheckedThrowingContinuation { cont in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    cont.resume(returning: out)
                case .failed, .cancelled:
                    cont.resume(throwing: AudioTrackExtractorError.failed(
                        export.error?.localizedDescription ?? "匯出未完成"))
                default:
                    cont.resume(throwing: AudioTrackExtractorError.failed("匯出狀態異常"))
                }
            }
        }
    }
}
