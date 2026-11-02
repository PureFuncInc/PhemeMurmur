# CLAUDE.md

## Build & Run

```bash
make build          # swift build -c release
make app            # build + bundle .app (signs with PhemeMurmurDev cert or ad-hoc)
make run            # build + open app
make install        # build + copy to /Applications + create dist zip
make clean          # rm -rf .build, .app, dist
```

## Architecture

macOS menu bar app (LSUIElement) built with Swift Package Manager — zero external dependencies, Apple frameworks only. Two targets: `PhemeMurmurCore` (Foundation-only library) and `PhemeMurmur` (executable, depends on Core). Entry point is `Sources/PhemeMurmur/main.swift` which creates an `NSApplication` + `AppDelegate` directly (no SwiftUI, no storyboards).

### Core flow

```text
IDLE --[hotkey]--> RECORDING --[hotkey]--> TRANSCRIBING --[done]--> auto-paste --> IDLE
                               [Esc]--> cancel --> IDLE
```

State machine lives in `AppDelegate`. The hotkey toggle and Esc cancel are dispatched by `HotkeyManager`.

### Provider system

`TranscriptionProvider` protocol (`transcribe(fileURL:language:prompt:)`) with three implementations:

- **OpenAIProvider** — Audio Transcriptions API (default model in `OpenAIProvider.defaultModel`), optional post-processing via chat completions when the active prompt template has a `prompt`

This is the minimal version, so we only keep OpenAI provider and remove other providers.

A provider's kind comes from its name in config.json's `providers` (`ProviderType(providerName:)`): `"Apple"` is `AppleSpeechProvider`, any other name is an OpenAI account keyed in the Keychain by that name, so several OpenAI keys can coexist. Nothing is added implicitly: the Provider menu lists exactly the configured entries.

### Key components

- **Config** — loads plain JSON from `~/.config/pheme-murmur/config.json` (no comments allowed). `Config.parse` rejects anything a hand edit can get wrong (unknown keys, wrong types, unsupported enum values, missing or empty `providers`, out-of-range threshold, several `active` entries) with a `ConfigError` naming the key path; `AppDelegate` re-reads the file at launch and on each hotkey press that starts recording, also rejects an active prompt template whose `prompt` the active provider can't run (`supportsPrompt`), and won't record while the file is invalid. Also handles saving individual fields (hotkey, and the `active` flag on provider / prompt-template entries) by editing the text in place to preserve the file's formatting and key order.
- **Keychain** — stores each provider's API key as a generic password in the login keychain (service `com.purefuncinc.PhemeMurmur`, account = provider name). It is the only place API keys live; config.json never holds them.
- **AudioRecorder** — `AVAudioEngine` tap converting hardware audio to 16kHz mono Float32, writes WAV via `AVAudioFile`. Validates minimum duration and RMS silence threshold.
- **HotkeyManager** — `CGEvent.tapCreate` listening for `flagsChanged` + `keyDown` (Esc). Configurable hotkey (`HotkeyKey` enum). Requires Accessibility permission.
- **PasteService** — clipboard + simulated Cmd+V via `CGEvent`.
- **VoiceCommandProcessor** — regex-based Chinese formatting commands (換一行, 空一行, 第一點…第十點).
- **LaunchAtLogin** — `SMAppService.mainApp` with LaunchAgent plist fallback for self-signed builds.
