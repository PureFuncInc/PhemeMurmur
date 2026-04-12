# PhemeMurmur Swift MVP

## Context

建立一個 macOS menu bar app（Swift），按右 Shift 開始/停止錄音，錄音透過 OpenAI gpt-4o-transcribe 轉文字後自動貼到當前輸入焦點。

## 專案結構

使用 Swift Package Manager + Makefile 包裝 .app bundle（不需要 Xcode）。

```
PhemeMurmur/
  Package.swift
  Makefile
  Sources/PhemeMurmur/
    main.swift              # NSApplication 啟動、menu bar 設定、狀態機
    HotkeyManager.swift     # CGEvent tap 偵測右 Shift
    AudioRecorder.swift     # AVAudioEngine 錄音 + 寫 WAV
    TranscriptionService.swift  # URLSession multipart POST 到 OpenAI
    PasteService.swift      # 剪貼簿 + 模擬 Cmd+V
    Config.swift            # API key 讀取、常數
  Resources/
    Info.plist              # LSUIElement, NSMicrophoneUsageDescription
```

## API Key

從 `~/.config/phememurmur/api_key` 讀取純文字 key。啟動時若找不到，在 menu bar 顯示錯誤提示。

## 實作步驟

### Step 1: 專案骨架

- 建立 `Package.swift`（executable target，依賴 AppKit、AVFoundation、CoreGraphics）
- 建立 `Resources/Info.plist`
  - `LSUIElement` = true（隱藏 Dock icon）
  - `NSMicrophoneUsageDescription` = 麥克風權限說明
- 建立 `Makefile`
  - `make build`: `swift build -c release`
  - `make app`: 將 binary 包成 `PhemeMurmur.app` bundle（含 Info.plist）
  - `make run`: build + open app
  - `make clean`
- 建立 `main.swift`: 最小 NSApplication + NSStatusItem，顯示 mic icon，有 Quit 選項

### Step 2: Config

`Config.swift`:
- 從 `~/.config/phememurmur/api_key` 讀取 API key（trim whitespace）
- 常數：`sampleRate = 16000`, `channels = 1`, `minDuration = 0.5`, `debounceInterval = 0.4`

### Step 3: 全域快捷鍵 — 右 Shift 偵測

`HotkeyManager.swift`:
- 使用 `CGEvent.tapCreate()` 監聽 `.flagsChanged` 事件
- Callback 中檢查 `keyCode == 0x3C`（右 Shift）且 flags 包含 `.maskShift`（key down）
- Debounce 400ms 防止重複觸發
- Callback 是 C function pointer，用 `Unmanaged<HotkeyManager>` 傳遞 self
- 加入 CFRunLoop source
- 若 `CGEvent.tapCreate()` 回傳 nil，代表沒有 Accessibility 權限：
  - 用 `AXIsProcessTrusted()` 檢查
  - 引導使用者開啟 System Settings > Privacy & Security > Accessibility

### Step 4: 錄音

`AudioRecorder.swift`:
- 使用 `AVAudioEngine`
- `startRecording()`:
  - 清除舊 buffer
  - 在 inputNode 安裝 tap，format: 16kHz mono Float32（AVAudioEngine 自動從硬體 48kHz 轉換）
  - 累積 `[AVAudioPCMBuffer]`
- `stopRecording() -> URL?`:
  - 移除 tap、停止 engine
  - 用 `AVAudioFile` 寫出 WAV（Linear PCM, 16kHz, mono, 16-bit）到 temp 目錄
  - 若錄音 < 0.5 秒則回傳 nil
- Buffer 存取用 lock 保護（audio callback 在不同 thread）

### Step 5: 語音轉文字

`TranscriptionService.swift`:
- `func transcribe(fileURL: URL) async throws -> String`
- 用 URLSession 發送 multipart/form-data POST 到 `https://api.openai.com/v1/audio/transcriptions`
  - Header: `Authorization: Bearer <api_key>`
  - Body: `model=gpt-4o-transcribe` + `file=<wav data>`
- 解析 JSON response 取 `text` 欄位

### Step 6: 貼上

`PasteService.swift`:
- `NSPasteboard.general` 設定文字
- 用 `CGEvent` 模擬 Cmd+V（virtualKey `0x09`）
- 貼上前加 50ms delay 確保剪貼簿就緒
- 需要 Accessibility 權限（同 Step 3）

### Step 7: 狀態機串接

在 `main.swift` 的 AppDelegate 中串接所有元件：

```
IDLE --[右Shift]--> RECORDING --[右Shift]--> TRANSCRIBING --[完成]--> PASTING --> IDLE
```

Menu bar icon 反映狀態：
- IDLE: `mic.slash`
- RECORDING: `mic.fill`（紅色）
- TRANSCRIBING: `ellipsis.circle`
- 錯誤: 顯示在 menu 中

### Step 8: .gitignore

加入 Swift/macOS 相關項目：`.build/`, `DerivedData/`, `.DS_Store`, `*.app`

## 權限需求

| 權限 | 用途 | 觸發方式 |
|------|------|---------|
| Microphone | 錄音 | Info.plist + 系統自動彈窗 |
| Accessibility | 全域快捷鍵 + 模擬按鍵 | `AXIsProcessTrusted()` 檢查，引導使用者手動開啟 |

## 外部依賴

**零依賴**，全部使用 Apple 框架：AppKit、AVFoundation、CoreGraphics、ApplicationServices、Foundation

## 驗證方式

1. `make app && make run` 能成功啟動，menu bar 出現 mic icon
2. 點 Quit 能正常關閉
3. 按右 Shift 開始錄音（icon 變紅），再按一次停止
4. 確認 `/tmp` 下有產出 .wav 檔且可播放
5. 確認 API 呼叫成功，transcript 出現在剪貼簿
6. 確認文字自動貼到當前輸入焦點（如 Notes、TextEdit）
