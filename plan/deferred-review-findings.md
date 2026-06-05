# 待處理：code review 未修項（feat/video2text）

來源：`/code-review xhigh`（2026-06）。前兩個 commit（`7543ce3`、`aa4a8cc`）已修掉崩潰與其餘可立即處理的問題；以下四項刻意延後，下次再處理。沒有 `gh` CLI，暫以本檔追蹤，之後可轉成正式 GitHub issue。

---

## #10 模型下載 continuation 在背景化可能洩漏（永久卡住）

**嚴重度**：低（需特定背景化時序），但發生後是永久卡住、需重啟。

`WhisperModelManager` / `SherpaModelManager` 用 `.default` 設定的 `URLSession` 下載模型，並以單一 `CheckedContinuation` 等待。若 App 在下載中被背景化夠久、系統把 session 拆掉而沒送出 `didFinishDownloadingTo` 或 `didCompleteWithError`，continuation 永遠不會 resume：

- 等待中的 `ensureDownloaded` / 轉錄 pipeline 無限掛住
- `activeDownload` 一直為非 nil，之後所有下載都丟 `.busy`

位置：
- `MediaDler/Transcribe/WhisperModelManager.swift`（`ensureDownloaded` + `URLSessionDownloadDelegate`）
- `MediaDler/Transcribe/SherpaModelManager.swift`（同樣結構）

建議修法：改用 `URLSessionConfiguration.background`（含 app 重啟後 completion handler 接續），或在等待端加逾時並於失敗時清除 continuation / activeDownload。屬較大結構改動，獨立處理。

---

## #11 尾段 window 起點落在實際 EOF 之後會靜默漏音

**嚴重度**：低（非崩潰、條件邊界）。

`AudioToPCM.decodeRange` 對某個起點已超過實際可解碼長度的 window，會回傳空 PCM；引擎等於辨識了一段靜音，該 window 仍標記完成、進度推到 100%，但尾段內容遺失且不報錯。

觸發前提：`durationMs`（由 `CMTime` 四捨五入而來）比實際可解碼音訊略長，使最後一段 window 起點落在真實 EOF 之後。`WindowPlanner` 已保證 `start < total`，所以非崩潰、機率低。

位置：`MediaDler/Transcribe/AudioToPCM.swift`（`decodeRange` 的 `timeRange` 設定）

建議修法：以實際可解碼長度校正最後一段，或當某 window 解出 0 sample 時記錄 / 重新量測長度，而非靜默完成。

---

## #12 抽出 WhisperModelManager / SherpaModelManager 共用下載器（cleanup）

**嚴重度**：cleanup（非 bug，但避免修一漏一）。

兩個 model manager 幾乎逐字重複：三個 `URLSessionDownloadDelegate` 方法、`continuation` / `activeDownload` / `progress` / `session` 屬性、busy 守衛、暫存檔搬移流程。任何修正（例如 #10、progress race）都得改兩遍。

位置：
- `MediaDler/Transcribe/WhisperModelManager.swift`
- `MediaDler/Transcribe/SherpaModelManager.swift`

建議修法：抽出共用 `ModelDownloader`（base class 或 helper），輸入 remote URL + 暫存副檔名，輸出 async 下載 + progress publisher；唯一差異是 URL 來源與下載後步驟（move vs tar.bz2 解壓）。

---

## #13 TranscribeSource.link 為死碼（cleanup）

**嚴重度**：cleanup（非 bug）。

`AppModel.transcribeLink` 透過 `LocalMediaInput.adopt` 把下載好的音訊當成 `.localFile` job，因此 `TranscribeSource.link` 從未被建構，`TranscriptHistoryView.media(for:)` 的 `if case .link` 分支永遠不會執行。目前保留是為了未來「連結／YouTube 字幕捷徑」路徑。

位置：
- `MediaDler/Transcribe/TranscriptJob.swift`（`TranscribeSource.link`）
- `MediaDler/UI/Transcribe/TranscriptHistoryView.swift`（`media(for:)` 的 `.link` 分支）

處理選項（二擇一）：
1. 實作連結來源時真正使用 `.link`（保留意圖）。
2. 若短期不做，移除死碼以免誤導讀者。
