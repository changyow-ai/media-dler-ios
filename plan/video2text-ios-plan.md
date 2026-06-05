# 計劃：video2text（iOS）— 在 media-dler-ios 上擴充「影音轉逐字稿」

> 本計劃把 Android 版 [`plan/video2text-plan.md`](./video2text-plan.md) 的「影音轉逐字稿」能力，
> **用 iOS 原生方式**移植到現有 **media-dler-ios**（Swift + SwiftUI + `MediaDlerCore` + YoutubeDL-iOS）。
> 不另開 repo、不改動既有下載路徑（surgical changes），轉錄走獨立 flow。
>
> Android 版已 ~95% 完成並真機驗過（M0–M8）；本計劃**直接照搬其平台無關決策與 API 契約**（見對照表），
> 只把平台整合層改寫成 iOS（AVFoundation / URLSession / Keychain / BGTask / 文件開啟），
> 並針對 iOS 三個硬限制（無前景服務、免費簽章無 App Groups、Share Extension 記憶體上限）重新設計長任務與檔案入口。

---

## 實作狀態（branch `feat/video2text`，2026-06-05）

> 程式碼已實作 M0–M6；**`swift test` 79 綠燈、`xcodebuild`（simulator 免簽）BUILD SUCCEEDED**。
> 尚需「真機 / 網路 / 金鑰」才能驗證的執行期行為見下。

- **M0 ✅ 完整驗證**：`MediaDlerCore/Transcribe/`（WindowPlanner / SegmentMerge / LanguageDecision / SubtitleVtt / TranscriptFormatter / Transcript / TranscriptionEngine）+ 32 個 XCTest；`Settings` 擴充；`project.yml` `CFBundleDocumentTypes`；`onOpenURL` 分流；`LocalMediaInput` 收檔複製；`LocalMediaSheet` + `TranscribeView` 串通。
- **M1 ✅ 程式完成（待真機）**：`AudioToPCM`（AVAssetReader decodeRange）、`WhisperModelManager`（HF 下載 + NWPath Wi-Fi gate）、`LibWhisper`/`WhisperCppEngine`（**`#if canImport(whisper)` 守護**）、`KeychainStore`、`TranscriptJob/Store/Manager/Runner`（checkpoint/resume + beginBackgroundTask + 通知 + 引擎切換防呆）。
  - ⚠️ **whisper 引擎決策（與 codex 討論結論）**：走 **vendored `whisper.xcframework`**（`build-xcframework.sh`），**非 SwiftPM**（master 已無可用 Package.swift）。產物不入 git → `make whisper`（`scripts/build-whisper.sh`）建置後，**取消 `project.yml` 內 whisper.xcframework 依賴註解**再 `make project`。引擎碼以 `canImport(whisper)` 守護，未建置時 app 照常編譯、裝置端轉錄會回報「請先建置引擎」。
- **M3 ✅ 程式完成（待金鑰/網路）**：`CloudTranscriptionEngine`（OpenRouter JSON+base64）+ `WavEncoder`；引擎切換（`EnginePlan`：裝置端 60s/3s、雲端 WAV 5min）；設定頁三欄 + 壓縮開關 + 金鑰存 Keychain。**雲端路徑不需 xcframework，simulator+金鑰即可端到端跑。**
- **M4 ✅**：結果頁「存成 .txt」→ `DocumentsStorage`。
- **M5 ✅**：`TranscriptFormatter` 顯示斷句（已測）；`methodLabel` 顯示轉譯方式；歷史頁。
- **M6 ✅ 程式完成（待真機）**：`AudioTrackExtractor`（AVAssetExportSession passthrough 無損 → .m4a）。
- **M2 ⚠️ 部分**：ask-mode picker 加「轉成文字」→ 下載 bestaudio → 收編為 LocalMedia 走同一 pipeline。**YouTube CC 捷徑暫緩**（`SubtitleVtt` 已在 core 備好；YoutubeDL-iOS 字幕能力待確認，目前一律 fallback 下載音訊）。
- **M7 ⬜ 未做**：sherpa-onnx 第二後端（選配/高階機，依計劃「先跑通 whisper.cpp」暫緩）。
- **取捨/簡化（誠實記錄）**：雲端用一般 `URLSession`（非 background session）；whisper 即時文字為「逐窗回報」而非 intra-window C callback 串流；未註冊 `BGProcessingTaskRequest`（前景+寬限+checkpoint 已覆蓋多數情境）；base64 直接組（窗已上限 5min，未做 3-byte 串流寫出）。以上皆為可後續強化的 refinement。

---

## Context（為什麼做這個）

收到分享 → 變逐字稿。輸入三種，全部匯入同一條 pipeline：

1. **本機 video/voice 檔分享**（手機內檔案直接分享進來）。
2. **影片連結分享**（沿用既有 `YtDlpEngine` 下載音訊）。
3. **YouTube（或任何 yt-dlp 有字幕的站）有 CC** → 直接抓字幕，**完全跳過下載音訊／切段／轉錄引擎**。

