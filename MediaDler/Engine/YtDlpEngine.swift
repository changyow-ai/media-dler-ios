import Foundation
import MediaDlerCore
import AVFoundation
import YoutubeDL

/// Lightweight stdout logger for on-device diagnosis of the "stuck on parsing"
/// hang. `print` lands on stdout, which `devicectl device process launch
/// --console` streams — same channel as yt-dlp's verbose output, so our markers
/// interleave with the extractor's own log lines and pinpoint where it stalls.
/// TODO: remove once the extract hang is diagnosed.
enum MDLog {
    private static let start = Date()

    static func log(_ message: String) {
        let t = String(format: "%8.3f", Date().timeIntervalSince(start))
        let thread = Thread.isMainThread ? "main" : "bg"
        print("🔵[MDLOG \(t)s \(thread)] \(message)")
    }

    /// Runs `body`, logging entry/exit and emitting a heartbeat every `interval`
    /// seconds while it is still running — so a hang shows up as repeating
    /// "STILL RUNNING" lines instead of silence.
    static func watch<T>(_ label: String, interval: TimeInterval = 5, _ body: () async throws -> T) async rethrows -> T {
        log("▶︎ \(label) — begin")
        let beat = Task {
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                n += 1
                if Task.isCancelled { break }
                log("⏳ \(label) — STILL RUNNING after \(Int(Double(n) * interval))s")
            }
        }
        defer { beat.cancel() }
        do {
            let result = try await body()
            log("✓ \(label) — end")
            return result
        } catch {
            log("✗ \(label) — threw: \(error)")
            throw error
        }
    }
}

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
    private var updateTask: Task<String?, Never>?
    private let directProgress = Progress()

    var progress: Progress { directProgress }

    /// Background-update the bundled yt-dlp once per launch. yt-dlp goes stale
    /// fast (YouTube changes often), so this is essential, not optional.
    func warmUpInBackground() {
        guard !didUpdateThisLaunch else { return }
        didUpdateThisLaunch = true
        guard updateTask == nil else { return }
        MDLog.log("warmUpInBackground: scheduling background yt-dlp update")
        updateTask = Task { await performUpdateNow() }
    }

    @discardableResult
    func updateNow() async -> String? {
        if let updateTask {
            MDLog.log("updateNow: awaiting existing yt-dlp update")
            let result = await updateTask.value
            self.updateTask = nil
            return result
        }

        let task = Task { await performUpdateNow() }
        updateTask = task
        let result = await task.value
        updateTask = nil
        return result
    }

    private func performUpdateNow() async -> String? {
        await MDLog.watch("updateNow (downloadPythonModule)") {
            do {
                try await YoutubeDL.downloadPythonModule()
                version = youtubeDL.version
                MDLog.log("updateNow: yt-dlp version now \(version ?? "nil")")
            } catch {
                // Non-fatal: a previously downloaded module may still work.
                MDLog.log("updateNow: yt-dlp update FAILED: \(error)")
            }
        }
        return version
    }

    private func waitForPendingUpdate(reason: String) async {
        guard let updateTask else { return }
        MDLog.log("waitForPendingUpdate: waiting before \(reason)")
        _ = await updateTask.value
        self.updateTask = nil
        MDLog.log("waitForPendingUpdate: update finished before \(reason)")
    }

    func extract(_ url: URL) async throws -> MediaItem {
        await waitForPendingUpdate(reason: "extract")
        MDLog.log("engine.extract: start url=\(url.absoluteString)")
        do {
            let (formats, info) = try await MDLog.watch("extractInfo #1") {
                try await youtubeDL.extractInfo(url: url)
            }
            let item = FormatMapping.mediaItem(from: info, formats: info.formats.isEmpty ? formats : info.formats, sourceUrl: url.absoluteString)
            MDLog.log("engine.extract: #1 mapped \(item.formats.count) formats")
            guard !item.formats.isEmpty else { throw EngineError.noMedia("") }
            return item
        } catch let error as EngineError {
            throw error
        } catch {
            // Self-heal: stale yt-dlp is the most common extract failure.
            MDLog.log("engine.extract: #1 threw (\(error)); self-healing then retry")
            await updateNow()
            let (formats, info) = try await MDLog.watch("extractInfo #2 (retry)") {
                try await youtubeDL.extractInfo(url: url)
            }
            let item = FormatMapping.mediaItem(from: info, formats: info.formats.isEmpty ? formats : info.formats, sourceUrl: url.absoluteString)
            MDLog.log("engine.extract: #2 mapped \(item.formats.count) formats")
            guard !item.formats.isEmpty else { throw EngineError.noMedia("") }
            return item
        }
    }

    /// Downloads `item` per `selection` and returns the finished file in the
    /// app's temp container. The caller decides where it ultimately lands
    /// (Photos vs app folder) via `MediaSink`.
    func download(item: MediaItem, selection: FormatSelection) async throws -> URL {
        await waitForPendingUpdate(reason: "download")
        guard let url = URL(string: item.sourceUrl) else { throw EngineError.badURL }
        let ids = FormatPicker.pick(item.formats, selection: selection)
        guard !ids.isEmpty else { throw EngineError.noMedia("沒有符合的格式。") }

        resetProgress()
        let (_, info) = try await youtubeDL.extractInfo(url: url)
        let byId = Dictionary(info.formats.map { ($0.format_id, $0) }, uniquingKeysWith: { a, _ in a })
        let chosen = ids.compactMap { byId[$0] }
        guard !chosen.isEmpty else { throw EngineError.noMedia("找不到選擇的格式。") }

        let fileURL: URL
        if chosen.count == 1, let format = chosen.first {
            fileURL = try await download(format: format, title: info.safeTitle)
        } else {
            let video = chosen.first(where: isVideoOnly) ?? chosen.first(where: hasVideo)
            let audio = chosen.first(where: isAudioOnly)
            guard let video, let audio else { throw EngineError.noMedia("無法組合選擇的影音格式。") }
            let videoURL = try await download(format: video, title: info.safeTitle, progressWeight: 0.75)
            // Clean the intermediate streams no matter how we leave this scope —
            // if the audio download or the merge throws, the already-downloaded
            // video temp would otherwise be orphaned in /tmp.
            defer { try? FileManager.default.removeItem(at: videoURL) }
            let audioURL = try await download(format: audio, title: info.safeTitle, progressOffset: 0.75, progressWeight: 0.20)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            fileURL = try await merge(videoURL: videoURL, audioURL: audioURL, title: info.safeTitle)
        }

        directProgress.completedUnitCount = directProgress.totalUnitCount
        return fileURL
    }

    private func resetProgress() {
        directProgress.totalUnitCount = 1_000
        directProgress.completedUnitCount = 0
        directProgress.fileCompletedCount = 0
        directProgress.fileTotalCount = 1
    }

    private func hasVideo(_ format: Format) -> Bool {
        (format.vcodec ?? "none") != "none" || (format.video_ext != "none" && !format.video_ext.isEmpty)
    }

    private func hasAudio(_ format: Format) -> Bool {
        (format.acodec ?? "none") != "none" || (format.audio_ext != "none" && !format.audio_ext.isEmpty)
    }

    private func isVideoOnly(_ format: Format) -> Bool {
        hasVideo(format) && !hasAudio(format)
    }

    private func isAudioOnly(_ format: Format) -> Bool {
        hasAudio(format) && !hasVideo(format)
    }

    private func download(format: Format, title: String, progressOffset: Double = 0, progressWeight: Double = 1) async throws -> URL {
        guard var request = format.urlRequest else { throw EngineError.badURL }
        // No Range header: requesting `bytes=0-(filesize-1)` is just the whole
        // file, but yt-dlp's `filesize` is often an estimate for adaptive
        // formats — if it under-reports, the server returns a 206 truncated to
        // that length and we'd silently save a cut-off file. A plain GET lets a
        // truncated transfer surface as a transport error instead.
        request.timeoutInterval = 30
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + sanitize(title))
            .appendingPathExtension(format.ext.isEmpty ? "bin" : format.ext)
        MDLog.log("direct download begin id=\(format.format_id) ext=\(format.ext)")
        updateProgress(written: 0, expected: 1, offset: progressOffset, weight: progressWeight)

        // Stream with a download-task delegate so the progress bar moves during
        // the transfer. URLSession's one-shot `download(for:)` reports no
        // incremental progress, so a large (e.g. 1080p, tens of MB) file would
        // sit at 0% for the whole download and look frozen.
        let tempURL = try await ProgressiveDownload.run(request: request) { [weak self] written, expected in
            guard expected > 0 else { return }
            Task { @MainActor in
                self?.updateProgress(written: written, expected: expected, offset: progressOffset, weight: progressWeight)
            }
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        updateProgress(written: 1, expected: 1, offset: progressOffset, weight: progressWeight)
        MDLog.log("direct download end id=\(format.format_id) bytes=\((try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0)")
        return destination
    }

    private func updateProgress(written: Int64, expected: Int64, offset: Double, weight: Double) {
        let fraction = offset + weight * min(1, Double(written) / Double(max(expected, 1)))
        directProgress.completedUnitCount = Int64(fraction * Double(directProgress.totalUnitCount))
    }

    private func merge(videoURL: URL, audioURL: URL, title: String) async throws -> URL {
        MDLog.log("merge begin video=\(videoURL.lastPathComponent) audio=\(audioURL.lastPathComponent)")
        directProgress.localizedDescription = "Merging..."
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioTrack = audioAsset.tracks(withMediaType: .audio).first else {
            throw EngineError.noMedia("下載完成，但無法讀取影音軌。")
        }

        let composition = AVMutableComposition()
        let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compositionVideo?.insertTimeRange(CMTimeRange(start: .zero, duration: videoTrack.timeRange.duration), of: videoTrack, at: .zero)
        try compositionAudio?.insertTimeRange(CMTimeRange(start: .zero, duration: audioTrack.timeRange.duration), of: audioTrack, at: .zero)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw EngineError.noMedia("無法建立影片輸出工作。")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + sanitize(title))
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)
        session.outputURL = outputURL
        session.outputFileType = .mp4

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: session.error ?? EngineError.noMedia("影片合併失敗。"))
                }
            }
        }
        directProgress.completedUnitCount = 980
        MDLog.log("merge end output=\(outputURL.lastPathComponent)")
        try? FileManager.default.removeItem(at: videoURL)
        try? FileManager.default.removeItem(at: audioURL)
        return outputURL
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "media" : String(trimmed.prefix(80))
    }
}

