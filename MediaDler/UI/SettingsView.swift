import SwiftUI
import MediaDlerCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var models = WhisperModelManager.shared
    @State private var apiKey = ""
    @State private var modelTick = 0

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

                transcribeSection

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
            .onAppear { apiKey = KeychainStore.apiKey() ?? "" }
        }
    }

    // MARK: Transcription

    @ViewBuilder private var transcribeSection: some View {
        Section("逐字稿（影音轉文字）") {
            Picker("引擎", selection: $settings.settings.transcribeEngine) {
                Text("裝置端（離線）").tag(TranscribeEngine.onDevice)
                Text("雲端 OpenRouter").tag(TranscribeEngine.cloud)
            }
            Picker("轉錄語言", selection: $settings.settings.transcribeLanguage) {
                ForEach(TranscribeLanguage.allCases, id: \.self) { lang in
                    Text(languageLabel(lang)).tag(lang)
                }
            }
            Text("選「中文」可鎖定主語言並確保輸出為台灣正體（雲端 AUTO 不回語言時，中文會停在簡體）。")
                .font(.footnote).foregroundStyle(.secondary)
        }

        if settings.settings.transcribeEngine == .onDevice {
            Section("裝置端模型") {
                Picker("模型", selection: $settings.settings.transcribeModel) {
                    Text("base（較快、較省記憶體）").tag(TranscribeModel.base)
                    Text("small（較準、較大）").tag(TranscribeModel.small)
                }
                modelStatusRow(settings.settings.transcribeModel)
                Text("模型首次使用時下載（不內建在 App），存在 App 支援目錄。非 Wi-Fi 會先詢問。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Section("雲端設定（OpenRouter）") {
                TextField("Base URL", text: $settings.settings.cloudBaseUrl)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("Model", text: $settings.settings.cloudModel)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("API 金鑰（存 Keychain）", text: $apiKey)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onChange(of: apiKey) { newValue in KeychainStore.saveApiKey(newValue) }
                Toggle("壓縮音訊上傳（m4a）", isOn: $settings.settings.cloudCompressAudio)
                Text("OpenRouter 按音訊「時長」計費，與格式／大小無關 → 壓縮省頻寬不省錢，預設用 WAV（品質較佳、分短窗）。推薦 model：openai/whisper-large-v3-turbo（$0.04/hr）。金鑰只存本機 Keychain，不寫進設定檔、不進原始碼／IPA。")
                    .font(.footnote).foregroundStyle(.secondary)
                if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("尚未設定金鑰，雲端轉錄會失敗。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder private func modelStatusRow(_ model: TranscribeModel) -> some View {
        let _ = modelTick // recompute after delete
        if models.activeDownload == model {
            HStack {
                Text("下載中…")
                Spacer()
                ProgressView(value: models.progress).frame(width: 120)
            }
        } else if WhisperModelManager.isDownloaded(model) {
            HStack {
                Label("已下載", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button("刪除", role: .destructive) {
                    models.delete(model)
                    modelTick += 1
                }
            }
        } else {
            Button("下載模型") {
                Task { try? await models.ensureDownloaded(model) }
            }
        }
    }

    private func languageLabel(_ lang: TranscribeLanguage) -> String {
        switch lang {
        case .auto: return "自動偵測"
        case .zh: return "中文（正體）"
        case .en: return "英文"
        case .ja: return "日文"
        case .ko: return "韓文"
        case .es: return "西班牙文"
        case .fr: return "法文"
        case .de: return "德文"
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
