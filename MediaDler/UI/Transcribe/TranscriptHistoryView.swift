import SwiftUI
import MediaDlerCore

/// History of transcription jobs. Tapping a row reopens the result/progress
/// screen (completed jobs show their text; failed jobs can retry).
struct TranscriptHistoryView: View {
    @ObservedObject var manager: TranscriptionManager
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var open: LocalMedia?

    var body: some View {
        NavigationStack {
            Group {
                if manager.jobs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("尚無逐字稿").foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(manager.jobs) { job in
                            Button { open = media(for: job) } label: { row(job) }
                                .swipeActions {
                                    Button("刪除", role: .destructive) { manager.remove(job.id) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("逐字稿紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .sheet(item: $open) { media in
                TranscribeView(media: media, manager: manager, settings: settings)
            }
        }
    }

    private func row(_ job: TranscriptJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title).font(.body).lineLimit(2)
            HStack(spacing: 6) {
                statusIcon(job)
                Text(job.methodLabel).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if job.status == .running {
                    Text("\(Int(job.progress * 100))%").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func statusIcon(_ job: TranscriptJob) -> some View {
        switch job.status {
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .canceled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        default: Image(systemName: "clock").foregroundStyle(.blue)
        }
    }

    /// Reconstructs a LocalMedia handle so TranscribeView can display/resume a
    /// stored job. For completed jobs the input file may be gone, but the view
    /// reads text straight from the job and won't restart.
    private func media(for job: TranscriptJob) -> LocalMedia {
        let path: String
        if case .localFile(let p) = job.source { path = p }
        else if case .link(let u) = job.source { path = u }
        else { path = "" }
        return LocalMedia(id: job.id, url: URL(fileURLWithPath: path), isVideo: false, title: job.title)
    }
}
