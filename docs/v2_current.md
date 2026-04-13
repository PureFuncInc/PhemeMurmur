# PhemeMurmur

macOS menu bar app，按右 Shift 錄音，透過 OpenAI gpt-4o-transcribe 轉文字後自動貼到當前輸入焦點與剪貼簿。

## 專案結構

```txt
PhemeMurmur/
├── Package.swift                    # SPM executable，macOS 13+，零外部依賴
├── Makefile                         # build / app / run / clean / icon
├── Resources/
│   ├── Info.plist                   # LSUIElement=true, CFBundleIconFile, mic 權限
│   └── AppIcon.icns                 # 🗣️ emoji 生成的 app icon
├── Sources/PhemeMurmur/
│   ├── main.swift                   # AppDelegate, 狀態機, menu bar UI
│   ├── HotkeyManager.swift          # CGEvent tap 偵測右 Shift（debounce 400ms）
│   ├── AudioRecorder.swift          # AVAudioEngine 錄音 → 16kHz mono WAV
│   ├── TranscriptionService.swift   # OpenAI API multipart POST
│   ├── PasteService.swift           # NSPasteboard + CGEvent 模擬 Cmd+V
│   └── Config.swift                 # 常數 + config.jsonc 讀取（API key、prefix）
└── scripts/
    └── generate_icon.swift          # 🗣️ emoji → .icns 轉換腳本
```

## 核心架構

### 狀態機

```
IDLE ──[右Shift]──► RECORDING ──[右Shift]──► TRANSCRIBING ──[完成]──► IDLE
                        │                          │
                      [Esc]                      [失敗]
                        │                          │
                      IDLE                   IDLE + 錯誤圖示(3s)
```

三個 `State` enum case：`.idle`、`.recording`、`.transcribing`。Transcribing 期間忽略快捷鍵輸入。錄音中按 Esc 可取消錄音並丟棄音檔。

### Menu Bar 圖示

使用 SF Symbols + `paletteColors` 著色

| State        | SF Symbol                  | Color                                        |
| ------------ | -------------------------- | -------------------------------------------- |
| Idle         | `waveform`                 | White (`.white`)                             |
| Recording    | `record.circle`            | Red (`.systemRed`)                           |
| Transcribing | `text.bubble`              | Blue (`.systemBlue`)                         |
| Error        | `exclamationmark.triangle` | Orange (`.systemOrange`), auto-reverts in 3s |

### Menu 項目

- **Status: {text}**
- **Cancel Recording**（錄音中才顯示，點擊取消錄音）
- **Open Config Folder**（用 Finder 開啟 `~/.config/pheme-murmur/`）
- **Restart**（快捷鍵 R，重新啟動應用程式）

### 資料流

1. **輸入**：右 Shift（全域，任何 app 都能觸發）；Esc 取消錄音
2. **錄音**：AVAudioEngine → 16kHz mono Float32 buffers（NSLock 保護）
3. **存檔**：寫 WAV 到 `$TMPDIR/phememurmur_recording.wav`（16-bit PCM；macOS 的 `FileManager.default.temporaryDirectory`，通常為 `/var/folders/.../T/`）
4. **轉譯**：multipart POST → OpenAI `gpt-4o-transcribe`（`language=zh` + prompt 引導正體中文輸出）
5. **輸出**：若 config 有設定 `prefix`，先 prepend 至轉譯文字前；寫入 NSPasteboard → CGEvent 模擬 Cmd+V 貼到焦點 app
6. **清理**：刪除 temp WAV

### 錯誤處理

- **錄音失敗**：menu 顯示錯誤文字 + 橘色警告圖示，3 秒後恢復 idle
- **轉譯失敗**：同上
- **API key 缺失**：
  - 啟動時找不到 config：console 印出設定指引，menu 維持 "Idle"（無 error icon）
  - 錄音後發現無 key：state 回 idle，menu 文字顯示 "Error: No API key"（無 error icon）
- **Accessibility 權限缺失**：啟動時彈窗提示開啟；若 event tap 建立失敗，menu 顯示 "Waiting for permission... (will relaunch)"，背景 polling 等權限授予後自動 relaunch

## 內建設定

- 設定檔路徑：`~/.config/pheme-murmur/config.jsonc`
- 取樣率：16kHz
- 聲道：Mono
- 最短錄音：0.5s
- 快捷鍵防抖：400ms
- 錯誤圖示顯示：3s
- 轉譯語言：`zh`
- 轉譯提示詞：`請使用正體中文（繁體中文）`
- 輸出前綴：`prefix`（可選，prepend 至轉譯文字前）

### 設定檔格式（JSONC）

支援 `//` 行註解與 `/* */` 區塊註解。首次啟動若設定檔不存在，會自動建立預設內容：

```jsonc
{
  // Your OpenAI API key — get one at https://platform.openai.com/api-keys
  "openai-api-key": "sk-your-key-here",

  // Optional: text to prepend before every transcription result
  // "prefix": ""
}
```

## 權限需求

| Permission    | Framework     | Purpose                                            |
| ------------- | ------------- | -------------------------------------------------- |
| Microphone    | AVAudioEngine | Recording (Info.plist + system dialog)             |
| Accessibility | CGEvent tap   | Global hotkey + simulated keypress (manual enable) |

## 建構與執行

```bash
make build    # swift build -c release
make app      # build + 包成 .app bundle
make run      # build + open PhemeMurmur.app
make install  # build + 複製 .app 到 /Applications/
make icon     # 重新生成 AppIcon.icns
make clean    # 清除 build 產物
```
