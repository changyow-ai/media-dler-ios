# video2text — 模型速查表（iOS 版用）

> 給 iOS app（`media-dler-ios`）的**單一真相**模型參考。整併自 Android `media-dler` 的真機驗證
> （CPH1941 / SD665 / 3.7GB RAM，同一段 **184s 中文片**，2026-06-05）與 OpenRouter `$1` key 實測。
> 完整背景見 [`video2text-ios-plan.md`](./video2text-ios-plan.md)、[`video2text-plan.md`](./video2text-plan.md)（Android）。
>
> **一句話結論**：要準/快 → **雲端 OpenRouter `whisper-large-v3-turbo`**（最便宜、最穩）；
> 要離線/隱私 → **裝置端 sherpa `SenseVoice-Small`**（中文遠勝 whisper、有標點、快於即時）。
> whisper.cpp `base`/`small` 是相容性保底，中文偏弱。

---

## 1. 兩種引擎、三類後端

| 引擎 | 後端 | 模型 | 場景 |
|---|---|---|---|
| **裝置端** `onDevice` | whisper.cpp (ggml) | base / small / large-v3-turbo-q5 | 離線、隱私、免金鑰；中文弱 |
| **裝置端** `onDevice` | sherpa-onnx (ONNX RT) | SenseVoice / Paraformer / Qwen3 | 離線且中文要準（**SenseVoice 主推**） |
| **雲端** `cloud` | OpenRouter (HTTP) | whisper-large-v3-turbo / qwen3-asr-flash | 準度/速度全面最佳，需使用者自備 key |

> **UI 不暴露「後端」概念**：`TranscribeEngine{onDevice,cloud}` 不變；`TranscribeModel` 加 `backend`
> 屬性（`whisperCpp` / `sherpa`），on-device 下拉統一列所有模型，後端由所選模型推導。
> enum 新值對既有偏好向後相容（缺欄 fallback 預設，不 wipe）。

---

## 2. 裝置端 — whisper.cpp（ggml）

模型不進 IPA，首次使用下載 + Wi-Fi gate。下載 base URL：
`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<檔名>`

| 模型 (`TranscribeModel`) | 檔名 | 大小 | 標點 | 速度（SD665，184s 片） | 中文相對 CER | 備註 |
|---|---|---|---|---|---|---|
| `base`（**現預設**） | `ggml-base.bin` | ~142MB | 有 | 141s（**0.77× 快於即時**） | ~30% | 多語、快；中文最弱 |
| `small` | `ggml-small.bin` | ~466MB | 有 | 358s（1.95× 慢於即時） | ~26% | 略優於 base 但慢、會漏字 |
| `turboQ5`（Android M8 新增） | `ggml-large-v3-turbo-q5_0.bin` | **574MB** | 有 | ~3.7× 即時（很慢） | 接近雲端 turbo | 準（小誤），但裝置端很慢；體積同 small 級、**零架構改動** |

- 同一份 whisper.cpp / 同一份 ggml 模型與 Android 共用；iOS 走 `whisper.swiftui` 範例的
  `WhisperContext` Swift/ObjC 橋 + vendored `whisper.xcframework`（`make whisper` 產出，不入 git）。
- 進度/即時文字/中止：whisper 的 `progress_callback` / `new_segment_callback` / `abort_callback`
  橋接出來（不縮窗、不犧牲準確度）。

## 3. 裝置端 — sherpa-onnx（ONNX Runtime）｜Android 已驗，iOS 列選配 M7

- 下載：`https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/<name>.tar.bz2`
  → **端上解壓**（tar.bz2，非逐檔；SenseVoice 標點版與 Qwen3 在 HF 無個別檔鏡像）。
- 音訊 **16kHz mono float 與 sherpa 完全相容、免轉換**（同 `AudioToPCM` 輸出）。
- iOS 整合：官方 prebuilt **`sherpa-onnx.xcframework` + `onnxruntime.xcframework`** + vendored `swift-api`；
  `OfflineRecognizer` API（`createStream` → `acceptWaveform(float,16000)` → `decode` → `getResult().text/.lang`）。
  （Android 用 vendored `.kt` + jniLibs `.so` v1.13.2，因 Android 無官方 maven；iOS 有官方 xcframework，較省事。）

| 模型 (`name`) | tar.bz2 | 解壓後 | 標點 | 語言 | 真機結果（SD665 184s 片） |
|---|---|---|---|---|---|
| **SenseVoice-Small**（**建議**）`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17` | 163MB | ~228MB | **有** | zh/yue/en/ja/ko | ✅ **快於即時**、正體、內容準、`language=zh` 自動回填；非自回歸、比 whisper-large 快 ~15× |
| **Paraformer-zh** `sherpa-onnx-paraformer-zh-int8-2025-10-07` | 228MB | ~227MB | **無** | 純中文 | ✅ ~3× 即時、準（CER ~1.95%）；CTC 無標點 → 靠軟斷可讀；引擎固定回 `zh`，OpenCC 必套正體 |
| **Qwen3-ASR 0.6B**（**實驗／高階機**）`sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25` | **879MB** | ~600–900MB | 有 | 多語 | ❌ **OOM-killed**（decoder 756MB + 自回歸活化超出 3.7GB 機，第一窗前被系統殺）→ 中階機不可行，UI 標「實驗/高階機」 |

> Qwen3 解壓後檔名：`conv_frontend.onnx` + `encoder.int8.onnx` + `decoder.int8.onnx` + `tokenizer/`（merges/vocab/config）。