姊妹專案：`fun-tools/whisper`（桌面 Qwen3-ASR + opencc `s2twp` 正體）是品質參照；
`fun-tools/media-dler`（Android）是本計劃的來源。on-device 引擎走 whisper.cpp（與 Android 同一份），
雲端走 OpenRouter（與 Android 同一契約）。

---

## 收斂後的需求（沿用 Android musk-review 結論，加 iOS 特有取捨）

- **輸入**：本機檔 / 連結 / YouTube CC 捷徑，三者共用 pipeline。
- **分享路由（UX，與既有下載共存）**：
  - **分享網址** → 沿用既有 URL 路徑（Share Extension → `mediadler://` deep-link → `AppModel`）。在 **彈窗（ask）模式**的 picker 多加一個「轉文字」動作，與下載選項並列。
    - ⚠️ **iOS 限制（同 Android）**：one-tap 模式不顯示 picker，故「連結轉文字」目前僅在 ask 模式可用（surgical，不動 one-tap 行為）。
  - **分享本機檔** → 走 iOS 文件開啟路徑（見「本機檔輸入設計」），主 app 收到 `file://` 後跳選單：
    - **影片** → 「轉成文字」**或「取出聲音」**（無損抽音軌存成 .m4a，不轉文字）。
    - **聲音檔** → 只有「轉成文字」。
  - 既有下載功能、首頁、清單**完全不動**。
- **轉錄引擎**：`MediaDlerCore` 定義 `TranscriptionEngine` 協定、可抽換。
  - **第一個實作：on-device whisper.cpp**（離線、隱私、免金鑰）— 也是**預設引擎**。
  - **第二階段：雲端 OpenRouter**（JSON + base64，base URL + model 設定化）。
    **金鑰由使用者在 app 內貼上、存進 Keychain；原始碼/IPA 不內建任何 key。**
- **語言**：多語言自動偵測；偵測到中文 → opencc `s2twp` 轉台灣正體。並提供「轉錄語言」設定鎖定主語言（解語言誤判 + OpenRouter AUTO 不回 language 的正體 caveat，見下）。
- **解碼 / 切段（不靠 ffmpeg 任意指令）**：
  - **本機檔 → PCM 用 AVFoundation `AVAssetReader`**（系統內建、零相依、支援 mp4/m4a/aac/mp3/wav/caf 等），輸出 **16kHz mono Float32**。
  - **連結 → 音訊**走既有 `YtDlpEngine`（yt-dlp `-x` / bestaudio，FFmpeg-iOS 那條路徑可用），落地後再用 `AVAssetReader` 解 PCM。
  - **on-device 不硬切檔案**：whisper.cpp 內部已用 30s window，真正限制是記憶體。
    → **依時長分窗，每窗只 `decodeRange(start,end)` 出該窗 PCM、用完即釋放**（對齊 Android：1hr 從 ~230MB 降到單窗數 MB）。
  - **硬切只留給雲端**（OpenRouter 上游 ~60s timeout + base64 膨脹）；切點優先靜音/窗界。
- **輸出**：結果頁顯示全文 + 一鍵複製 + 系統分享（`UIActivityViewController`）。**存成 .txt 列選配（M4）。** 不做時間軸字幕。

### iOS 特有的砍掉/重設計（相對 Android）

- **Android 的前景服務（`TranscriptionService`/`AudioExtractionService`）iOS 無對應** → 改「前景跑 + `beginBackgroundTask` 寬限 + checkpoint/resume + 雲端走 background URLSession」。**這是最大結構差異**（見「長任務存活設計」）。
- **本機檔不走 Share Extension**（記憶體上限 + 免費簽章無 App Groups 無法把檔案傳回主 app）→ 改 **`CFBundleDocumentTypes` 文件開啟**，由系統把檔案複製進主 app 容器（見「本機檔輸入設計」）。
- **金鑰存 Keychain**（比 Android DataStore 明文更安全）。
- **sherpa-onnx 第二後端（Android M8）列為 iOS 選配 M8**：iOS 有官方 prebuilt xcframework + Swift API，可移植；但屬高階機選項，先把 whisper.cpp 跑通。

---

## 架構（沿用既有 `MediaDlerCore` + App 分離，新增獨立 flow）

對齊既有 iOS 專案的「純邏輯（可單測）/ 平台整合分離」：