/// Downloads a request to a temp file via a `URLSessionDownloadTask`, forwarding
/// byte-level progress through `onProgress(totalWritten, totalExpected)`. The
/// returned URL is a stable temp file the caller owns (the delegate's transient
/// `location` is moved before it is reclaimed). HTTP errors and transport errors
/// are surfaced as thrown errors.
private final class ProgressiveDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static func run(request: URLRequest, onProgress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        let delegate = ProgressiveDownload(onProgress: onProgress)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: request).resume()
        }
    }

    private let onProgress: (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?

    private init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    /// Last `totalBytesExpectedToWrite` seen — used to reject a truncated file
    /// that still arrives with a 2xx (e.g. a 206 short of the advertised length).
    private var expectedBytes: Int64 = NSURLSessionTransferSizeUnknown

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        expectedBytes = totalBytesExpectedToWrite
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(DirectDownloadError.http(http.statusCode)))
            return
        }
        // Guard against a silently truncated transfer: if the server told us how
        // many bytes to expect, the file on disk must match.
        if expectedBytes > 0 {
            let attrs = try? FileManager.default.attributesOfItem(atPath: location.path)
            let actual = (attrs?[.size] as? Int64) ?? 0
            if actual < expectedBytes {
                finish(.failure(DirectDownloadError.truncated(received: actual, expected: expectedBytes)))
                return
            }
        }
        // `location` is deleted once this delegate call returns, so move it now.
        let stable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            finish(.success(stable))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
