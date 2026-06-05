import Foundation
import Network
import MediaDlerCore

/// Downloads, caches and manages the ggml whisper models. Models are NOT bundled
/// in the IPA — they download on first use into Application Support and persist.
/// A Wi-Fi gate (ask-first on expensive/cellular paths) guards the download.
@MainActor
final class WhisperModelManager: NSObject, ObservableObject {
    static let shared = WhisperModelManager()

    @Published private(set) var activeDownload: TranscribeModel?
    @Published private(set) var progress: Double = 0

    private var continuation: CheckedContinuation<URL, Error>?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    // MARK: Model catalog

    /// HuggingFace resolve URL for each ggml model (multilingual variants).
    static func remoteURL(for model: TranscribeModel) -> URL {
        let name: String
        switch model {
        case .base: name = "ggml-base.bin"
        case .small: name = "ggml-small.bin"
        case .turboQ5: name = "ggml-large-v3-turbo-q5_0.bin"
        case .senseVoice, .paraformer, .qwen3:
            preconditionFailure("sherpa model has no whisper ggml URL — use SherpaModelManager")
        }
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)")!
    }

    static var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WhisperModels", isDirectory: true)
    }

    static func localURL(for model: TranscribeModel) -> URL {
        modelsDir.appendingPathComponent(remoteURL(for: model).lastPathComponent)
    }

    static func isDownloaded(_ model: TranscribeModel) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    /// True when the current network path is cellular/metered — the UI should
    /// confirm before a large model download. Async so it never blocks the
    /// caller's thread (the old semaphore version stalled the main actor up to
    /// 1s on every transcribe-screen open).
    static func isExpensiveNetwork() async -> Bool {
        final class Box: @unchecked Sendable { var resumed = false; let lock = NSLock() }
        let box = Box()
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "whisper.netcheck")
        return await withCheckedContinuation { cont in
            // pathUpdateHandler and the timeout both run on `queue` (serial), but
            // guard the single resume anyway in case of overlap.
            func finish(_ expensive: Bool) {
                box.lock.lock(); defer { box.lock.unlock() }
                guard !box.resumed else { return }
                box.resumed = true
                monitor.cancel()
                cont.resume(returning: expensive)
            }
            monitor.pathUpdateHandler = { path in
                finish(path.isExpensive || path.usesInterfaceType(.cellular))
            }
            monitor.start(queue: queue)
            // Fallback: assume not-expensive if no path update lands in 1s.
            queue.asyncAfter(deadline: .now() + 1.0) { finish(false) }
        }
    }

    // MARK: Download / delete

    /// Ensures the model is present locally, downloading it if needed. Returns
    /// the local file URL. Throws if a download is already running.
    @discardableResult
    func ensureDownloaded(_ model: TranscribeModel) async throws -> URL {
        let local = Self.localURL(for: model)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        guard activeDownload == nil else {
            throw TranscribeError.busy("已有模型正在下載。")
        }
        try? FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)

        activeDownload = model
        progress = 0
        defer { activeDownload = nil }

        let temp: URL = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let task = session.downloadTask(with: Self.remoteURL(for: model))
            task.resume()
        }
        try FileManager.default.moveItem(at: temp, to: local)
        return local
    }

    func delete(_ model: TranscribeModel) {
        try? FileManager.default.removeItem(at: Self.localURL(for: model))
    }
}

extension WhisperModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is removed when this delegate returns — move it to a
        // staging path we control before hopping to the main actor.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        try? FileManager.default.moveItem(at: location, to: staged)
        Task { @MainActor in
            self.continuation?.resume(returning: staged)
            self.continuation = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
