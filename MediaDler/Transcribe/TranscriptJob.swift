import Foundation
import MediaDlerCore

enum TranscribeError: LocalizedError {
    case busy(String)
    case engineUnavailable(String)
    case noApiKey
    case canceled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .busy(let m): return m
        case .engineUnavailable(let m): return m
        case .noApiKey: return "尚未設定雲端 API 金鑰。請到設定頁貼上 OpenRouter 金鑰。"
        case .canceled: return "已取消。"
        case .message(let m): return m
        }
    }
}

/// Where a transcription job's audio comes from. The id is derived from the
/// source so re-submitting the same input maps to the same resumable job.
enum TranscribeSource: Codable, Equatable {
    case localFile(path: String)
    case link(url: String)
}

enum JobStatus: String, Codable { case pending, running, completed, failed, canceled }

/// Persisted state for one transcription. High-frequency progress lives only in
/// memory (TranscriptionManager); the store is written at window checkpoints
/// and terminal states. `engineId` guards against mixing checkpoints across
/// engines (different windowing → seam mismatch → force clean re-transcribe).
struct TranscriptJob: Codable, Equatable, Identifiable {
    let id: String
    var source: TranscribeSource
    var title: String
    var status: JobStatus
    var progress: Double
    /// Raw merged transcript so far (NO inserted line breaks — display layer
    /// formats it; seam-dedup needs the raw form).
    var text: String
    var detectedLanguage: String?
    var completedWindows: Int
    var totalWindows: Int
    var engineId: String
    /// Human-readable "轉譯方式" recorded at start (TranscribeMethod.label).
    var methodLabel: String
    var errorMessage: String?
    let createdAt: Double
    var durationMs: Int64

    var isTerminal: Bool { status == .completed || status == .failed || status == .canceled }
}
