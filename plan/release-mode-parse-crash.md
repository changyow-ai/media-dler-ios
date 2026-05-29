# Release 模式解析崩潰 — 調查與修復存檔

> 日期：2026-05-29 ／ 分支：main ／ 調查者：codex（初判）+ Claude（驗證）
>
> 摘要：App 在 **Release（最佳化）** 模式下，一進到解析就崩潰，UI 表現為「卡在解析」。
> 根因是 Swift `-O` 對 PythonKit 的誤編譯；修復是把 **Release 的 app target 降回 `-Onone`**。
> 已在 x86_64 模擬器上以對照實驗 100% 重現並驗證修復。

---

## 1. 症狀（codex 最初回報）

- Debug build 一切正常；**Release build 一貼連結就「卡在解析」**。
- 使用者觀感是 hang，但實際是 **app 在解析早期就崩潰**（程序消失 → UI 停在 extracting 狀態）。

## 2. 重現方式（本次採用）

因為 headless CLI 無法存取 Xcode GUI 的簽章帳號（見 §6 限制），改用**模擬器對照實驗**，
唯一變數是 **app target 的 Swift 最佳化等級**，其餘 source / URL 完全相同。

觸發解析不需點 UI：deep-link `mediadler://...?url=` 在這種 headless 啟動下不會觸發 `onOpenURL`，
故改用啟動環境變數 + `--console-pty` 串 stdout（`MDLog` 用 `print` 輸出）：

```bash
SIM=<iPhone 模擬器 udid>
# 用環境變數餵 URL（需在 MediaDlerApp 暫時加一個讀 MDLER_TEST_URL 的測試 hook；驗證後已移除）
SIMCTL_CHILD_MDLER_TEST_URL="https://www.w3schools.com/html/mov_bbb.mp4" \
  xcrun simctl launch --console-pty $SIM com.changyow.mediadler >> run.log 2>&1
```

測試 URL 選擇：要能**真的取得 formats**（走完 `PythonDecoder` 解碼路徑）才有代表性。
- YouTube 測試影片在 iOS 上會因「無 JS runtime（deno）」+ 影片失效而走錯誤路徑，不適合。
- Google / 多數 CDN 會對 yt-dlp 的 UA 回 403。
- ✅ `https://www.w3schools.com/html/mov_bbb.mp4`：generic extractor，回 200，穩定產生 1 個 format。

兩種 build：
```bash
# A) 現況 workaround（app target = -Onone）
xcodebuild ... -configuration Release CODE_SIGNING_ALLOWED=NO build
# B) 沒 workaround 的正常 Release（app target 也 -O；套件本來就 -O）
xcodebuild ... -configuration Release CODE_SIGNING_ALLOWED=NO \
  SWIFT_OPTIMIZATION_LEVEL=-Owholemodule SWIFT_COMPILATION_MODE=wholemodule build
```

## 3. 結果（決定性）

| Build（app target 最佳化） | 同一個 mp4 URL | 結果 |
|---|---|---|
| `-Onone`（= 現況 workaround） | `▶︎ extractInfo #1 begin → ✓ end → mapped 1 formats` | ✅ 正常，~7s |
| `-O -wholemodule`（= 無 workaround 的 Release） | `▶︎ extractInfo #1 begin → ✗`（程序消失） | ❌ **SIGSEGV 崩潰，2/2 次** |

崩潰報告（`~/Library/Logs/DiagnosticReports/MediaDler-2026-05-29-110040.ips`、`-110215.ips`）：

```
EXC_BAD_ACCESS (SIGSEGV) — KERN_INVALID_ADDRESS at 0x0   ← null pointer deref
faulting thread:
  YoutubeDL.loadPythonModule(downloadPythonModule:)
  specialized YoutubeDL.makePythonObject(_:initializePython:)
  YoutubeDL.extractInfo(url:)
  YtDlpEngine.extract(_:)
  AppModel.extract(_:)
```

→ 崩在 `extractInfo` 內**初始化 Python 直譯器 / 載入 yt-dlp 模組**（`makePythonObject` → `loadPythonModule`）。

## 4. 根因

PythonKit 的 CPython C-API glue 大量是 `@inlinable`。當 **app target 以 `-O -wholemodule`** 編譯時，
跨模組最佳化（CMO）會把這些 inlinable 程式碼 inline / specialize 進最佳化過的 app target 並重新最佳化，
過程中誤處理了 `PythonObject`（`PyObject*`）的指標 / 生命週期，導致 null deref（`0x0`）。
`-Onone` 不做這種積極最佳化，故不崩。這是 PythonKit「Debug 正常、Release 爆掉」的典型案例。

## 5. 修復（已在 `project.yml`，本次確認有效且正確接上）

```yaml
settings:
  configs:
    Release:
      SWIFT_OPTIMIZATION_LEVEL: "-Onone"
      SWIFT_COMPILATION_MODE: singlefile
```

驗證重點：
- pbxproj 確認 **app target 的 Release 繼承到專案層級的 `-Onone`**（target 沒覆寫 opt level）。
- **反直覺事實**：`-Onone` 其實**沒傳到 SwiftPM 套件**。Build log 實證：
  `swiftc -module-name PythonSupport -O -whole-module-optimization …`
  亦即 PythonKit / YoutubeDL / MediaDlerCore 在 Release **永遠是 `-O`**（Xcode 不讓專案層級設定覆寫 package 的最佳化）。
- 即使如此，workaround 仍有效，因為**觸發點是 app target 自己的 `-O` CMO 在 inline PythonKit**。
  只要 **app target** 不最佳化就避開了 → 所以放「專案層級」就夠，不必、也無法靠改 package 解決。
- `SWIFT_COMPILATION_MODE: singlefile` 對修復而言**冗餘**（`-Onone` 已關掉 whole-module），但無害，可留。

## 6. 限制與待辦

- ⚠️ **arch 限制**：本機是 **Intel Mac**，模擬器跑 **x86_64**；實機 iPhone XS 是 **arm64**。
  崩潰在 x86_64 上 100% 重現（且原始回報本來就是 on-device arm64），強力佐證這是真實 optimizer 問題；
  但**尚未在 arm64 實機直接驗證**。要鐵證：Xcode 裡暫時移除 Release override、選 Release + 實機跑一次即崩。
- ⚠️ **簽章**：headless `xcodebuild -allowProvisioningUpdates` 取不到 Xcode GUI 的 Apple ID
  （`error: No Account for Team "3923UH7ZW6"`），故實機 build 只能在 Xcode GUI / 已登入帳號的環境做。
- 長期方向（非必要）：升級 / 隔離 YoutubeDL-iOS + PythonKit，待上游修掉 `-O` 問題後即可恢復 Release 最佳化、
  並移除這個 `-Onone` workaround 以拿回效能。屆時應重跑本文件 §2 的對照實驗確認。

## 7. 附帶產出（本次調查順帶留下的診斷設施）

- `MediaDler/Engine/YtDlpEngine.swift` 的 `MDLog`（含 `watch()` 心跳）：用 `print` 走 stdout，
  可被 `devicectl device process launch --console`（實機）或 `simctl launch --console-pty`（模擬器）即時擷取，
  逐行標出解析流程進到哪、卡 / 崩在哪。診斷完成後可移除（程式內已標 TODO）。
