# PhemeMurmur

macOS menu bar app — 按右 Shift 錄音，透過 OpenAI gpt-4o-transcribe 轉文字，自動貼到當前輸入焦點。

## Build

```bash
make run      # 編譯 + 打包 + 啟動
make install  # 編譯 + 打包 + 安裝到 /Applications
make clean    # 清除 build 產物
```

需要 Xcode Command Line Tools（`xcode-select --install`）。

## 設定

### API Key

```bash
mkdir -p ~/.config/phememurmur
echo 'sk-your-key-here' > ~/.config/phememurmur/api_key
```

### 權限

首次啟動需要授予兩個權限：

1. **麥克風** — 系統會自動彈窗，點允許即可
2. **Accessibility** — 需手動開啟：System Settings > Privacy & Security > Accessibility，將 PhemeMurmur 加入清單

Accessibility 權限用於全域快捷鍵偵測和自動貼上功能。若未授權，app 會在 console 輸出提示。

## 使用

1. 啟動後 menu bar 會出現麥克風 icon
2. 按 **右 Shift** 開始錄音（icon 變為實心麥克風）
3. 再按 **右 Shift** 停止錄音
4. 自動送出轉錄請求，完成後文字會貼到當前輸入焦點

## 注意事項

- 錄音時間需 > 0.5 秒，否則會被忽略
- 轉錄期間按右 Shift 不會有反應（防止中斷）
- app 不會出現在 Dock，只在 menu bar
- 每次 `make app` 會重新打包 .app bundle，若之前已授予 Accessibility 權限可能需要重新授權