```
MediaDlerCore/  （純 Swift Package，無 UIKit/AVFoundation 相依，可 XCTest）
  Sources/MediaDlerCore/Transcribe/
    TranscriptionEngine.swift   協定：func transcribe(...) / streaming 介面 + StreamResult
    Transcript.swift            結果模型（text, detectedLang, segments?）+ AudioRef
    WindowPlanner.swift         純函式：算分窗（大窗+重疊）與雲端切段點（時長上限觸發）
    SegmentMerge.swift          多段轉錄結果合併（去重疊、接縫；精確 suffix==prefix）
    LanguageDecision.swift      偵測語言 → 是否套 opencc 的決策
    SubtitleVtt.swift           VTT → 純文字（去時間軸、去重複行）
    TranscriptFormatter.swift   顯示用斷句（句末標點硬斷 + 過長軟斷；raw 保持無換行）
  Tests/MediaDlerCoreTests/Transcribe*Tests.swift   ← red/green 閘門（對齊 Android :core JUnit）

MediaDler/ (App target, SwiftUI)
  Transcribe/
    WhisperBridge / WhisperContext.swift   whisper.cpp Swift/ObjC 橋（whisper.swiftui 模式）
    WhisperCppEngine.swift      TranscriptionEngine 的 whisper.cpp 實作（M1，預設引擎）
    WhisperModelManager.swift   ggml 模型下載/快取/選擇（base / small；HF resolve URL）
    AudioToPCM.swift            AVAssetReader → 16kHz mono Float32（durationMs + decodeRange 分窗串流）
    AudioEncoder.swift          PCM → AAC m4a（AVAudioConverter / AVAssetWriter，雲端壓縮選項用）
    AudioTrackExtractor.swift   無損抽音軌 → m4a（AVAssetExportSession presetPassthrough，只留 audio）
    CloudTranscriptionEngine.swift  OpenRouter JSON+base64（URLSession，background session）
    OpenCCConverter.swift       簡→繁正體（SwiftyOpenCC，s2twp config）
    LinkAudioResolver.swift     URL → 探字幕(VTT) 或 yt-dlp -x bestaudio（包既有 YtDlpEngine）
    TranscriptJob.swift         job 狀態（id 由來源導出可續跑 / status / progress / text / completedWindows / engineId / method）
    TranscriptStore.swift       JSON 檔持久化（對齊既有 HistoryStore，只在 checkpoint/終態寫入）
    TranscriptionManager.swift  記憶體 live @Published 為 UI 單一真相；佇列、續跑、cancel、清暫存
    TranscriptionRunner.swift   取代 Android foreground service：前景跑 + beginBackgroundTask + BGTask 排程
    KeychainStore.swift         API key 存取（kSecClassGenericPassword）
  UI/Transcribe/
    TranscribeView.swift        進度 + 結果頁（即時文字 / 複製 / 分享 / 放棄 / 轉譯方式）
    TranscriptHistoryView.swift 歷史清單（Home 加入口）
  UI/LocalMediaSheet.swift      本機檔選單（confirmationDialog：影片→轉文字/取出聲音；聲音→轉文字）
  （SettingsView 加：引擎 / 語言 / 模型(下載狀態) / 雲端三欄 + 壓縮開關+說明）
  （AppModel 加 transcribe 路由；MediaDlerApp.onOpenURL 分流 file:// vs mediadler://）
```

⚠️ **把平台無關的易錯邏輯（分窗、接縫去重、斷句、語言決策、VTT 解析）放進 `MediaDlerCore` 寫 XCTest**（紅綠閘門）；引擎、AVFoundation、URLSession、Keychain、檔案入口等無法純單測的整合碼留在 App 層，交給 `xcodebuild` 編譯 + 實機驗證把關（與既有專案分工一致）。

whisper.cpp 走官方 **SwiftPM**（whisper.cpp repo 有 `Package.swift`）或 vendored xcframework（由 `make` 產出，不入 git），搭配 `whisper.swiftui` 範例的 `WhisperContext` Swift wrapper。模型不進 IPA，首次使用下載。

---

## Android → iOS 對照（平台整合層改寫）

平台無關（**直接照搬邏輯/契約到 `MediaDlerCore`**）：`WindowPlanner`、`SegmentMerge`、`TranscriptFormatter`、`LanguageDecision`、`SubtitleVtt`、OpenRouter API 契約與 model 取捨、轉錄狀態機（job/checkpoint/resume/cancel）、引擎切換防呆（engineId 不同丟 checkpoint 重轉）。

