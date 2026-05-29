import Foundation

/// A single downloadable piece of media resolved from a shared URL.
public struct MediaItem: Equatable, Identifiable {
    public let sourceUrl: String
    public let playlistIndex: Int?
    public let id: String
    public let title: String
    public let thumbnailUrl: String?
    public let durationSeconds: Int64?
    public let isImage: Bool
    public let formats: [MediaFormat]

    public init(
        sourceUrl: String,
        playlistIndex: Int?,
        id: String,
        title: String,
        thumbnailUrl: String?,
        durationSeconds: Int64?,
        isImage: Bool,
        formats: [MediaFormat]
    ) {
        self.sourceUrl = sourceUrl
        self.playlistIndex = playlistIndex
        self.id = id
        self.title = title
        self.thumbnailUrl = thumbnailUrl
        self.durationSeconds = durationSeconds
        self.isImage = isImage
        self.formats = formats
    }
}

/// One selectable output format for a `MediaItem`.
public struct MediaFormat: Equatable {
    public let formatId: String
    public let ext: String
    public let label: String
    public let height: Int?
    public let hasVideo: Bool
    public let hasAudio: Bool
    public let isImage: Bool
    public let filesizeBytes: Int64?
    public let vcodec: String?
    public let acodec: String?

    public init(
        formatId: String,
        ext: String,
        label: String,
        height: Int?,
        hasVideo: Bool,
        hasAudio: Bool,
        isImage: Bool,
        filesizeBytes: Int64?,
        vcodec: String? = nil,
        acodec: String? = nil
    ) {
        self.formatId = formatId
        self.ext = ext
        self.label = label
        self.height = height
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.isImage = isImage
        self.filesizeBytes = filesizeBytes
        self.vcodec = vcodec
        self.acodec = acodec
    }
}

public enum DownloadStatus: String, Codable {
    case queued, extracting, downloading, processing, completed, failed, canceled

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .canceled
    }
}

public struct DownloadTask: Equatable, Codable {
    public let id: String
    public let title: String
    public let sourceUrl: String
    public let thumbnailUrl: String?
    public let formatLabel: String
    public var status: DownloadStatus
    public var progress: Double
    public var outputUri: String?
    public var mimeType: String?
    public var errorMessage: String?
    public let createdAt: Double
    public var previewPath: String?
    /// Absolute path of the saved file when stored in the app folder (nil for
    /// items saved to the Photos library). Used for share + delete-on-remove.
    public var localPath: String?

    public init(
        id: String,
        title: String,
        sourceUrl: String,
        thumbnailUrl: String?,
        formatLabel: String,
        status: DownloadStatus,
        progress: Double,
        outputUri: String?,
        mimeType: String?,
        errorMessage: String?,
        createdAt: Double,
        previewPath: String? = nil,
        localPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceUrl = sourceUrl
        self.thumbnailUrl = thumbnailUrl
        self.formatLabel = formatLabel
        self.status = status
        self.progress = progress
        self.outputUri = outputUri
        self.mimeType = mimeType
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.previewPath = previewPath
        self.localPath = localPath
    }
}

/// How the user wants a `MediaItem` downloaded.
public enum FormatSelection: Equatable {
    case bestVideo
    case cappedVideo(maxHeight: Int)
    case specificFormat(MediaFormat)
    case audio(AudioFormat)
    case imageOriginal
}

/// A concrete unit of work submitted to the download queue.
public struct DownloadRequest: Equatable {
    public let item: MediaItem
    public let selection: FormatSelection

    public init(item: MediaItem, selection: FormatSelection) {
        self.item = item
        self.selection = selection
    }
}
