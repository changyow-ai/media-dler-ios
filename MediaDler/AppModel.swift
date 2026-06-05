import Foundation
import MediaDlerCore

/// Central app state: warm-up, deep-link handling, extraction, the download
/// queue, and history. Owns the engine and settings.
@MainActor
final class AppModel: ObservableObject {
    let engine = YtDlpEngine()
    let settings = SettingsStore()
    let transcription = TranscriptionManager.shared

    @Published var tasks: [DownloadTask] = HistoryStore.load()
    @Published var isExtracting = false
    @Published var banner: String?
    @Published var pendingPick: MediaItem?
    @Published var engineVersion: String?

    // Transcription (video2text). `pendingLocalMedia` drives the action menu
    // shown after a local file is shared in; `activeTranscribe` presents the
    // result/progress screen once the user picks 「轉成文字」.
    @Published var pendingLocalMedia: LocalMedia?
    @Published var activeTranscribe: LocalMedia?

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
        TranscriptionRunner.requestNotificationPermission()
    }

    func refreshEngine() {
        Task { engineVersion = await engine.updateNow() }
    }

    // MARK: Entry points

    func handle(text: String?) {
        MDLog.log("AppModel.handle(text:) raw=\(text ?? "nil") isExtracting=\(isExtracting)")
        guard let raw = UrlExtractor.firstUrl(text), let url = URL(string: raw) else {
            banner = "剪貼簿或連結中找不到有效的網址。"
            return
        }
        Task { await extract(url) }
    }

    func handle(deepLink: URL) {
        MDLog.log("AppModel.handle(deepLink:) \(deepLink.absoluteString)")
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              components.scheme == "mediadler" else { return }
        let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value
        handle(text: urlParam)
    }

    // MARK: Transcription routing

    /// A local video/audio file was shared in via CFBundleDocumentTypes. Copy
    /// it into private storage (resumable source) and show the action menu.
    func handle(localFile url: URL) {
        MDLog.log("AppModel.handle(localFile:) \(url.lastPathComponent)")
        guard let media = LocalMediaInput.importFile(url) else {
            banner = "無法讀取分享進來的檔案。"
            return
        }
        pendingLocalMedia = media
    }

    func transcribeLocal(_ media: LocalMedia) {
        pendingLocalMedia = nil
        activeTranscribe = media
    }

    func extractAudio(_ media: LocalMedia) {
        pendingLocalMedia = nil
        // Lossless audio extraction lands in M6.
        banner = "「取出聲音」將於後續里程碑加入。"
    }

    // MARK: Extraction

    private func extract(_ url: URL) async {
        MDLog.log("AppModel.extract: ENTER isExtracting(before)=\(isExtracting) url=\(url.absoluteString)")
        guard !isExtracting else {
            banner = "正在解析上一個連結，請稍候。"
            MDLog.log("AppModel.extract: ignored duplicate extract while busy")
            return
        }
        isExtracting = true
        defer { isExtracting = false; MDLog.log("AppModel.extract: EXIT (isExtracting=false)") }
        do {
            // Threads has no yt-dlp extractor: resolve it ourselves and download
            // the direct CDN media (all items in the post) straight to Photos.
            if ThreadsService.isThreads(url.absoluteString) {
                let items = try await ThreadsService.extract(url.absoluteString)
                MDLog.log("Threads.extract: returned \(items.count) item(s): \(items.map { ($0.isImage ? "img" : "vid") + ":" + $0.title }.joined(separator: ", "))")
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
        deleteFiles(of: task)
        tasks.removeAll { $0.id == task.id }
        queue.removeAll { $0.taskId == task.id }
        persist()
    }

    /// Removes every history item. App-folder files and previews are deleted;
    /// items saved to the Photos library are left there (the user manages those).
    func clearAll() {
        tasks.forEach(deleteFiles)
        tasks.removeAll()
        queue.removeAll()
        ThumbnailMaker.removeAll()
        persist()
    }

    /// Deletes the on-disk artifacts owned by a task: the stored file (only if it
    /// lives in the app folder) and its local preview thumbnail.
    private func deleteFiles(of task: DownloadTask) {
        if let path = task.localPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        ThumbnailMaker.remove(id: task.id)
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
            MDLog.log("runEngine: starting download (calls extractInfo internally) task=\(job.taskId)")
            let fileURL = try await MDLog.watch("engine.download") {
                try await engine.download(item: job.item, selection: selection)
            }
            progressTask.cancel()
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let isAudio: Bool = { if case .audio = selection { return true }; return false }()
            let kind: MediaContentKind = isAudio ? .audio : (job.item.isImage ? .image : .video)
            // Build the preview from the temp file before it is moved/consumed.
            let preview = kind == .audio ? nil
                : ThumbnailMaker.make(from: fileURL, isImage: kind == .image, id: job.taskId)
            let saved = try await MediaSink.save(
                tempFile: fileURL,
                kind: kind,
                title: job.item.title,
                destination: settings.settings.storageDestination
            )
            update(job.taskId) {
                $0.status = .completed
                $0.progress = 1
                $0.outputUri = saved.outputUri
                $0.mimeType = saved.mimeType
                $0.localPath = saved.localPath
                $0.previewPath = preview
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
            MDLog.log("runDirect: saving \(job.item.isImage ? "image" : "video") \(job.item.title) src=\(job.item.sourceUrl.prefix(80))")
            let fileURL = try await DirectMediaSaver.download(job.item)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let kind: MediaContentKind = job.item.isImage ? .image : .video
            let preview = ThumbnailMaker.make(from: fileURL, isImage: job.item.isImage, id: job.taskId)
            let saved = try await MediaSink.save(
                tempFile: fileURL,
                kind: kind,
                title: job.item.title,
                destination: settings.settings.storageDestination
            )
            MDLog.log("runDirect: ✓ saved (\(saved.localPath ?? "photos")): \(job.item.title)")
            update(job.taskId) {
                $0.status = .completed
                $0.progress = 1
                $0.outputUri = saved.outputUri
                $0.mimeType = saved.mimeType
                $0.localPath = saved.localPath
                $0.previewPath = preview
            }
        } catch {
            MDLog.log("runDirect: ✗ FAILED \(job.item.title): \(error)")
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
