# Icon: App Icon + Status Bar Icon

## Context

App 目前沒有 app icon（系統預設白色），status bar 用 SF Symbols 區分狀態。改為統一使用 🗣️ emoji。

## 變更

### 1. Status bar icon

修改 `Sources/PhemeMurmur/main.swift`：

- `updateIcon()` 改為設定 `button.title = "🗣️"`，移除 NSImage 邏輯
- `updateStatus()` 不再傳 icon 參數
- 所有狀態使用相同 emoji，不做視覺區分

### 2. App icon

- 建立 `scripts/generate_icon.swift`：用 NSFont 把 🗣️ render 成 16/32/128/256/512 各尺寸（含 @2x）PNG
- 用 `iconutil` 把 iconset 打包成 `Resources/AppIcon.icns`
- `Info.plist` 加 `CFBundleIconFile` = `AppIcon`
- `Makefile` 的 `app` target 加入複製 `AppIcon.icns` 到 `Contents/Resources/`

### 涉及檔案

- `Sources/PhemeMurmur/main.swift` — 簡化 status bar icon 邏輯
- `scripts/generate_icon.swift` — 新增，emoji 轉 icns 腳本
- `Resources/Info.plist` — 加 CFBundleIconFile
- `Makefile` — app target 加 Resources 複製步驟

### 驗證

1. `make app && make run` 啟動後 status bar 顯示 🗣️
2. Finder 中 .app 顯示 🗣️ 圖示
3. Cmd+Tab 切換時顯示 🗣️ 圖示
