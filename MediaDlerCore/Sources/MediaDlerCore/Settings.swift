import Foundation

public enum ShareMode: String, Codable { case oneTap, ask }

public enum MediaKind: String, Codable { case video, audio }

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

    public init(
        shareMode: ShareMode = .ask,
        defaultMediaKind: MediaKind = .video,
        defaultVideoQuality: VideoQuality = .best,
        audioFormat: AudioFormat = .mp3,
        downloadAllWhenMultiple: Bool = true
    ) {
        self.shareMode = shareMode
        self.defaultMediaKind = defaultMediaKind
        self.defaultVideoQuality = defaultVideoQuality
        self.audioFormat = audioFormat
        self.downloadAllWhenMultiple = downloadAllWhenMultiple
    }
}
