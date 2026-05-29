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

public struct AppSettings: Equatable, Codable {
    public var shareMode: ShareMode
    public var defaultMediaKind: MediaKind
    public var defaultVideoQuality: VideoQuality
    public var audioFormat: AudioFormat
    public var downloadAllWhenMultiple: Bool
    public var storageDestination: StorageDestination

    public init(
        shareMode: ShareMode = .ask,
        defaultMediaKind: MediaKind = .video,
        defaultVideoQuality: VideoQuality = .best,
        audioFormat: AudioFormat = .mp3,
        downloadAllWhenMultiple: Bool = true,
        storageDestination: StorageDestination = .photos
    ) {
        self.shareMode = shareMode
        self.defaultMediaKind = defaultMediaKind
        self.defaultVideoQuality = defaultVideoQuality
        self.audioFormat = audioFormat
        self.downloadAllWhenMultiple = downloadAllWhenMultiple
        self.storageDestination = storageDestination
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
    }
}
