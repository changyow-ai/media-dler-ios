import Foundation

/// A decoded audio source ready for transcription. Platform-neutral: the file
/// already lives in the app's private storage (a copied local file or a
/// downloaded audio track); duration is measured by the platform layer.
public struct AudioRef: Equatable {
    /// Absolute on-disk path of the audio/media file (kept as a string so the
    /// model stays Foundation-only and trivially Codable across the app layer).
    public let path: String
    /// Total duration in milliseconds (read from the asset by the app layer).
    public let durationMs: Int64

    public init(path: String, durationMs: Int64) {
        self.path = path
        self.durationMs = durationMs
    }
}

/// One time-coded chunk of transcript. Cloud (OpenRouter) returns no
/// timestamps, so `startMs`/`endMs` fall back to the window bounds.
public struct TranscriptSegment: Equatable {
    public let text: String
    public let startMs: Int64
    public let endMs: Int64

    public init(text: String, startMs: Int64, endMs: Int64) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// Result of transcribing one window (or a whole short clip).
public struct Transcript: Equatable {
    /// Raw transcript text with NO inserted line breaks — kept verbatim so the
    /// seam-dedup in `SegmentMerge` works on exact suffix/prefix overlap.
    public let text: String
    /// Language code reported by the engine, or nil when unknown (cloud AUTO).
    public let detectedLanguage: String?
    public let segments: [TranscriptSegment]

    public init(text: String, detectedLanguage: String? = nil, segments: [TranscriptSegment] = []) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.segments = segments
    }
}

/// How a transcript was produced — recorded on the job at start time and shown
/// under the result title ("轉譯方式：…").
public enum TranscribeMethod: Equatable {
    /// On-device whisper.cpp (or future sherpa) with the model label, e.g. "base".
    case onDevice(model: String)
    /// Cloud OpenRouter with the model id and the uploaded audio container.
    case cloud(model: String, format: String)
    /// Site-provided captions reused verbatim (no recognition ran).
    case captions

    /// Human-readable label for the result screen.
    public var label: String {
        switch self {
        case .onDevice(let model): return "裝置端 · \(model)"
        case .cloud(let model, let format): return "雲端 · \(model)（\(format)）"
        case .captions: return "內嵌字幕（未經辨識）"
        }
    }
}
