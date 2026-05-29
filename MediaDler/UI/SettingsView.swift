import SwiftUI
import MediaDlerCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("分享後行為") {
                    Picker("模式", selection: $settings.settings.shareMode) {
                        Text("彈窗選擇").tag(ShareMode.ask)
                        Text("一鍵下載").tag(ShareMode.oneTap)
                    }
                }

                Section("儲存位置") {
                    Picker("影片 / 圖片存到", selection: $settings.settings.storageDestination) {
                        Text("照片 App").tag(StorageDestination.photos)
                        Text("App 資料夾").tag(StorageDestination.appFolder)
                    }
                }

                Section("一鍵下載預設") {
                    Picker("類型", selection: $settings.settings.defaultMediaKind) {
                        Text("影片").tag(MediaKind.video)
                        Text("音訊").tag(MediaKind.audio)
                    }
                    Picker("畫質", selection: $settings.settings.defaultVideoQuality) {
                        ForEach(VideoQuality.allCases, id: \.self) { q in
                            Text(qualityLabel(q)).tag(q)
                        }
                    }
                    Picker("音訊格式", selection: $settings.settings.audioFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { f in
                            Text(f.ext.uppercased()).tag(f)
                        }
                    }
                }

                Section("下載引擎") {
                    HStack {
                        Text("yt-dlp 版本")
                        Spacer()
                        Text(model.engineVersion ?? "—").foregroundStyle(.secondary)
                    }
                    Button("更新 yt-dlp") { model.refreshEngine() }
                }

                Section {
                    Text(storageHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var storageHint: String {
        switch settings.settings.storageDestination {
        case .photos:
            return "影片與圖片會存入「照片」App；音訊（MP3 / M4A）一律存入 App 資料夾（可在「檔案」App 開啟）。"
        case .appFolder:
            return "影片、圖片與音訊都存入 App 資料夾，可在「檔案」App 開啟，也能從列表分享到其他 App。"
        }
    }

    private func qualityLabel(_ q: VideoQuality) -> String {
        switch q {
        case .best: return "最佳畫質"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
}
