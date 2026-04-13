# PhemeMurmur

macOS menu bar app — 按右 Shift 錄音，透過 OpenAI gpt-4o-transcribe 轉文字，自動貼到當前輸入焦點。

## Build

```bash
make run      # 編譯 + 打包 + 啟動
make install  # 編譯 + 打包 + 安裝到 /Applications
make clean    # 清除 build 產物
```

需要 Xcode Command Line Tools（`xcode-select --install`）。
