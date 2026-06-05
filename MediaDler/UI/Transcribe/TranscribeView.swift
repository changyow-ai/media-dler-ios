import SwiftUI
import UIKit
import MediaDlerCore

/// Progress + result screen for a transcription job. Reads its job from the
/// shared `TranscriptionManager` (single source of truth) and shows live text,
/// progress, the transcription method, and (on completion) copy / share /
/// discard.
struct TranscribeView: View {
    let media: LocalMedia
    @ObservedObject var manager: TranscriptionManager
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var started = false
    @State private var confirmExpensive = false
    @State private var savedNote: String?

    private var job: TranscriptJob? { manager.job(media.id) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("逐字稿")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .confirmationDialog(
                    "目前似乎使用行動數據／計費網路，仍要下載語音模型嗎？",
                    isPresented: $confirmExpensive,
                    titleVisibility: .visible
                ) {
                    Button("仍要下載") { start() }
                    Button("取消", role: .cancel) { dismiss() }
                }
                .alert("已存檔", isPresented: Binding(get: { savedNote != nil }, set: { if !$0 { savedNote = nil } })) {
                    Button("好", role: .cancel) { savedNote = nil }
                } message: {
                    Text(savedNote ?? "")
                }
        }
        .onAppear {
            startIfNeeded()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        let job = self.job
        VStack(alignment: .leading, spacing: 12) {
            header(job)
            switch job?.status {
            case .completed:
                resultBody(job)
            case .failed:
                failedBody(job)
            default:
                runningBody(job)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ job: TranscriptJob?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(media.title).font(.headline).lineLimit(2)
            if let label = job?.methodLabel {
                Text("轉譯方式：\(label)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func runningBody(_ job: TranscriptJob?) -> some View {
        let progress = job?.progress ?? 0
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: max(0, min(1, progress)))
            HStack {
                ProgressView().controlSize(.small)
                Text(progressText(job)).font(.caption).foregroundStyle(.secondary)
            }
        }
        liveText(job)
    }

    @ViewBuilder private func resultBody(_ job: TranscriptJob?) -> some View {
        ScrollView {
            Text(formatted(job?.text ?? ""))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func failedBody(_ job: TranscriptJob?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("轉錄失敗", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            ScrollView {
                Text(job?.errorMessage ?? "未知錯誤")
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("重試") { start() }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private func liveText(_ job: TranscriptJob?) -> some View {
        if let text = job?.text, !text.isEmpty {
            ScrollView {
                Text(formatted(text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
        } else {
            Spacer()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if job?.status == .completed, let text = job?.text, !text.isEmpty {
                let out = formatted(text)
                Button { UIPasteboard.general.string = out } label: {
                    Image(systemName: "doc.on.doc")
                }
                Button { saveTxt(out) } label: { Image(systemName: "square.and.arrow.down") }
                ShareLink(item: out) { Image(systemName: "square.and.arrow.up") }
            } else if let job, job.status == .running || job.status == .pending {
                Button(role: .destructive) {
                    manager.cancel(job.id)
                    dismiss()
                } label: { Text("放棄") }
            }
        }
    }

    // MARK: Logic

    private func startIfNeeded() {
        guard !started else { return }
        if let j = job, j.status == .completed { started = true; return }
        // Only the on-device engine downloads a model — gate that on Wi-Fi.
        // The download-state check MUST be backend-aware: WhisperModelManager
        // traps (preconditionFailure) on sherpa models, so route each backend
        // to its own manager.
        if settings.transcribeEngine == .onDevice {
            let model = settings.transcribeModel
            let downloaded = model.backend == .sherpa
                ? SherpaModelManager.isDownloaded(model)
                : WhisperModelManager.isDownloaded(model)
            if !downloaded && WhisperModelManager.isExpensiveNetwork() {
                confirmExpensive = true
                return
            }
        }
        start()
    }

    private func start() {
        started = true
        manager.startLocal(media, settings: settings)
    }

    private func progressText(_ job: TranscriptJob?) -> String {
        guard let job, job.totalWindows > 0 else { return "準備中…" }
        return "轉錄中 \(job.completedWindows)/\(job.totalWindows) 段 · \(Int((job.progress) * 100))%"
    }

    private func formatted(_ raw: String) -> String { TranscriptFormatter.format(raw) }

    /// Saves the formatted transcript as media-dler/<title>.txt (Files app).
    private func saveTxt(_ text: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(media.title).txt")
        do {
            try text.data(using: .utf8)?.write(to: tmp)
            let saved = DocumentsStorage.save(tmp, preferredName: media.title)
            try? FileManager.default.removeItem(at: tmp)
            savedNote = saved != nil ? "已存到「檔案」App 的 media-dler 資料夾。" : "存檔失敗。"
        } catch {
            savedNote = "存檔失敗：\(error.localizedDescription)"
        }
    }
}

