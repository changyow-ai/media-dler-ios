import SwiftUI

/// The action menu shown after a local media file is shared in:
/// - video → 「轉成文字」 or 「取出聲音」 (lossless audio extraction, M6)
/// - audio → 「轉成文字」 only
extension View {
    func localMediaSheet(
        _ media: Binding<LocalMedia?>,
        onTranscribe: @escaping (LocalMedia) -> Void,
        onExtractAudio: @escaping (LocalMedia) -> Void
    ) -> some View {
        modifier(LocalMediaSheet(media: media, onTranscribe: onTranscribe, onExtractAudio: onExtractAudio))
    }
}

struct LocalMediaSheet: ViewModifier {
    @Binding var media: LocalMedia?
    let onTranscribe: (LocalMedia) -> Void
    let onExtractAudio: (LocalMedia) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            media?.title ?? "",
            isPresented: presented,
            titleVisibility: .visible,
            presenting: media
        ) { m in
            Button("轉成文字") { onTranscribe(m) }
            if m.isVideo {
                Button("取出聲音（存成音檔）") { onExtractAudio(m) }
            }
            Button("取消", role: .cancel) { media = nil }
        }
    }

    private var presented: Binding<Bool> {
        Binding(get: { media != nil }, set: { if !$0 { media = nil } })
    }
}