| Android 元件 | iOS 對應 |
|---|---|
| whisper.cpp JNI（`WhisperNative`/`whisper_jni.cpp`） | 同一份 whisper.cpp，走 `whisper.swiftui` 的 Swift/ObjC 橋（`WhisperContext`）；SwiftPM 或 vendored xcframework；ggml 模型相同 |
| `AudioToPcm`（MediaCodec/MediaExtractor→16k mono float，`decodeRange`） | `AudioToPCM`：`AVAssetReader` + `AVAssetReaderTrackOutput`（PCM Float32, 16k mono）；時長讀 `AVAsset.duration`；分窗用 reader `timeRange` 限定區段 |
| `AudioEncoder`（PCM→AAC m4a，壓縮上傳用） | `AVAudioConverter` 或 `AVAssetWriter`（AAC-LC 16k mono ~32kbps）；僅雲端壓縮選項需要 |
| `AudioTrackRemuxer`（無損抽音軌→m4a） | `AVAssetExportSession(presetName: passthrough)`，`outputFileType=.m4a`，只保留 audio track（或 `AVAssetReader`+`AVAssetWriter` passthrough） |
| `CloudTranscriptionEngine`（JSON+base64 HTTP） | `URLSession`（background config），契約**完全相同**（見「OpenRouter STT API 契約」） |
| 設定 DataStore + 金鑰 | `UserDefaults`（沿用 `SettingsStore`）；**金鑰存 Keychain**（`KeychainStore`） |
| `TranscriptionService`/`AudioExtractionService`（foreground service） | **iOS 無前景服務**：前景跑 + `UIApplication.beginBackgroundTask`（寬限續跑到 checkpoint）+ `BGProcessingTaskRequest`（重排）+ 雲端 background `URLSession`。詳見「長任務存活設計」 |
| `MediaStoreStorage`/`SafStorage`（Downloads/SAF 存檔） | 沿用既有 `DocumentsStorage`（app Documents `media-dler/`，已開 Files app 存取）+ `UIActivityViewController` 匯出 |
| `ShareReceiverActivity` + intent-filter（video/*、audio/*） | **本機檔走 `CFBundleDocumentTypes` 文件開啟**（系統複製進主 app Inbox，免 App Group、免 extension）；URL 仍走既有 Share Extension。詳見「本機檔輸入設計」 |
| `LocalMediaSheet`/`ShareSheet`（Compose Dialog） | SwiftUI `confirmationDialog` / sheet |
| `Notifications`（前景/完成/失敗） | `UNUserNotificationCenter`（完成/失敗 local notification；長任務在前景以 UI 進度為主） |
| `OpenCcConverter`（opencc4j s2t） | `SwiftyOpenCC`（s2twp config，片語在地化優於字元級） |
| yt-dlp（連結下載/字幕，youtubedl-android） | 既有 `YtDlpEngine`（YoutubeDL-iOS）：bestaudio 取音訊；字幕能力以套件實測為準，抓不到自動 fallback 下載音訊 |
| sherpa-onnx 第二後端（M8） | sherpa-onnx 官方 iOS prebuilt xcframework + `swift-api`（vendored），同模型（SenseVoice/Paraformer/Qwen3）；列選配 |

---

## 本機檔輸入設計（iOS 關鍵：免 App Group、免 extension 跑引擎）

⚠️ **Android 用 `ShareReceiverActivity` + intent-filter 直接收 `content://` 檔案；iOS 不能照搬。** 原因：
1. **Share Extension 有嚴格記憶體上限（≈120MB）**，但我們連 whisper、連把整窗 PCM 載入都吃記憶體 → extension 不能跑引擎（既有 `ShareViewController` 註解已言明）。
2. **免費個人簽章拿不到 App Groups entitlement** → extension 與主 app 容器隔離，extension 無法把檔案 bytes 傳回主 app（deep-link 只能帶字串，帶不了檔案）。

✅ **iOS 原生解法：用 `CFBundleDocumentTypes` 宣告主 app 支援 video/audio，走「文件開啟 / Copy to media-dler」路徑。** 使用者在其他 app（Files / Photos / 訊息…）分享一個影片或音檔、選 media-dler，**系統會把檔案複製進主 app 的 `Documents/Inbox/`**（或給 in-place security-scoped URL），並以 `file://` URL 啟動主 app，由 `.onOpenURL` 接住。**完全繞開 extension 記憶體上限與 App Group 需求。**

- `project.yml` 主 app `info.properties` 加：
  ```yaml
  CFBundleDocumentTypes:
    - CFBundleTypeName: Audio/Video
      LSHandlerRank: Alternate
      LSItemContentTypes:
        - public.movie
        - public.audio
        - public.mpeg-4
        - public.mp3
        - com.apple.m4a-audio
  ```
  （`UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` 既有，維持。）
- **`MediaDlerApp.onOpenURL` 分流**：`url.isFileURL` → 本機檔轉錄路徑；`scheme == "mediadler"` → 既有 URL 路徑。
- **收檔即複製進私有 storage**（對齊 Android M2b「複製進私有 storage 才能續跑」）：
  - 若是 security-scoped URL：`startAccessingSecurityScopedResource()` → 立刻 `copyItem` 到 `Documents/transcribe/input/<jobId>.<ext>` → `stopAccessing...`。
  - 若在 `Documents/Inbox/`：搬出 Inbox 到 `transcribe/input/`（Inbox 檔需盡快移走）。
  - 私有複本是 job 的可續跑來源；job 完成/取消時清除（FAILED 保留以利續跑——見「已知問題」修法）。
- 收檔後 `AppModel` 顯示 `LocalMediaSheet`（`isVideo = UTType(filenameExtension:)` 判定）：影片→「轉成文字」/「取出聲音」；聲音→「轉成文字」。

> **note**：宣告 doc types 後，本機影音檔分享會出現「media-dler」可選；既有 Share Extension 的 activation rule 只配 WebURL+text，故 URL 走 extension、本機檔走 doc-open，兩者互補不重複。**免費簽章「最多 3 個 App ID」**：主 app + Share Extension 已用 2 個，doc-open 不需新增 target，不吃額度。

---

## 長任務存活設計（iOS 無前景服務 — 最大結構差異）

Android 用 foreground service（`dataSync`）讓長轉錄/抽音存活；iOS 沒有等價物。設計：

- **狀態機照搬 Android**：`TranscriptJob`（id 由來源導出 → 可續跑）+ `TranscriptStore`（JSON 檔）+ `TranscriptionManager`（記憶體 `@Published` 為 UI 單一真相；高頻更新只在記憶體，**只在窗完成 checkpoint / 終態才持久化**）。窗單位 **60s + 3s 重疊**當 checkpoint。
- **on-device（whisper / sherpa）跑在前景**：
  - 進入轉錄頁時 `UIApplication.shared.isIdleTimerDisabled = true`（避免自動鎖屏中斷），離開還原。
  - 使用者切到背景：`beginBackgroundTask(withName:)` 取得寬限（通常數十秒～數分鐘），**用這段時間把當前窗跑完並 checkpoint**，到期前 `endBackgroundTask`；下次回前景或下次啟動從 checkpoint 續跑。
  - 註冊 `BGProcessingTaskRequest`（`requiresExternalPower`/`requiresNetworkConnectivity` 視需要）作為「之後系統許可時繼續跑剩餘窗」的盡力路徑（非即時保證）。
  - App 被殺/重啟：啟動時 hydrate，`hasPending` → 自動續跑；`firstUnseenCompleted` → 跳結果頁（對齊 Android `MainActivity` 行為）。
- **雲端（OpenRouter）走 background `URLSession`**：逐窗上傳的 HTTP 請求用 `URLSessionConfiguration.background(withIdentifier:)`，背景/被殺後系統仍可完成傳輸並喚醒 app 處理回應（比 on-device 更耐背景）。
- **完成/失敗發 local notification**（`UNUserNotificationCenter`）：長任務在背景完成時通知使用者；前景時以 UI 進度為主。
- **進度與中止**：whisper.cpp 的 `progress_callback` / `new_segment_callback` / `abort_callback` 經 Swift 橋接出 `WhisperContext` callback（即時文字 + 進度 + 可中止），不縮窗、不犧牲準確度（對齊 Android M2b）。

> 取捨：on-device 長音訊在 iOS 無法保證「鎖屏後一路跑完」（無前景服務）。實務上：**前景跑 + 防鎖屏 + 寬限期 checkpoint + 續跑**已能覆蓋多數情境；要全程背景請用雲端（background URLSession）。此取捨明列於設定頁說明與「已知問題」。

---

## OpenRouter STT API 契約（iOS 照此實作，與 Android 完全相同）

- **端點**：`POST https://openrouter.ai/api/v1/audio/transcriptions`，`Content-Type: application/json`，`Authorization: Bearer <key>`。
- **Body**：`{"model":"<id>", "language":"zh"(可省，省則自動偵測), "input_audio":{"format":"wav"|"m4a"|"mp3"|"flac"|"ogg", "data":"<raw base64，非 data URI>"}}`。
- **回應**：`{"text":"...", "usage":{"seconds":183.86, "cost":0.00204}}`。**無 language 欄、無 segments/timestamps**（不支援 `verbose_json`）。
- **計費**：按**音訊時長**（秒），與 bytes/格式無關 → 壓縮省頻寬不省錢；用 `usage.cost` 對帳。
- **限制**：上游 ~**60s timeout** → 長音訊務必分窗（WAV 5min / m4a 10min，照 Android）。base URL 須 https（iOS ATS 預設禁 cleartext，正好一致）。
- **base64 串流**：以 3-byte 對齊分塊寫出，**不要把整個 ~25MB base64 一次進記憶體**（照 Android）。
- **model id 實測**（Android 已驗，iOS 沿用）：
  - ✅ `openai/whisper-large-v3-turbo` — WAV+m4a 皆可，最便宜 **$0.04/hr**，**推薦預設**。
  - ❌ `openai/whisper-large-v3` — 反覆 `Provider returned 400`，不可用。
  - ⚠️ `qwen/qwen3-asr-flash-2026-02-10` — **只收 WAV，m4a→400**；最貴 **$0.126/hr**；同音字較準、自動加標點。（基本 id 不帶日期不存在）
- **正體 caveat**：OpenRouter 不回 language → **AUTO 時中文停在簡體不轉正體**（OpenCC 只在 language 已知時套）。解法：把「轉錄語言」設「中文」→ knownLanguage=zh → OpenCC 轉正體（iOS 同 Android 設計）。

---

## 實作步驟（里程碑）

### 里程碑 0 — 介面與骨架（先讓端到端可編譯）
- `MediaDlerCore/Transcribe/` 定義 `TranscriptionEngine`、`Transcript`/`AudioRef`、`WindowPlanner`、`SegmentMerge`、`LanguageDecision`、`SubtitleVtt`，全部寫 XCTest（紅綠）。
- `project.yml` 加 `CFBundleDocumentTypes`（video/audio）；`MediaDlerApp.onOpenURL` 分流 `file://`。
- App 端加 `TranscribeView` 空殼 + `AppModel` transcribe 路由 + `LocalMediaSheet` 骨架。
- **verify**：`swift test`（或 `xcodebuild test -scheme MediaDlerCore`）綠燈；`xcodebuild build`（simulator，免簽）過；分享一個本機影音檔能進到一個空結果頁。

### 里程碑 1 — on-device whisper.cpp 端到端（核心驗證）
1. 引入 whisper.cpp（SwiftPM 或 vendored xcframework）+ `WhisperContext` Swift wrapper（whisper.swiftui 模式），`WhisperCppEngine` 跑通單檔。
2. `AudioToPCM`：`AVAssetReader` 任意輸入 → 16kHz mono Float32；`duration` + `decodeRange(start,end)`（reader `timeRange` 限定區段、逐窗釋放）。
3. `WhisperModelManager`：首次下載 ggml 多語模型（預設 base，可選 small；HF resolve URL，存 app support，不進 IPA）；**Wi-Fi gate（詢問式）**：非 Wi-Fi（`NWPathMonitor` 判 `isExpensive`/cellular）下載前跳確認。
4. 串起：本機檔分享 →（`LocalMediaSheet` 只「轉文字」分支）→ PCM 分窗 → 逐窗 whisper（native callback 串流）→ `SegmentMerge` → `LanguageDecision` → `OpenCCConverter`（中文轉正體）→ 結果頁。
5. **狀態層 + 長任務存活**：`TranscriptJob`/`TranscriptStore`/`TranscriptionManager`/`TranscriptionRunner`（前景跑 + `beginBackgroundTask` + checkpoint/resume + 防鎖屏）；進度 + 即時文字回報到 UI。
6. 結果頁：即時文字 + 進度 + 全文 + 複製 + 分享 + **放棄**（cancel → 清私有複本）。
- **verify（end-to-end，實機）**：分享 1–2 分中文語音 → 出正體逐字稿；英文 → 英文原文；30 分音檔 → 分窗、進度推進、不 OOM；中途切背景再回前景 → 從 checkpoint 續跑。

### 里程碑 2 — 連結輸入 + YouTube CC 捷徑
1. `LinkAudioResolver`：給 URL →（1）best-effort 探字幕（以 YoutubeDL-iOS 能力為準，抓到 VTT → `SubtitleVtt` 去時間軸出純文字、依語言碼套 OpenCC，**完全跳過引擎**）；（2）抓不到 → 既有 `YtDlpEngine` 取 bestaudio（m4a）下載 → 交回同一條 on-device pipeline。
2. **分享路由**：URL 分享的 ask-mode picker 加「轉文字」按鈕（`PickerView` → `AppModel.transcribeLink(url)`），與下載選項並列；既有下載完全不動。
3. `TranscribeView`/job 泛化：輸入分 `localFile`/`link`；連結走「解析(0–40%)→轉錄(40–100%)」兩階段，captions 命中則秒出。
- **限制**：連結轉文字僅 ask（彈窗）模式可用（one-tap 不顯示 picker，不動既有行為）；YouTube CC best-effort，抓不到自動 fallback 下載音訊。
- **verify**：有 CC 的 YouTube → 秒出文字、無引擎耗時；無 CC → 走轉錄；一般連結 → 走轉錄。

### 里程碑 3 — 雲端 OpenRouter 引擎 + 引擎切換 + 壓縮選項（對齊 Android M5）
1. `CloudTranscriptionEngine`：讀雲端設定（baseUrl/model/compressAudio）+ Keychain 金鑰；`WindowPlanner`（WAV 5min / m4a 10min）逐窗 `decodeRange` → WAV 或 `AudioEncoder` m4a → **JSON+base64** POST（background `URLSession`，`response_format` 不帶/不解析 verbose）→ 解析 `{text, usage}` → `SegmentMerge` + OpenCC；每窗一 checkpoint，臨時檔用完即刪。
2. **金鑰存 Keychain**（`KeychainStore`，`kSecClassGenericPassword`）；設定頁密碼欄輸入、可清除；原始碼/IPA 不內建任何 key。
3. 設定頁加：引擎選擇（裝置端/雲端，預設裝置端）、雲端三欄（baseUrl/model/key）、**壓縮開關 + ⓘ 說明**（WAV vs m4a/分窗/費用取捨）、未設定提示。
4. **引擎切換防呆**：`TranscriptJob.engineId` 記錄產生 checkpoint 的引擎；引擎不同時丟棄 checkpoint 乾淨重轉（窗制不同會接縫錯亂）。
- **verify**：切雲端、填金鑰，同段音訊出逐字稿（turbo WAV/m4a 皆通）；金鑰未設→快速 FAILED 並提示；AUTO 中文停簡體、設「中文」→ 正體。

### 里程碑 4（選配）— 存成 .txt
- 結果頁加「存檔」，沿用 `DocumentsStorage` 寫 `media-dler/<title>.txt`（Files app 可見），或 `UIDocumentPicker` 匯出。

### 里程碑 5 — 顯示層：可讀斷句 + 轉譯方式顯示（對齊 Android M6）
- `TranscriptFormatter`（`MediaDlerCore` + XCTest）：raw 逐字稿 → 斷行可讀（**僅供顯示/複製/分享**，raw 保持無換行以利接縫去重）。句末標點硬斷 + 過長無標點子句軟斷，不偽造句界。
- `TranscriptJob.method`（開跑時寫入）→ 結果頁標題下顯示「轉譯方式：…」：雲端 `雲端 · <model>（WAV|m4a）`／裝置端 `裝置端 · base|small`／字幕 `內嵌字幕（未經辨識）`。記在 job 上，歷史也正確。

### 里程碑 6 — 本機分享選單 + 影片抽音存檔（對齊 Android M7）
- `LocalMediaSheet`（`confirmationDialog`）：影片→「轉成文字」/「取出聲音（存成音檔）」；聲音→「轉成文字」。
- `AudioTrackExtractor`：`AVAssetExportSession(presetName: AVAssetExportPresetPassthrough)`，移除 video track（或只挑 audio）→ `.m4a`，**無損搬音軌**（不重新編碼）→ 重用 `DocumentsStorage` 存到 `media-dler/`（依 `storageDestination`）→ local notification。檔名 `sanitize(來源去副檔名)+".m4a"`。
- **verify（實機）**：影片分享→兩選項；「取出聲音」→ 輸出與原音軌一致（無損）、可播放、發完成通知；聲音檔分享→只有「轉成文字」。

### 里程碑 7（選配）— sherpa-onnx 第二裝置端後端（對齊 Android M8）
- 引入 sherpa-onnx 官方 iOS prebuilt（`sherpa-onnx.xcframework` + `onnxruntime.xcframework`）+ vendored `swift-api`；`SherpaOnnxEngine` 實作 `TranscriptionEngine`。
- 三模型：**SenseVoice-Small**（建議、有標點、非自回歸、中文準）、**Paraformer-zh**（純中文最準、無標點、固定 `zh`）、**Qwen3-ASR 0.6B**（多語高品質但大且自回歸 → **標「實驗/高階機」**，低記憶體裝置可能被系統殺，對齊 Android Qwen3 OOM 結論）。
- `TranscribeEngine{onDevice,cloud}` 不變；`TranscribeModel` 加 `backend`（whisperCpp/sherpa），on-device 下拉統一列模型、後端由所選模型推導；模型走官方 `.tar.bz2` 端上解壓（或逐檔）。音訊 16k mono float 與 sherpa 完全相容免轉換。
- **verify**：各模型下載+轉同一中文片比準度/速度；sherpa↔whisper 切換乾淨重轉；轉譯方式正確。

---

## 設定（`AppSettings` 擴充，存 UserDefaults；金鑰存 Keychain）

`MediaDlerCore/Settings.swift` 的 `AppSettings` 加（沿用既有 tolerant decoding，缺欄 fallback 預設，不 wipe 既有偏好）：

```swift
public enum TranscribeEngine: String, Codable, CaseIterable { case onDevice, cloud }
public enum TranscribeModel: String, Codable, CaseIterable { case base, small /* M7: turboQ5, senseVoice, paraformer, qwen3 */ }
public enum TranscribeLanguage: String, Codable, CaseIterable { case auto, zh, en, ja, ko, es, fr, de }

