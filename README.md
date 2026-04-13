# PhemeMurmur

macOS menu bar app — 按右 Shift 錄音，透過 OpenAI gpt-4o-transcribe 轉文字，自動貼到當前輸入焦點與剪貼簿。

## Build

```bash
make install  # 編譯 + 打包 + 安裝到 /Applications
make clean    # 清除 build 產物
```

需要 Xcode Command Line Tools（`xcode-select --install`）。

## Error Handling

| Scenario                   | Icon          | Status Text                          | Recovery                          |
| -------------------------- | ------------- | ------------------------------------ | --------------------------------- |
| Invalid config JSON        | Warning, stay | Error: Invalid config syntax         | Fix config.jsonc and restart      |
| Missing API key            | Warning, stay | Error: No API key                    | Add API key to config and restart |
| Recording too short < 0.5s | —             | Idle                                 | Auto-recover, re-record           |
| Transcription API failure  | Warning, 3s   | Error: API error (code): message     | Auto-recover, retry               |
| API response parse error   | Warning, 3s   | Error: Cannot parse API response     | Auto-recover, retry               |

- Warning = orange `exclamationmark.triangle` icon
- "stay" = icon persists until issue is fixed and app is restarted
- "3s" = icon auto-reverts to idle after 3 seconds
