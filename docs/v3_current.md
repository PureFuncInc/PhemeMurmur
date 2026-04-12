# PhemeMurmur — 現狀總覽

macOS menu bar app，按右 Shift 錄音，透過 OpenAI gpt-4o-transcribe 轉文字後自動貼到當前輸入焦點。

## 專案結構

```
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
│   └── Config.swift                 # 常數 + API key 讀取
└── scripts/
    └── generate_icon.swift          # 🗣️ emoji → .icns 轉換腳本
```

## 核心架構

### 狀態機

```
IDLE ──[右Shift]──► RECORDING ──[右Shift]──► TRANSCRIBING ──[完成]──► IDLE
                                                    │
                                                  [失敗]
                                                    │
                                              IDLE + 錯誤圖示(3s)
```

三個 `State` enum case：`.idle`、`.recording`、`.transcribing`。Transcribing 期間忽略快捷鍵輸入。

### Menu Bar 圖示

使用 SF Symbols + `paletteColors` 著色（`contentTintColor` 在 macOS 11+ 壞了）：

| 狀態 | SF Symbol | 顏色 |
|---|---|---|
| Idle | `waveform` | 灰（`.secondaryLabelColor`） |
| Recording | `record.circle` | 紅（`.systemRed`） |
| Transcribing | `text.bubble` | 藍（`.systemBlue`） |
| Error（暫態） | `exclamationmark.triangle` | 橘（`.systemOrange`），3 秒自動恢復 |

`isTemplate = false`，不隨 menu bar 明暗自動變色（設計取捨：狀態色比自適應重要）。

### 資料流

1. **輸入**：右 Shift（全域，任何 app 都能觸發）
2. **錄音**：AVAudioEngine → 16kHz mono Float32 buffers（NSLock 保護）
3. **存檔**：寫 WAV 到 `/tmp/phememurmur_recording.wav`（16-bit PCM）
4. **轉譯**：multipart POST → OpenAI `gpt-4o-transcribe`
5. **輸出**：文字寫入 NSPasteboard → CGEvent 模擬 Cmd+V 貼到焦點 app
6. **清理**：刪除 temp WAV

### 錯誤處理

- **錄音失敗**：menu 顯示錯誤文字 + 橘色警告圖示，3 秒後恢復 idle
- **轉譯失敗**：同上
- **API key 缺失**：menu 顯示持續性錯誤（不自動恢復），console 印出設定指引
- **Accessibility 權限缺失**：啟動時提示開啟，快捷鍵靜默失效

## 設定

| 項目 | 值 |
|---|---|
| API key 路徑 | `~/.config/phememurmur/api_key`（純文字） |
| 取樣率 | 16kHz |
| 聲道 | Mono |
| 最短錄音 | 0.5 秒 |
| 快捷鍵防抖 | 400ms |
| 錯誤圖示顯示 | 3 秒 |

## 權限需求

| 權限 | 框架 | 用途 |
|---|---|---|
| Microphone | AVAudioEngine | 錄音（Info.plist + 系統彈窗） |
| Accessibility | CGEvent tap | 全域快捷鍵 + 模擬按鍵（手動開啟） |

## 建構與執行

```bash
make app    # swift build -c release + 包成 .app bundle
make run    # build + open PhemeMurmur.app
make icon   # 重新生成 AppIcon.icns
make clean  # 清除 build 產物
```

## 版本歷程

| 版本 | 內容 | Plan 文件 |
|---|---|---|
| v1 | MVP 全功能（錄音、轉譯、貼上、快捷鍵、menu bar） | `docs/v1_mvp.md` |
| v2 | App icon（🗣️ emoji → icns）+ 簡化 status bar 為靜態 emoji | （已合併至本文件） |
| v3 | SF Symbols 狀態圖示（idle/recording/transcribing/error） | （已合併至本文件） |
