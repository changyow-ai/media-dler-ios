# media-dler (iOS)

iOS 版的 **media-dler** — 從其他 App「分享」或貼上一個連結，就解析並下載當中的影片 / 音訊。以 [yt-dlp](https://github.com/yt-dlp/yt-dlp) 為引擎，透過 [YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS)（PythonKit + FFmpeg-iOS）執行。

由 [Android 版 media-dler](https://github.com/changyow-ai/media-dler) 改寫；完整設計與 iOS 平台限制見 [`plan/media-dler-ios-plan.md`](plan/media-dler-ios-plan.md)。

> **散布**：不上 App Store（YoutubeDL-iOS 作者明言 NOT AppStore-safe）。以**個人 Apple ID 自簽**裝到自用裝置。

---

## 功能（v0.1）

- **分享即下載**：Share Extension 接住連結，透過 `mediadler://` 喚起主 App（yt-dlp 太重，**不在 extension 內執行**）。
- **貼上連結**：首頁讀剪貼簿或手動輸入網址。
- **兩種模式**：一鍵（用預設值直接下載）/ 彈窗（選畫質或音訊）。
- **格式選擇**：最佳畫質、限制解析度（1080/720/480/360p）、音訊轉 MP3 / M4A。
- **儲存（依類型分流）**：影片 / 圖片 → **照片 App**（由函式庫匯出）；音訊 → **檔案 App** 的 `media-dler` 資料夾。
- **下載清單**：進行中與歷史，可重試 / 刪除。
- **引擎線上更新**：啟動時背景更新 yt-dlp，解析失敗時自動更新重試，設定頁也可手動更新。

- **Threads（Meta）**：yt-dlp 無 extractor，故自行抓 `/embed` 頁、解析直連 cdninstagram 媒體，**影片與圖片都直接存入照片庫**（`ThreadsService` + `DirectMediaSaver`，純解析邏輯在 `MediaDlerCore` 有單元測試）。純圖多圖輪播仍受限（需登入，多半只拿得到首圖）。

### 已知限制 / 後續
- **一般站的多圖輪播逐項勾選** 與 **單張圖片下載**：受函式庫 typed `Info`（無 `entries`）與其 Photos-video 匯出限制，列為後續；yt-dlp 路徑 v0.1 以單一影片 / 音訊為主。
- **音訊→檔案** 路徑依賴函式庫的轉檔輸出，標記為實驗性。

---

## 架構

```
MediaDlerCore/      純 Swift Package（無 UIKit/Photos 相依）— 領域模型、URL 抽取、
                    yt-dlp JSON 解析、格式挑選（FormatPicker）、預設選擇。XCTest 覆蓋。
MediaDler/          SwiftUI App — YtDlpEngine、儲存、設定、下載佇列、UI、deep-link。
ShareExtension/     Share Extension — 只擷取 URL 後 deep-link 回主 App。
project.yml         XcodeGen 專案定義。
```

`MediaDlerCore` 對齊 Android 的 `:core`：把容易出錯的純邏輯抽出來單元測試。iOS 與 Android 的差異在於**格式選擇是 client-side**（挑 `Format` 物件而非 yt-dlp `-f` 字串），故新增 `FormatPicker`。

---

## 開發

需求：**macOS + Xcode**（編譯 App）；[XcodeGen](https://github.com/yonaskolb/XcodeGen) 產生專案。

> ⚠️ **repo 內沒有 `.xcodeproj`，這是正常的。** 它是 XcodeGen 依 `project.yml` 產生的衍生檔，已列入 `.gitignore`（避免 `project.pbxproj` 的 merge conflict）。**Xcode 不會因為你打開資料夾就自動生成它**——第一次取得原始碼後，必須先執行一次 `xcodegen generate`。專案設定的唯一來源是 `project.yml`；之後改了它、或新增／刪除原始檔，都要重跑 `xcodegen generate` 讓專案檔同步。

最快的方式是用根目錄的 `Makefile`：

```bash
make open       # xcodegen generate 之後用 Xcode 開啟（需 macOS + Xcode）
make test-core  # 跑核心純邏輯單元測試（不需 Xcode；Linux 亦可）
make help       # 列出所有指令
```

或手動執行：

```bash
# 0) 安裝 XcodeGen（只需一次）
brew install xcodegen

# 1) 純邏輯單元測試（最快的回饋，不需 Xcode 模擬器；亦可在 Linux Swift toolchain 跑）
cd MediaDlerCore && swift test

# 2) 產生 Xcode 專案（讀 project.yml → 產生 MediaDler.xcodeproj）
xcodegen generate

# 3) 開啟並執行
open MediaDler.xcodeproj
#   在 Signing & Capabilities 選你的個人 Team（主 App 與 Share Extension 各一個 bundle id），
#   選實機，Run。首次啟動會背景下載 yt-dlp python 模組。
```

> 個人免費團隊：provisioning 7 天到期需重簽；免費帳號最多 3 個 App ID（主 App + Share Extension 用掉 2 個）；通常拿不到 App Groups（故本專案以 URL scheme 而非共享容器傳遞連結）。

---

## CI

`.github/workflows/ci.yml`（macOS runner）：

1. `core-tests` — 在 `MediaDlerCore` 跑 `swift test`（red/green 閘門）。
2. `app-build` — `xcodegen generate` → `xcodebuild build`（iOS Simulator、未簽章）驗證可編譯。

CI 不做簽章 / 發佈：iOS sideload 需使用者自己的憑證，實機安裝走 Xcode 手動。

---

## 注意與限制

- 平台支援度取決於 yt-dlp；下載失敗先更新引擎（App 會自動嘗試）。
- 進度以函式庫的 `Progress` 呈現，百分比為盡力呈現。
- 請尊重各平台服務條款與著作權，僅下載你有權保存的內容。

## 致謝

[yt-dlp](https://github.com/yt-dlp/yt-dlp)、[YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS)、[FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)。