## 4. 雲端 — OpenRouter（JSON + base64）｜契約與 Android 完全相同

- **端點**：`POST https://openrouter.ai/api/v1/audio/transcriptions`
  · `Content-Type: application/json` · `Authorization: Bearer <key>` · base URL **須 https**（ATS）。
- **Body**：
  ```json
  {"model":"<id>","language":"zh","input_audio":{"format":"wav","data":"<raw base64，非 data URI>"}}
  ```
  `language` 可省（省則自動偵測）；`format` 支援 `wav`/`m4a`/`mp3`/`flac`/`ogg`。
- **回應**：`{"text":"...","usage":{"seconds":183.86,"cost":0.00204}}`
  — **無 `language` 欄、無 segments/timestamps**（不支援 `verbose_json`）。
- **計費**：按**音訊時長（秒）**，與 bytes/格式無關 → 壓縮省頻寬**不省錢**；用 `usage.cost` 對帳。
- **限制**：上游 **~60s timeout** → 長音訊務必分窗（本專案 **WAV 5min / m4a 10min**）。

| model id | WAV | m4a | 價格/hr | 結果 |
|---|---|---|---|---|
| ✅ `openai/whisper-large-v3-turbo`（**推薦預設**） | ✓ | ✓ | **$0.04** | 最便宜最穩；壓縮 vs WAV CER 僅 ~1.5% |
| ❌ `openai/whisper-large-v3` | ✗ | ✗ | $0.09 | 反覆 `Provider returned 400`，provider 壞、不可用 |
| ⚠️ `qwen/qwen3-asr-flash-2026-02-10` | ✓ | **✗（400）** | **$0.126** | 最貴；同音字較準、自動加標點；**只收 WAV**。基本 id 不帶日期不存在 |

> 選 model + 壓縮模式要避開壞組合：**turbo 最穩**；qwen **必須關壓縮（WAV）**。

---

## 5. 實測基準總表（184s 中文片，CPH1941 / SD665）

| 引擎·模型 | 速度 | 即時倍率 | 成本/次 | 相對 CER\* | 標點 |
|---|---|---|---|---|---|
| 裝置端 whisper base | 141s | 0.77× | $0 | ~30% | 有 |
| 裝置端 whisper small | 358s | 1.95× | $0 | ~26% | 有 |
| 裝置端 whisper turbo-q5 | ~3.7× 即時 | 很慢 | $0 | ≈雲端 turbo | 有 |
| 裝置端 sherpa SenseVoice | 快於即時 | <1× | $0 | 遠勝 whisper | 有 |
| 裝置端 sherpa Paraformer | ~3× 即時 | — | $0 | CER ~1.95% | 無 |
| 裝置端 sherpa Qwen3 | OOM | — | $0 | — | — |
| 雲端 turbo | ~35s | 0.19× | $0.00204 | **0（基準）** | 有 |
| 雲端 qwen | ~35s | 0.19× | $0.00644 | ~2% | 有 |

\*相對 CER 以雲端 turbo 當參考（無 ground truth，無法算絕對 WER）。
結論：**雲端準度/速度全面勝**；on-device 把難詞（「錘子」聽成「垂澀」）聽錯，**只適合離線/隱私**。
裝置端要中文準度 → **sherpa SenseVoice** 是離線最佳解。

---

## 6. iOS 實作必讀的 model 相關 caveat

1. **正體轉換**：OpenCC 用 **SwiftyOpenCC（`s2twp`）**，片語在地化優於 Android 目前的 opencc4j 字元級 s2t。
2. **OpenRouter AUTO 中文停在簡體**：OpenRouter **不回 language**，AUTO 時不套 OpenCC → 中文停簡體。
   解法：把「轉錄語言」設 **中文** → `knownLanguage=zh` → OpenCC 轉正體。（Paraformer 固定回 `zh` 已自動規避。）
3. **語言誤判**：whisper 在第一窗偵測語言，片頭是音樂/無人聲會誤判整段（測試片頭被判 `ko`）。
   非「自動」時把該語言碼當 `knownLanguage` 鎖住 whisper `language`，跳過自動偵測。
4. **金鑰存 Keychain**（非 UserDefaults 明文）；原始碼/IPA **不內建任何 key**，使用者自貼。
5. **Qwen3 在低記憶體機被系統殺**（Android 已驗）→ iOS 同列實驗/高階機。
6. **雲端逐窗上傳無行動數據 gate**（模型下載有 Wi-Fi 詢問）；雲端走 background `URLSession` 更耐背景。
7. **`TranscribeModel` enum 對應**（`MediaDlerCore/Settings.swift`）：
   ```swift
   // 現有：case base, small
   // M1 可加：case turboQ5
   // M7（sherpa）可加：case senseVoice, paraformer, qwen3
   // 各 case 帶 backend（.whisperCpp / .sherpa），UI 統一列、後端推導
   ```

---

## 7. 模型下載 URL 速查

| 模型 | URL |
|---|---|
| whisper base/small/turbo-q5 | `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{ggml-base.bin\|ggml-small.bin\|ggml-large-v3-turbo-q5_0.bin}` |
| sherpa SenseVoice | `…/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2` |
| sherpa Paraformer | `…/releases/download/asr-models/sherpa-onnx-paraformer-zh-int8-2025-10-07.tar.bz2` |
| sherpa Qwen3 | `…/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2` |

（sherpa releases base：`https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/`）
