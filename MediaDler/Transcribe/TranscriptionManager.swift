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
    /// One in-flight pipeline Task per job id. Keying by id means cancelling or
    /// removing one job never aborts a *different* job that happens to be the
    /// most recently started one (and never deletes its input out from under it).
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Resolved engine choice + window config for one run.
    private struct EnginePlan {
        let transcribeEngine: TranscribeEngine
        let model: TranscribeModel
        let knownLanguage: TranscribeLanguage
        let engineId: String
        let method: TranscribeMethod
        let windowMs: Int64
        let overlapMs: Int64
        let baseUrl: String
        let cloudModel: String
    }

    private func plan(for settings: AppSettings) -> EnginePlan {
        switch settings.transcribeEngine {
        case .onDevice:
            // 60s window + 3s overlap, also the checkpoint unit. Engine id is
            // backend-prefixed so switching whisper↔sherpa (different windowing
            // behaviour) discards the checkpoint and re-transcribes cleanly.
            let model = settings.transcribeModel
            let prefix = model.backend == .sherpa ? "sherpa" : "whispercpp"
            return EnginePlan(
                transcribeEngine: .onDevice,
                model: model,
                knownLanguage: settings.transcribeLanguage,
                engineId: "\(prefix)-\(model.rawValue)",
                method: .onDevice(model: model.label),
                windowMs: 60_000, overlapMs: 3_000,
                baseUrl: settings.cloudBaseUrl, cloudModel: settings.cloudModel
            )
        case .cloud:
            // Hard cap WAV 5min (upstream ~60s timeout + base64 inflation).
            return EnginePlan(
                transcribeEngine: .cloud,
                model: settings.transcribeModel,
                knownLanguage: settings.transcribeLanguage,
                engineId: "openrouter-\(settings.cloudModel)",
                method: .cloud(model: settings.cloudModel, format: settings.cloudCompressAudio ? "m4a" : "WAV"),
                windowMs: 300_000, overlapMs: 3_000,
                baseUrl: settings.cloudBaseUrl, cloudModel: settings.cloudModel
            )
        }
    }

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
        let plan = plan(for: settings)
        let engineId = plan.engineId
        let method = plan.method

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
        run(jobId: jobId, plan: plan)
        return jobId
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        update(id) { $0.status = .canceled }
        persist()
        cleanupInput(id)
    }

    func remove(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        cleanupInput(id)
        jobs.removeAll { $0.id == id }
        persist()
    }

    // MARK: Pipeline

    private func run(jobId: String, plan: EnginePlan) {
        tasks[jobId]?.cancel()
        runner.beginGrace(name: "transcribe-\(jobId)")
        tasks[jobId] = Task { [weak self] in
            await self?.pipeline(jobId: jobId, plan: plan)
            self?.runner.endGrace()
        }
    }

    private func makeEngine(_ plan: EnginePlan) async throws -> TranscriptionEngine {
        switch plan.transcribeEngine {
        case .onDevice where plan.model.backend == .sherpa:
            // Check the engine is built BEFORE downloading a large model.
            guard SherpaEngineFactory.isAvailable else {
                throw TranscribeError.engineUnavailable(
                    "sherpa-onnx 引擎尚未建置。請執行 scripts/fetch-sherpa-libs.sh，並依 project.yml 內的註解加入 sherpa-onnx.xcframework 後重新產生專案。"
                )
            }
            let dir = try await SherpaModelManager.shared.ensureDownloaded(plan.model)
            guard let engine = SherpaEngineFactory.engine(model: plan.model, modelDir: dir) else {
                throw TranscribeError.engineUnavailable("sherpa-onnx 引擎建立失敗。")
            }
            return engine
        case .onDevice:
            let modelPath = try await WhisperModelManager.shared.ensureDownloaded(plan.model).path
            guard let engine = TranscriptionEngineFactory.onDeviceEngine(model: plan.model, modelPath: modelPath) else {
                throw TranscribeError.engineUnavailable(
                    "裝置端轉錄引擎尚未建置。請執行 scripts/build-whisper.sh，並依 project.yml 內的註解加入 whisper.xcframework 後重新產生專案。"
                )
            }
            return engine
        case .cloud:
            guard let key = KeychainStore.apiKey() else { throw TranscribeError.noApiKey }
            return CloudTranscriptionEngine(apiKey: key, baseUrl: plan.baseUrl, model: plan.cloudModel)
        }
    }

    private func pipeline(jobId: String, plan: EnginePlan) async {
        guard case .localFile(let path)? = job(jobId)?.source else { return }
        let url = URL(fileURLWithPath: path)
        let knownLanguage = plan.knownLanguage
        update(jobId) { $0.status = .running }
        do {
            let engine = try await makeEngine(plan)

            let durationMs = try await AudioToPCM.durationMs(of: url)
            let windows = WindowPlanner.plan(totalMs: durationMs, windowMs: plan.windowMs, overlapMs: plan.overlapMs)
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
                        self?.update(jobId) {
                            // Live preview only. This Task is detached, so it can
                            // land AFTER the window's final merge / the terminal
                            // OpenCC pass; guard on .running so a stale partial
                            // never clobbers the finalized (converted) text.
                            guard $0.status == .running else { return }
                            $0.text = SegmentMerge.merge([base, partial.partialText])
                        }
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
