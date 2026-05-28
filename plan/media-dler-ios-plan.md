# 計劃:media-dler iOS — 分享下載 App（iOS 版）

> 本計劃由 Android 版 [`media-dler`](https://github.com/changyow-ai/media-dler) 的 [plan](https://github.com/changyow-ai/media-dler/blob/main/plan/media-dler-plan.md) 改寫而來，對齊功能、按 iOS 平台限制重新設計引擎、儲存與分享入口。**尚未實作**;下文為設計與待踩坑預判,標 ⚠️ 的是 iOS 特有、最可能卡住的地方。

## Context(為什麼做這個)

把 Android 版「從其他 app 分享一個 URL 過來,就自動解析並下載當中的影片或圖片」的體驗搬到 iOS,盡量支援主流平台(YouTube、Instagram、TikTok、Threads、X/Twitter、Facebook、Reddit、Bilibili…)。

經提問收斂出的需求(本次決策):

- **引擎**:採用 [`kewlbear/YoutubeDL-iOS`](https://github.com/kewlbear/YoutubeDL-iOS)(底層以 PythonKit 跑 yt-dlp,搭配 [`FFmpeg-iOS`](https://github.com/kewlbear/FFmpeg-iOS) 做轉檔/合流),一次涵蓋 yt-dlp 支援的 1000+ 平台,與 Android 同源。
- **技術棧**:原生 **Swift + SwiftUI**,**獨立 App**(不走 KMP 共用;Android `:core` 的純邏輯以 Swift 重寫,放進可單測的 Core 模組)。
- **散布/簽章**:sideload 取向(與 Android 同;`YoutubeDL-iOS` 作者明言 **NOT AppStore-safe**)。**個人 Apple ID 自簽 + 自用裝置**。⚠️ 這對架構有實質影響,見「散布與簽章限制」。
- **儲存位置(依類型分流)**:
  - **影片 / 圖片** → 存入 **Photos 媒體庫**(`PHPhotoLibrary`,需 `NSPhotoLibraryAddUsageDescription`)。
  - **音訊(mp3 / m4a)** → 存入 **App Documents**,並開放 **Files app** 存取(`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`)。⚠️ **Photos 不收音訊**,這是分流的根因。
- **分享入口(兩者都做)**:
  - **Share Extension**:在其他 app 點「分享 → media-dler」接住 URL。
  - **貼上連結 / URL Scheme**:首頁讀剪貼簿貼上;並註冊自訂 URL scheme(`mediadler://`)供 deep-link。
  - ⚠️ **yt-dlp 太重,不能在 Share Extension 內跑**(見「分享入口設計」)。Extension 只負責「接 URL → 交給主 app」。
- **App 內列表/歷史**:可以,照 Android 首頁做(進行中 + 歷史,可重試/刪除/開啟/分享)。
- **格式需求**:最佳畫質、可選解析度(1080p/720p/480p/360p)、音訊轉 MP3/M4A、圖片下載(含多圖貼文逐項勾選)。
- **兩種模式**:一鍵模式(用設定預設值直接下載)/ 彈窗模式(選畫質、音訊、勾選項目),可在設定切換。

## 架構總覽

對齊 Android 的「純邏輯 / 平台整合分離」原則,但落在單一 Xcode workspace:

```
MediaDler.xcodeproj (或 .xcworkspace)
├─ MediaDlerCore/                 // 純 Swift Package(無 UIKit/Photos 相依,可 XCTest)
│   Sources/MediaDlerCore/
│     Model/      MediaItem, MediaFormat, DownloadTask, DownloadStatus,
│                 DownloadRequest, FormatSelection, AppSettings(+enum)
│     Extract/    UrlExtractor, YtDlpInfoParser   // ← 有單元測試(對齊 Android :core)
│     Download/   FormatSelector, SelectionPlanner // ← 有單元測試
│   Tests/MediaDlerCoreTests/     // XCTest, red/green
│
├─ MediaDler/ (App target, SwiftUI)
│     MediaDlerApp.swift          // @main,啟動時背景 init 引擎 + 更新 yt-dlp
│     Engine/    YtDlpEngine       // 包 YoutubeDL-iOS:extractInfo / download / 線上更新
│     Storage/   PhotosStorage(影片/圖片)、DocumentsStorage(音訊→Files)
│     Settings/  SettingsStore     // UserDefaults / @AppStorage
│     History/   HistoryStore      // JSON 檔(對齊 Android「不用 DB」)
│     Download/  DownloadQueue     // actor / async 串行 worker
│     UI/        Home / Picker / Settings / Common(SwiftUI views + ViewModel)
│     DeepLink/  處理 mediadler:// 與 Share Extension 傳入的 URL
│
└─ ShareExtension/ (App Extension target)
      ShareViewController          // 取出分享的 URL → 立刻 deep-link 回主 app(見下)
```

⚠️ **把容易出錯的純邏輯(URL 抽取、格式字串、預設選擇、JSON 解析)放進 `MediaDlerCore`,用 XCTest 做 red/green**。引擎、Photos、Files、Share Extension 等無法純單測的整合碼留在 App 層,交給 `xcodebuild` 編譯 + 實機驗證把關。

## 引擎整合契約(YoutubeDL-iOS 實測 API)

> 來源:`kewlbear/YoutubeDL-iOS` 的 `YoutubeDL` 類別(撰寫時 API)。⚠️ 版本尚淺(SPM `from: "0.0.2"`),簽名可能變動,鎖定版本並以實際標頭為準。

- 安裝:Swift Package Manager 加 `https://github.com/kewlbear/YoutubeDL-iOS.git`。它會再拉 `FFmpeg-iOS` 與 python-apple-support 等相依(體積大,首次 resolve 慢)。
- 建立:`YoutubeDL()`(初始化會啟動 post-download 任務)。⚠️ 載入 Python runtime 很重,**放背景**,並以一個 `YtDlpEngine` actor 確保只成功初始化一次、失敗可重試(對齊 Android 的 `EngineInitializer`)。
- **線上更新(必要,不是可選)**:`static func downloadPythonModule(from:) async throws` 會抓 yt-dlp 最新 python 模組;`var version: String?` 取版本。⚠️ 與 Android 同理:打包的 yt-dlp 很快過期(YouTube 常改版)。實作 **啟動時背景更新一次 + 設定頁手動更新按鈕 + 解析失敗時自動更新再重試一次**(self-heal)。
- 解析:`open func extractInfo(url:) async throws -> ([Format], Info)`。⚠️ **多圖/輪播(`entries`)**:若 `Info` 模型沒攤平 `entries`,需要自己用 yt-dlp `-J` 的 JSON(經由 Python 物件或自帶解析)補處理,對齊 Android 的 `YtDlpInfoParser`(把每個 entry 轉成一個 `MediaItem`,丟掉沒有可下載 format 的空殼)。
- 下載:`open func download(url:options:formatSelector:) async throws -> URL`。
  - `options: Options`(OptionSet)預設 `[.background, .chunked]`,另有 `.noRemux`、`.noTranscode`。⚠️ **背景下載**是 iOS 內建支援(URLSession background),沿用即可。
  - `formatSelector: ((Info) async -> ([Format], URL?, TimeRange?, Double?, String))?` — **回傳的 `String` 就是 yt-dlp format 字串**。把 Android `FormatSelector` 的字串組裝邏輯搬到這裡(見「格式選擇」)。
  - 回傳值是下載完成的檔案 URL(落在 app 容器),交給 storage 分流到 Photos / Documents。
- 轉檔進度:`var willTranscode: (() -> ((Double) -> Void)?)?`(0.0–1.0)。下載/解析進度精度有限,UI 以「解析中 / 下載中 / 轉檔中 / 完成」狀態為主。
- 檔案落點:`var downloadsDirectory: URL`(預設 app support 目錄)。⚠️ 這只是**中繼**;最終要依類型搬進 Photos 或 Documents。
- ⚠️ **平台支援度 = yt-dlp 有沒有 extractor**:與 Android 同。例如 **Threads 無官方 extractor**,generic 會抓到 og:title/og:image 之類垃圾。對策見「Threads 特例」。

## 分享入口設計(Share Extension + URL Scheme)

⚠️ **核心限制:Share Extension 不能跑 yt-dlp。** App Extension 有嚴格記憶體上限(約數十~120MB),而載入 Python runtime + 解析 + 下載遠超過,會被系統 jetsam 殺掉。**記入計劃:extension 內絕不初始化 YoutubeDL,只做「擷取 URL → 喚起主 app」。**

⚠️ **個人 Apple ID(免費)自簽通常拿不到 App Groups entitlement**,所以**不要用 App Group 共享容器**來傳遞 URL。改用 **URL Scheme deep-link**:

- Share Extension(`ShareViewController`):從 `extensionContext` 的 `NSItemProvider` 取出 URL / 純文字 → 用 regex 抽出第一個 http(s)(共用 `MediaDlerCore.UrlExtractor`)→ 組成 `mediadler://download?url=<percent-encoded>` → 透過 responder chain 找到 `UIApplication` 呼叫 `open(_:)` 開啟主 app → `completeRequest`。
  - ⚠️ Extension 不能直接用 `UIApplication.shared`;用沿 responder chain 往上找 `open(_:options:completionHandler:)` 的既知手法(或 `openURL:` selector)。這是免 App Group 傳遞 URL 的關鍵。
- 主 App:在 `Info.plist` 註冊 `CFBundleURLTypes`(scheme `mediadler`);用 SwiftUI `.onOpenURL { }` 接住,解碼 URL → 進入解析/下載流程(與「貼上連結」同一條路徑)。
- 「貼上連結」:首頁按鈕讀 `UIPasteboard.general.string` → 同一條路徑。

⚠️ **免費個人團隊**:provisioning 7 天到期需重簽;免費帳號每個團隊 **最多 3 個 App ID**,主 app + Share Extension 會用掉 2 個。心裡有數即可。

## 儲存設計(依類型分流)

- `PhotosStorage`(影片 / 圖片):用 `PHPhotoLibrary.shared().performChanges`(`PHAssetCreationRequest.forAsset().addResource(with:fileURL:options:)`),type `.video` / `.photo`。需 `NSPhotoLibraryAddUsageDescription`;只需「新增」權限(`addOnly`),不需讀取整個相簿。
  - ⚠️ 完成後可把中繼檔刪掉;Photos 會自有副本。
- `DocumentsStorage`(音訊 mp3 / m4a):搬到 `FileManager` 的 Documents 目錄下 `media-dler/`。在 `Info.plist` 開 `UIFileSharingEnabled = YES` + `LSSupportsOpeningDocumentsInPlace = YES`,使用者就能在 **Files app → 我的 iPhone → media-dler** 看到並分享/匯出。
  - ⚠️ 同名檔不要先刪再建;自動加序號去重(對齊 Android SAF 的教訓)。
- 由 `AppSettings` 與媒體類型決定走哪個 storage;UI 完成後提供「用系統分享匯出」(`UIActivityViewController`)當通用出口。

## 格式選擇(對齊 Android,輸出給 formatSelector 的字串)

`MediaDlerCore.FormatSelector` 產生 yt-dlp `-f` 字串(由 `download(...formatSelector:)` 回傳):
- 最佳:`bv*+ba/b`。
- **限制畫質**:`bv*[height<=H]+ba/b[height<=H]/b`,並讓 selector 額外帶 `-S res:H` 的等效設定。
  - ⚠️ 只以 `…/b` 收尾(無上限 fallback)時,沒有 ≤H 串流會默默下載到 4K;`-S res:H` 取「最接近上限」。
  - ⚠️ Bilibili 是 DASH(無 muxed `b`),fallback 要保留 `…/bv*+ba/b`(對齊 Android 踩坑 #3)。
- 音訊:轉 mp3/m4a → 選 `ba/b`,並用引擎的轉檔路徑(FFmpeg-iOS);留意 `Options.noTranscode` 不可開。
- 圖片:不指定 `-f`,讓 yt-dlp 抓原圖。
- **多圖貼文逐項勾選**:用原貼文 URL + `--playlist-items <1-based index>`;單一影片才 `--no-playlist`(互斥)。

**這些字串組裝與「輸出檔挑選」(依需求類型挑副檔名,排除 `.part`/`.ytdl`/`.tmp`,音訊轉檔時別誤挑較大的來源影片)是純函式 → 放 `MediaDlerCore` 寫 XCTest。**

## 解析 / URL 正確作法(沿用 Android 的踩坑)

- `UrlExtractor`:regex 抓第一個 http(s);去尾端標點時**括號做平衡判斷**(`/Foo_(bar)` 結尾的 `)` 是 URL 一部分),但句尾 `.,;:!?` 去掉。**Share Extension 與貼上連結共用此函式**。
- `YtDlpInfoParser`:從 `url` 推副檔名**只看 path**(先去 `?`、`#`);`entries` 可能含 `null` 或巢狀 playlist → `compactMap` 並丟掉無可下載 format 的項目。

## Threads 特例(可選,後續)

Android 自寫 `ThreadsExtractor`:用瀏覽器 UA 抓 `…/embed`、regex 取 cdninstagram 直連 `.mp4`/圖片。iOS 可用 `URLSession` + 正規表達式照搬(純圖/多圖輪播仍需登入,屬已知限制)。**列為 v0.2 後續**,v0.1 先靠 yt-dlp 本身,抓不到就回友善錯誤。

## 散布與簽章限制(務必先讀)

- ⚠️ **NOT AppStore-safe**:不上架。個人 Apple ID 自簽裝自用裝置。
- ⚠️ **免費團隊無 App Groups** → 分享入口用 URL Scheme(見上),不依賴共享容器。
- ⚠️ **provisioning 7 天到期**:需定期用 Xcode 重簽重裝(自用可接受)。
- ⚠️ **最低 iOS 版本**:暫定 **iOS 16+**(SwiftUI 成熟 + 與 YoutubeDL-iOS / python-apple-support 相容);**以套件實際 deployment target 為準**,resolve 後確認再鎖定。
- 體積大宗是 Python runtime + FFmpeg,屬無法避免;iOS 無 ABI split 概念,單一 app bundle。

## CI(GitHub Actions,macOS runner)

- 對齊 Android「先跑純邏輯測試當閘門」:
  - `build.yml`:在 `macos-latest` 上 `xcodebuild test -scheme MediaDlerCore -destination 'platform=iOS Simulator,name=iPhone 15'`(或 `swift test` 直接測 Core package)當 red/green 閘門 → 再 `xcodebuild build -scheme MediaDler -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` 確認可編譯。
- ⚠️ **CI 不做簽章/發佈**:iOS sideload 需要使用者自己的憑證,實機安裝走 Xcode 手動。(與 Android 用 CI 簽 APK 發 Releases 的模式不同。)

## 待踩坑預判(iOS 特有,照此可少走彎路)

1. **Python runtime 啟動慢 / 首次卡頓** — 背景初始化 + 狀態列顯示「引擎準備中」,別在主執行緒同步 init。
2. **Share Extension 被系統殺(OOM)** — 永遠不在 extension 內跑 yt-dlp;只擷取 URL 後 deep-link 回主 app。
3. **免費簽章無 App Groups** — 用 URL Scheme 傳遞,不要設計成共享容器。
4. **音訊存不進 Photos** — 依類型分流到 Documents/Files;別硬塞 Photos。
5. **yt-dlp 過期抓不動** — 啟動背景更新 + 手動更新 + 失敗自動更新重試(沿用 Android self-heal)。
6. **背景下載被暫停** — 用引擎的 `.background` option(URLSession background);回前景續傳。
7. **SPM 相依體積大、resolve 慢** — 鎖定版本,首次 CI 加快取。
8. **錯誤要夠詳細** — 解析/下載失敗訊息帶來源 URL、HTTP 狀態等;錯誤視圖可捲動 + 可複製(沿用 Android)。

## 實作步驟

1. **骨架**:建 Xcode 專案(App + ShareExtension + `MediaDlerCore` SPM local package);min iOS 16(待確認)。先在 `MediaDlerCore` 寫測試再寫實作(red/green):`UrlExtractor`、`FormatSelector`、`SelectionPlanner`、`YtDlpInfoParser`。
2. **引擎**:加 `YoutubeDL-iOS` 相依,寫 `YtDlpEngine`(actor):init、`extractInfo`、`download(formatSelector:)`、線上更新 + self-heal。
3. **儲存**:`PhotosStorage`(影片/圖片)、`DocumentsStorage`(音訊→Files);Info.plist 開 `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` + 權限字串。
4. **設定**:`@AppStorage` 存 `AppSettings`(shareMode、defaultMediaKind、defaultVideoQuality、audioFormat、downloadAllWhenMultiple)。
5. **分享入口**:Share Extension 擷取 URL → `mediadler://` deep-link;主 app `.onOpenURL` + 「貼上連結」共用解析路徑。
6. **下載佇列**:`DownloadQueue`(actor,串行 worker),每筆任務狀態 `StateFlow` 等價(`@Published` / `AsyncStream`)。
7. **UI**:Home(進行中 + 歷史,可重試/刪除/開啟/分享)、Picker(縮圖 + 每項格式選單 + 勾選)、Settings。
8. **歷史**:`HistoryStore`(JSON 檔,只在終態寫入)。

## 驗證方式(end-to-end)

0. ⚠️ `swift test`(或 `xcodebuild test -scheme MediaDlerCore`)綠燈:URL 抽取 / 格式字串 / 預設選擇 / JSON 解析。
1. `xcodebuild build`(simulator,免簽)成功;再用 Xcode 簽章裝到實機。
2. 首次啟動完成 yt-dlp/FFmpeg init + 背景更新(看 log 無錯)。
3. 從 Safari / YouTube app「分享 → media-dler」:Extension 喚起主 app,
   - 彈窗模式:出現格式選單,選 720p 下載 → 影片進 **Photos 相簿**,可播放。
   - 一鍵模式:再分享一次,直接下載完成,首頁顯示紀錄。
4. 複製連結 → 首頁「貼上連結」→ 同樣可解析下載。
5. 音訊:選 MP3 → 檔案出現在 **Files app → media-dler**,可播放。
6. 多圖貼文 → 列出多個 media 可逐項勾選下載。
7. 非法/不支援 URL → 友善錯誤,不崩潰。

## 與 Android 版的對照(差異摘要)

| 面向 | Android(`media-dler`) | iOS(本計劃) |
| --- | --- | --- |
| 引擎 | youtubedl-android(yt-dlp) | YoutubeDL-iOS(yt-dlp via PythonKit)+ FFmpeg-iOS |
| UI | Kotlin + Compose | Swift + SwiftUI |
| 純邏輯模組 | `:core`(JVM,JUnit) | `MediaDlerCore`(SPM,XCTest) |
| 分享入口 | `ShareReceiverActivity`(ACTION_SEND) | Share Extension → URL Scheme deep-link + 貼上連結 |
| 儲存 | MediaStore Downloads / SAF | 影片/圖片→Photos;音訊→Documents/Files |
| 線上更新 | `updateYoutubeDL` | `downloadPythonModule` |
| 背景下載 | Foreground Service + 通知 | URLSession background(引擎 `.background`) |
| 散布 | CI 簽 APK 發 Releases(各 ABI) | 個人自簽,Xcode 手動裝機(CI 只測+編譯) |
| 進度 | 行解析,狀態為主 | 同,狀態為主 + 轉檔進度 |
