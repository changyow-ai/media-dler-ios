import SwiftUI
import MediaDlerCore

struct PickerView: View {
    let item: MediaItem
    let audioFormat: AudioFormat
    let onPick: (FormatSelection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if item.isImage {
                    row("下載圖片", "photo", .imageOriginal)
                } else {
                    Section("影片") {
                        row("最佳畫質", "film", .bestVideo)
                        ForEach(caps, id: \.self) { h in
                            row("\(h)p", "film", .cappedVideo(maxHeight: h))
                        }
                    }
                    Section("音訊") {
                        row("轉存 \(audioFormat.ext.uppercased())", "music.note", .audio(audioFormat))
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var caps: [Int] {
        let maxH = item.formats.compactMap { $0.height }.max() ?? 0
        let standard = [1080, 720, 480, 360]
        let filtered = standard.filter { maxH == 0 || $0 <= maxH }
        return filtered.isEmpty ? standard : filtered
    }

    private func row(_ title: String, _ icon: String, _ selection: FormatSelection) -> some View {
        Button { onPick(selection) } label: {
            Label(title, systemImage: icon)
        }
    }
}
