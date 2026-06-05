import Foundation
import MediaDlerCore

/// In-memory single source of truth for transcription jobs and the pipeline
/// driver. High-frequency progress lives here (`@Published`); the on-disk store
/// is written only at window checkpoints and terminal states.
///
/// Pipeline (on-device): durationMs → plan 60s/3s windows → per-window
/// decodeRange PCM → engine.transcribeWindow → SegmentMerge → checkpoint;
/// at the end LanguageDecision + OpenCC produce the final text.
@MainActor
final class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()

    @Published private(set) var jobs: [TranscriptJob]

    private let runner = TranscriptionRunner()
    private var task: Task<Void, Never>?

    // On-device window config — also the checkpoint unit (60s + 3s overlap).
    private let windowMs: Int64 = 60_000
    private let overlapMs: Int64 = 3_000

    init() {
        jobs = TranscriptStore.load()
        // Any job left `running` was interrupted (app killed) → mark resumable.
        for i in jobs.indices where jobs[i].status == .running {
            jobs[i].status = .pending
        }
    }

    func job(_ id: String) -> TranscriptJob? { jobs.first { $0.id == id } }

    /// Most recent job that can still be resumed (interrupted/pending, on-device).
    var resumableJob: TranscriptJob? {
        jobs.first { $0.status == .pending && $0.completedWindows > 0 }
    }

    // MARK: Start / resume / cancel

    /// Starts (or resumes) transcription of a shared local file. Returns the job id.
    @discardableResult
    func startLocal(_ media: LocalMedia, settings: AppSettings) -> String {
        let jobId = media.id
        let engineId = "whispercpp-\(settings.transcribeModel.rawValue)"
        let method = TranscribeMethod.onDevice(model: settings.transcribeModel.rawValue)

        if let existing = job(jobId) {
            if existing.status == .completed { return jobId }
            update(jobId) {
                // Engine-switch guard: a differing engine id invalidates the
                // checkpoint (windowing differs → seams would mismatch).
                if $0.engineId != engineId {
                    $0.text = ""
                    $0.completedWindows = 0
                    $0.detectedLanguage = nil
                    $0.engineId = engineId
                    $0.methodLabel = method.label
                }
                $0.status = .pending
                $0.errorMessage = nil
            }
        } else {
            upsert(TranscriptJob(
                id: jobId,
                source: .localFile(path: media.url.path),
                title: media.title,
                status: .pending,
                progress: 0,
                text: "",
                detectedLanguage: nil,
                completedWindows: 0,
                totalWindows: 0,
                engineId: engineId,
                methodLabel: method.label,
                errorMessage: nil,
                createdAt: Date().timeIntervalSince1970,
                durationMs: 0
            ))
        }
        run(jobId: jobId, model: settings.transcribeModel, knownLanguage: settings.transcribeLanguage)
        return jobId
    }

    func cancel(_ id: String) {
        task?.cancel()
        update(id) { $0.status = .canceled }
        persist()
        cleanupInput(id)
    }

    func remove(_ id: String) {
        task?.cancel()
        cleanupInput(id)
        jobs.removeAll { $0.id == id }
        persist()
    }

    // MARK: Pipeline

    private func run(jobId: String, model: TranscribeModel, knownLanguage: TranscribeLanguage) {
        task?.cancel()
        runner.beginGrace(name: "transcribe-\(jobId)")
        task = Task { [weak self] in
            await self?.pipeline(jobId: jobId, model: model, knownLanguage: knownLanguage)
            self?.runner.endGrace()
        }
    }

    private func pipeline(jobId: String, model: TranscribeModel, knownLanguage: TranscribeLanguage) async {
        guard case .localFile(let path)? = job(jobId)?.source else { return }
        let url = URL(fileURLWithPath: path)
        update(jobId) { $0.status = .running }
        do {
            let modelPath = try await WhisperModelManager.shared.ensureDownloaded(model).path
            guard let engine = TranscriptionEngineFactory.onDeviceEngine(model: model, modelPath: modelPath) else {
                throw TranscribeError.engineUnavailable(
                    "裝置端轉錄引擎尚未建置。請執行 scripts/build-whisper.sh，並依 project.yml 內的註解加入 whisper.xcframework 後重新產生專案。"
                )
            }

            let durationMs = try await AudioToPCM.durationMs(of: url)
            let windows = WindowPlanner.plan(totalMs: durationMs, windowMs: windowMs, overlapMs: overlapMs)
            update(jobId) { $0.durationMs = durationMs; $0.totalWindows = windows.count }

            let startIndex = job(jobId)?.completedWindows ?? 0
            var merged = job(jobId)?.text ?? ""

            for window in windows where window.index >= startIndex {
                try Task.checkCancellation()
                let pcm = try await AudioToPCM.decodeRange(url: url, startMs: window.startMs, endMs: window.endMs)
                let base = merged
                let result = try await engine.transcribeWindow(
                    pcm: pcm, window: window, knownLanguage: knownLanguage
                ) { [weak self] partial in
                    Task { @MainActor in
                        self?.update(jobId) { $0.text = SegmentMerge.merge([base, partial.partialText]) }
                    }
                }
                merged = SegmentMerge.merge([merged, result.text])
                let detected = result.detectedLanguage
                update(jobId) {
                    $0.text = merged
                    $0.completedWindows = window.index + 1
                    if $0.detectedLanguage == nil { $0.detectedLanguage = detected }
                    $0.progress = windows.isEmpty ? 1 : Double(window.index + 1) / Double(windows.count)
                }
                persist() // checkpoint per window
            }

            let detected = job(jobId)?.detectedLanguage
            var finalText = merged
            if LanguageDecision.shouldConvertToTraditional(detectedLang: detected, knownLanguage: knownLanguage) {
                finalText = OpenCCConverter.s2twp(merged)
            }
            update(jobId) { $0.text = finalText; $0.status = .completed; $0.progress = 1 }
            persist()
            cleanupInput(jobId)
            TranscriptionRunner.notify(title: "逐字稿完成", body: job(jobId)?.title ?? "")
        } catch is CancellationError {
            update(jobId) { $0.status = .canceled }
            persist()
            cleanupInput(jobId)
        } catch {
            // FAILED keeps the private input copy so the user can resume.
            update(jobId) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
            persist()
            TranscriptionRunner.notify(title: "逐字稿失敗", body: error.localizedDescription)
        }
    }

    // MARK: Helpers

    private func upsert(_ job: TranscriptJob) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i] = job
        } else {
            jobs.insert(job, at: 0)
        }
    }

    private func update(_ id: String, _ mutate: (inout TranscriptJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[i])
    }

    private func persist() { TranscriptStore.save(jobs) }

    /// Removes the resumable private input copy (completed/canceled only — a
    /// FAILED job keeps it so it can resume).
    private func cleanupInput(_ id: String) {
        guard case .localFile(let path)? = job(id)?.source else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
