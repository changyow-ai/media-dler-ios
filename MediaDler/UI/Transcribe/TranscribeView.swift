import SwiftUI
import MediaDlerCore

/// Progress + result screen for a transcription job. M0 is a skeleton that
/// confirms the local-file → menu → result-page wiring; the engine, live text,
/// progress, copy/share and cancel arrive in M1.
struct TranscribeView: View {
    let media: LocalMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: media.isVideo ? "film" : "music.note")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(media.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(media.isVideo ? "影片 · 轉成文字" : "聲音檔 · 轉成文字")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("轉錄引擎將於里程碑 1（on-device whisper.cpp）接上。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding()
            .navigationTitle("逐字稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }
}
