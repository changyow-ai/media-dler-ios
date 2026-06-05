import Foundation

public enum ShareMode: String, Codable { case oneTap, ask }

public enum MediaKind: String, Codable { case video, audio }

/// Where finished video/image downloads are stored. Audio always lands in the
/// app folder regardless (the Photos library can't hold audio).
public enum StorageDestination: String, Codable, CaseIterable {
    /// Save into the system Photos library (the historical default).
    case photos
    /// Keep inside the app's Documents folder, shareable to other apps.
    case appFolder
}

public enum VideoQuality: String, Codable, CaseIterable {
    case best, p1080, p720, p480, p360

    public var maxHeight: Int? {
        switch self {
        case .best: return nil
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        case .p360: return 360
        }
    }
}

public enum AudioFormat: String, Codable, CaseIterable {
    case mp3, m4a

    public var ext: String { rawValue }
}

// MARK: - Transcription (video2text)

/// Which transcription backend to use. On-device whisper.cpp is the default
/// (offline, private, no key); cloud goes through OpenRouter.
public enum TranscribeEngine: String, Codable, CaseIterable { case onDevice, cloud }

/// Which on-device recognition backend a model runs on. Derived from the
/// selected `TranscribeModel` — the UI never exposes "backend" directly.
public enum OnDeviceBackend: String, Codable { case whisperCpp, sherpa }

/// On-device model selection. `base`/`small`/`turboQ5` run on whisper.cpp;
/// `senseVoice`/`paraformer`/`qwen3` run on sherpa-onnx. The on-device picker
/// lists all of them and the backend is inferred from the choice.
public enum TranscribeModel: String, Codable, CaseIterable {
    case base, small, turboQ5            // whisper.cpp (ggml)
    case senseVoice, paraformer, qwen3   // sherpa-onnx (ONNX Runtime)

    public var backend: OnDeviceBackend {
        switch self {
        case .base, .small, .turboQ5: return .whisperCpp
        case .senseVoice, .paraformer, .qwen3: return .sherpa
        }
    }

    /// Short label for the "轉譯方式" line on the result screen.
    public var label: String {
        switch self {
        case .base: return "base"
        case .small: return "small"
        case .turboQ5: return "turbo-q5"
        case .senseVoice: return "SenseVoice"
        case .paraformer: return "Paraformer"
        case .qwen3: return "Qwen3"
        }
    }
}

/// User-locked transcription language. `auto` lets the engine detect; an
/// explicit choice both improves accuracy and (for `zh`) forces the
/// simplified→traditional conversion even when the engine reports no language
/// (the OpenRouter AUTO caveat).
public enum TranscribeLanguage: String, Codable, CaseIterable {
    case auto, zh, en, ja, ko, es, fr, de
}

public struct AppSettings: Equatable, Codable {
    public var shareMode: ShareMode
    public var defaultMediaKind: MediaKind
    public var defaultVideoQuality: VideoQuality
    public var audioFormat: AudioFormat
    public var downloadAllWhenMultiple: Bool
    public var storageDestination: StorageDestination

    // Transcription (video2text). The API key is NOT stored here — it lives in
    // the Keychain (KeychainStore) to avoid plaintext in UserDefaults.
    public var transcribeEngine: TranscribeEngine
    public var transcribeModel: TranscribeModel
    public var transcribeLanguage: TranscribeLanguage
    public var cloudBaseUrl: String
    public var cloudModel: String
    public var cloudCompressAudio: Bool

    public init(
        shareMode: ShareMode = .ask,
        defaultMediaKind: MediaKind = .video,
        defaultVideoQuality: VideoQuality = .best,
        audioFormat: AudioFormat = .mp3,
        downloadAllWhenMultiple: Bool = true,
        storageDestination: StorageDestination = .photos,
        transcribeEngine: TranscribeEngine = .onDevice,
        transcribeModel: TranscribeModel = .base,
        transcribeLanguage: TranscribeLanguage = .auto,
        cloudBaseUrl: String = "https://openrouter.ai/api/v1",
        cloudModel: String = "openai/whisper-large-v3-turbo",
        cloudCompressAudio: Bool = false
    ) {
        self.shareMode = shareMode
        self.defaultMediaKind = defaultMediaKind
        self.defaultVideoQuality = defaultVideoQuality
        self.audioFormat = audioFormat
        self.downloadAllWhenMultiple = downloadAllWhenMultiple
        self.storageDestination = storageDestination
        self.transcribeEngine = transcribeEngine
        self.transcribeModel = transcribeModel
        self.transcribeLanguage = transcribeLanguage
        self.cloudBaseUrl = cloudBaseUrl
        self.cloudModel = cloudModel
        self.cloudCompressAudio = cloudCompressAudio
    }

    // Tolerant decoding: settings persisted by older builds won't carry every
    // key (e.g. `storageDestination` added later). Default missing fields
    // instead of failing the whole decode, which would wipe the user's prefs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        shareMode = try c.decodeIfPresent(ShareMode.self, forKey: .shareMode) ?? d.shareMode
        defaultMediaKind = try c.decodeIfPresent(MediaKind.self, forKey: .defaultMediaKind) ?? d.defaultMediaKind
        defaultVideoQuality = try c.decodeIfPresent(VideoQuality.self, forKey: .defaultVideoQuality) ?? d.defaultVideoQuality
        audioFormat = try c.decodeIfPresent(AudioFormat.self, forKey: .audioFormat) ?? d.audioFormat
        downloadAllWhenMultiple = try c.decodeIfPresent(Bool.self, forKey: .downloadAllWhenMultiple) ?? d.downloadAllWhenMultiple
        storageDestination = try c.decodeIfPresent(StorageDestination.self, forKey: .storageDestination) ?? d.storageDestination
        transcribeEngine = try c.decodeIfPresent(TranscribeEngine.self, forKey: .transcribeEngine) ?? d.transcribeEngine
        transcribeModel = try c.decodeIfPresent(TranscribeModel.self, forKey: .transcribeModel) ?? d.transcribeModel
        transcribeLanguage = try c.decodeIfPresent(TranscribeLanguage.self, forKey: .transcribeLanguage) ?? d.transcribeLanguage
        cloudBaseUrl = try c.decodeIfPresent(String.self, forKey: .cloudBaseUrl) ?? d.cloudBaseUrl
        cloudModel = try c.decodeIfPresent(String.self, forKey: .cloudModel) ?? d.cloudModel
        cloudCompressAudio = try c.decodeIfPresent(Bool.self, forKey: .cloudCompressAudio) ?? d.cloudCompressAudio
    }
}
