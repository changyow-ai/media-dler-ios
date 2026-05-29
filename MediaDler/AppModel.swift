import Foundation
import MediaDlerCore

/// Central app state: warm-up, deep-link handling, extraction, the download
/// queue, and history. Owns the engine and settings.
@MainActor
final class AppModel: ObservableObject {
    let engine = YtDlpEngine()
    let settings = SettingsStore()

    @Published var tasks: [DownloadTask] = HistoryStore.load()
    @Published var isExtracting = false
    @Published var banner: String?
    @Published var pendingPick: MediaItem?
    @Published var engineVersion: String?

    private enum JobKind {
        case engine(FormatSelection)
        case directToPhotos
    }
    private struct Job { let taskId: String; let item: MediaItem; let kind: JobKind }
    private var queue: [Job] = []
    private var running = false

    func start() {
        engineVersion = engine.version
        engine.warmUpInBackground()
    }

    func refreshEngine() {
        Task { engineVersion = await engine.updateNow() }
    }

    // MARK: Entry points

    func handle(text: String?) {
        guard let raw = UrlExtractor.firstUrl(text), let url = URL(string: raw) else {
            banner = "剪貼簿或連結中找不到有效的網址。"
            return
        }
        Task { await extract(url) }
    }

    func handle(deepLink: URL) {
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              components.scheme == "mediadler" else { return }
        let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value
        handle(text: urlParam)
    }

    // MARK: Extraction

    private func extract(_ url: URL) async {
        isExtracting = true
        defer { isExtracting = false }
        do {
            // Threads has no yt-dlp extractor: resolve it ourselves and download
            // the direct CDN media (all items in the post) straight to Photos.
            if ThreadsService.isThreads(url.absoluteString) {
                let items = try await ThreadsService.extract(url.absoluteString)
                guard !items.isEmpty else {
                    throw EngineError.noMedia("Threads 貼文沒有可下載媒體（純文字，或需登入的多圖輪播）。")
                }
                items.forEach { enqueueDirect($0) }
                return
            }

            let item = try await engine.extract(url)
            if settings.settings.shareMode == .oneTap {
                let selection = SelectionPlanner.defaultSelection(item, settings: settings.settings)
                submit(item: item, selection: selection)
            } else {
                pendingPick = item
            }
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: Queue

    func submit(item: MediaItem, selection: FormatSelection) {
        enqueue(item: item, label: label(for: selection), kind: .engine(selection))
    }

    private func enqueueDirect(_ item: MediaItem) {
        enqueue(item: item, label: item.isImage ? "圖片" : "影片", kind: .directToPhotos)
    }

    private func enqueue(item: MediaItem, label: String, kind: JobKind) {
        let task = DownloadTask(
            id: UUID().uuidString,
            title: item.title,
            sourceUrl: item.sourceUrl,
            thumbnailUrl: item.thumbnailUrl,
            formatLabel: label,
            status: .queued,
            progress: 0,
            outputUri: nil,
            mimeType: nil,
            errorMessage: nil,
            createdAt: Date().timeIntervalSince1970
        )
        tasks.insert(task, at: 0)
        persist()
        queue.append(Job(taskId: task.id, item: item, kind: kind))
        pump()
    }

    func retry(_ task: DownloadTask) {
        guard let url = URL(string: task.sourceUrl) else { return }
        Task { await extract(url) }
    }

    func remove(_ task: DownloadTask) {
        tasks.removeAll { $0.id == task.id }
        queue.removeAll { $0.taskId == task.id }
        persist()
    }

    private func pump() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let job = queue.removeFirst()
        Task {
            await run(job)
            running = false
            pump()
        }
    }

    private func run(_ job: Job) async {
        update(job.taskId) { $0.status = .downloading }
        switch job.kind {
        case .engine(let selection): await runEngine(job, selection: selection)
        case .directToPhotos: await runDirect(job)
        }
        persist()
    }

    private func runEngine(_ job: Job, selection: FormatSelection) async {
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                update(job.taskId) { $0.progress = engine.progress.fractionCompleted }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        do {
            let fileURL = try await engine.download(item: job.item, selection: selection)
            progressTask.cancel()
            var output: String?
            var mime: String?
            if case .audio = selection {
                let saved = DocumentsStorage.save(fileURL, preferredName: job.item.title)
                output = saved.map { "檔案 App → media-dler → \($0.lastPathComponent)" }
                mime = "audio/\(fileURL.pathExtension)"
            } else {
                output = "已儲存到「照片」App"
                mime = "video/\(fileURL.pathExtension)"
            }
            update(job.taskId) {
                $0.status = .completed
                $0.progress = 1
                $0.outputUri = output
                $0.mimeType = mime
            }
        } catch {
            progressTask.cancel()
            update(job.taskId) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    private func runDirect(_ job: Job) async {
        do {
            try await DirectMediaSaver.saveToPhotos(job.item)
            update(job.taskId) {
                $0.status = .completed
                $0.progress = 1
                $0.outputUri = "已儲存到「照片」App"
                $0.mimeType = job.item.isImage ? "image" : "video"
            }
        } catch {
            update(job.taskId) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Helpers

    private func update(_ id: String, _ mutate: (inout DownloadTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[i])
    }

    private func persist() {
        HistoryStore.save(tasks.filter { $0.status.isTerminal })
    }

    private func label(for selection: FormatSelection) -> String {
        switch selection {
        case .bestVideo: return "最佳畫質"
        case .cappedVideo(let h): return "\(h)p"
        case .audio(let f): return "音訊 \(f.ext.uppercased())"
        case .imageOriginal: return "圖片"
        case .specificFormat(let f): return f.label
        }
    }
}
