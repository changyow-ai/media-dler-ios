import Foundation
import MediaDlerCore
import YoutubeDL

enum EngineError: LocalizedError {
    case badURL
    case noMedia(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "無法解析這個連結。"
        case .noMedia(let s): return "找不到可下載的媒體。\(s)"
        }
    }
}

/// Wraps YoutubeDL-iOS: engine warm-up + online yt-dlp update (self-heal),
/// info extraction, and downloading with client-side format selection.
@MainActor
final class YtDlpEngine {
    let youtubeDL = YoutubeDL()
    private(set) var version: String?
    private var didUpdateThisLaunch = false

    var progress: Progress { youtubeDL.downloader.progress }

    /// Background-update the bundled yt-dlp once per launch. yt-dlp goes stale
    /// fast (YouTube changes often), so this is essential, not optional.
    func warmUpInBackground() {
        guard !didUpdateThisLaunch else { return }
        didUpdateThisLaunch = true
        Task { _ = await updateNow() }
    }

    @discardableResult
    func updateNow() async -> String? {
        do {
            try await YoutubeDL.downloadPythonModule()
            version = youtubeDL.version
        } catch {
            // Non-fatal: a previously downloaded module may still work.
            print("yt-dlp update failed: \(error)")
        }
        return version
    }

    func extract(_ url: URL) async throws -> MediaItem {
        do {
            let (formats, info) = try await youtubeDL.extractInfo(url: url)
            let item = FormatMapping.mediaItem(from: info, formats: info.formats.isEmpty ? formats : info.formats, sourceUrl: url.absoluteString)
            guard !item.formats.isEmpty else { throw EngineError.noMedia("") }
            return item
        } catch let error as EngineError {
            throw error
        } catch {
            // Self-heal: stale yt-dlp is the most common extract failure.
            await updateNow()
            let (formats, info) = try await youtubeDL.extractInfo(url: url)
            let item = FormatMapping.mediaItem(from: info, formats: info.formats.isEmpty ? formats : info.formats, sourceUrl: url.absoluteString)
            guard !item.formats.isEmpty else { throw EngineError.noMedia("") }
            return item
        }
    }

    /// Downloads `item` per `selection`. Video is exported to Photos by the
    /// library; the returned URL is the finished file in the app container.
    func download(item: MediaItem, selection: FormatSelection) async throws -> URL {
        guard let url = URL(string: item.sourceUrl) else { throw EngineError.badURL }
        let ids = FormatPicker.pick(item.formats, selection: selection)
        guard !ids.isEmpty else { throw EngineError.noMedia("沒有符合的格式。") }

        return try await youtubeDL.download(url: url, options: [.background, .chunked]) { info in
            let byId = Dictionary(info.formats.map { ($0.format_id, $0) }, uniquingKeysWith: { a, _ in a })
            let chosen = ids.compactMap { byId[$0] }
            return (chosen, nil, nil, nil, info.safeTitle)
        }
    }
}
