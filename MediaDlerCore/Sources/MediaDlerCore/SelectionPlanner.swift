import Foundation

public enum SelectionPlanner {
    /// The default `FormatSelection` for `item` given user `settings` (one-tap mode).
    public static func defaultSelection(_ item: MediaItem, settings: AppSettings) -> FormatSelection {
        if item.isImage { return .imageOriginal }
        if settings.defaultMediaKind == .audio { return .audio(settings.audioFormat) }
        if let cap = settings.defaultVideoQuality.maxHeight { return .cappedVideo(maxHeight: cap) }
        return .bestVideo
    }
}