// 新增欄位：
//   transcribeEngine: TranscribeEngine = .onDevice
//   transcribeModel:  TranscribeModel  = .base
//   transcribeLanguage: TranscribeLanguage = .auto
//   cloudBaseUrl: String = "https://openrouter.ai/api/v1"
//   cloudModel:   String = "openai/whisper-large-v3-turbo"
//   cloudCompressAudio: Bool = false   // 預設 WAV
// 金鑰「不」放這裡 → KeychainStore（避免 UserDefaults 明文）
```

設定頁（`SettingsView` 新增區塊，沿用既有 `Form`/`Picker` 風格）：引擎選擇、轉錄語言、模型下拉（含下載/刪除狀態 + 進度 + Wi-Fi 詢問）、雲端三欄（baseUrl / model / key 密碼欄）、壓縮開關 + ⓘ 說明、清除暫存。

---

## 技術決策（iOS 取向，多方檢視後）

- **本機檔走 `CFBundleDocumentTypes` 文件開啟，非 Share Extension**：唯一能在免費簽章（無 App Groups）下把檔案 bytes 安全送進主 app、又不踩 extension 記憶體上限的原生路徑。收檔即複製進私有 storage（可續跑）。
- **長任務：前景跑 + `beginBackgroundTask` 寬限 + checkpoint/resume + 雲端 background URLSession**，取代 Android 前景服務。on-device 鎖屏全程跑無法保證，全程背景請用雲端。
- **裝置端解碼：`AVAssetReader`**（系統內建、零相依、支援主流容器），對齊 Android 不依賴任意 ffmpeg 指令的決策。
- **影片抽音：`AVAssetExportSession` passthrough（無損）**，非重新編碼，對齊 Android remux 決策。
- **雲端只支援 OpenRouter（JSON+base64）**，契約照搬 Android M5；壓縮為使用者選項、預設關（WAV 品質佳/短窗；費用按時長與格式無關）。
- **金鑰存 Keychain**（比 Android DataStore 明文更安全）；原始碼/IPA 不內建任何 key。
- **OpenCC：SwiftyOpenCC（s2twp）**，片語在地化優於 Android 目前的 opencc4j 字元級 s2t。
- **whisper.cpp 取得：官方 SwiftPM / whisper.swiftui 橋自建**（可控、模型同 ggml）；模型不進 IPA，首次下載 + Wi-Fi gate。
- **顯示層可讀斷句（`TranscriptFormatter`）**：raw 保持無換行（接縫去重靠精確 suffix==prefix），只在顯示/複製/分享斷句。
- **既有專案前提**：iOS 16+、Swift 5.0、`SWIFT_OPTIMIZATION_LEVEL=-Onone`（Release，因 PythonKit）；新轉錄碼避免依賴此 workaround，但須與之共存。

---

## 待踩坑預判（iOS 特有）

1. **whisper.cpp xcframework / SwiftPM 整合是最重的一塊**（對齊 Android「最重在引入引擎」）→ 列 M1，先打通「能 init context + 跑單檔」再往下。
2. **長音訊鎖屏中斷**：前景 + 防鎖屏 + 寬限 checkpoint；無法保證全程背景，明示使用者改用雲端。
3. **本機檔 in-place vs Inbox 兩種交付**：security-scoped 要 `startAccessingSecurityScopedResource` 並立刻複製；Inbox 檔盡快移走。兩路都複製進私有 storage。
4. **OpenRouter AUTO 中文停簡體**：提示設「轉錄語言＝中文」。
5. **base URL 須 https**（ATS）；雲端逐窗上傳目前無行動數據 gate（模型下載有 Wi-Fi 詢問）。
6. **sherpa Qwen3 在低記憶體機被系統殺**（Android 已驗 OOM）→ iOS 同列實驗/高階機。
7. **免費簽章 7 天到期需重簽**；最多 3 App ID（主+share 已 2 個，doc-open 不額外吃）。
8. **錯誤要夠詳細**：解析/轉錄/上傳失敗帶來源、HTTP 狀態；錯誤視圖可捲動 + 可複製（沿用既有風格）。

---

## 驗證方式（end-to-end）

0. ⚠️ `swift test`（或 `xcodebuild test -scheme MediaDlerCore`）綠燈：`WindowPlanner` / `SegmentMerge` / `TranscriptFormatter` / `LanguageDecision` / `SubtitleVtt`。
1. `xcodebuild build`（simulator，免簽）成功 → Xcode 簽章裝實機。
2. 本機影音檔分享 → 跳 `LocalMediaSheet` → 「轉成文字」→ 1–2 分中文 → 正體逐字稿；30 分音檔不 OOM、進度推進。
3. 切背景再回前景 → 從 checkpoint 續跑；殺 app 重啟 → 自動續跑/跳結果頁。
4. 影片「取出聲音」→ .m4a 進 Files app（media-dler），無損可播。
5. 連結（ask 模式 picker 加的「轉文字」）→ 有 CC 秒出、無 CC 走轉錄。
6. 雲端：填 Keychain 金鑰、切雲端 → 同段音訊出逐字稿（turbo）；AUTO 簡體、設中文 → 正體。
7. 結果頁「轉譯方式」正確；複製/分享可用；放棄清暫存。

---

## 不做（明確排除，同 Android）
- 時間軸字幕（SRT/VTT 輸出）、講者分離、即時串流轉錄、編輯逐字稿、雲端同步。
- 在 Share Extension 內跑引擎（記憶體上限）；用 App Group 共享容器（免費簽章不可用）。

---

## 與 Android 版的對照（差異摘要）

| 面向 | Android（`media-dler`） | iOS（本計劃） |
|---|---|---|
| on-device 引擎 | whisper.cpp JNI + sherpa-onnx | whisper.cpp（Swift 橋）+ sherpa-onnx xcframework（選配 M7） |
| 解碼 | MediaCodec/MediaExtractor | `AVAssetReader`（16k mono Float32, decodeRange） |
| 抽音軌 | MediaExtractor+MediaMuxer（無損） | `AVAssetExportSession` passthrough（無損） |
| 雲端 | OpenRouter JSON+base64（URLConnection） | OpenRouter JSON+base64（background URLSession，契約同） |
| 本機檔入口 | intent-filter（video/*、audio/*） | `CFBundleDocumentTypes` 文件開啟（免 App Group / 免 extension 跑引擎） |
| 長任務 | foreground service（dataSync） | 前景 + beginBackgroundTask + checkpoint/resume + 雲端 background URLSession |
| 金鑰 | DataStore（明文） | **Keychain** |
| 正體 | opencc4j（字元級 s2t） | SwiftyOpenCC（s2twp 片語） |
| 純邏輯模組 | `:core`（JUnit） | `MediaDlerCore`（XCTest） |
| 儲存 | MediaStore/SAF | `DocumentsStorage`（Files app）+ `UIActivityViewController` |
| 散布 | CI 簽 APK 發 Releases | 個人自簽，Xcode 手動裝機（CI 只測+編譯） |
