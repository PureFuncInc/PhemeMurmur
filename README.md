# PhemeMurmur

macOS menu bar app — press Right Shift to record, transcribe speech via OpenAI or Google Gemini, auto-paste to the active input field and clipboard.

## Features

- **Menu bar only** — no Dock icon, stays out of your way
- **Right Shift toggle** — press to start/stop recording (Esc to cancel)
- **Multi-provider** — switch between OpenAI and Google Gemini at runtime
- **Prompt templates** — configurable post-processing (translation, formatting, etc.)
- **Auto-paste** — transcribed text is written to clipboard and pasted via Cmd+V
- **Zero dependencies** — pure Swift, Apple frameworks only

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) only if building from source
- API key for [OpenAI](https://platform.openai.com/api-keys) or [Google Gemini](https://aistudio.google.com/apikey)

## Install

```bash
make clean && make install
```

## Setup

On first launch, a guided onboarding walks you through:

1. Grant **Accessibility** access (System Settings > Privacy & Security > Accessibility)
2. Set up your API key via the **Provider** menu in the menu bar
3. Grant **Microphone** access (system prompt)

## Launch at Login

Toggle **Launch at Login** from the menu bar to have macOS start PhemeMurmur automatically when you log in. When enabled, the menu item shows a green check; if macOS reports the registration needs approval (or it failed), a gray info icon appears with a tooltip — clicking it opens **System Settings → General → Login Items**.

For builds without an Apple Developer ID Team Identifier (e.g. the default `PhemeMurmurDev` self-signed cert), `SMAppService` cannot register a login item. PhemeMurmur transparently falls back to writing a LaunchAgent plist at `~/Library/LaunchAgents/com.purefuncinc.PhemeMurmur.plist`; `launchd` then starts the app at the next login. Toggling the menu item off removes the plist. On this fallback path the app does not appear in the System Settings → Login Items list — the menu toggle is the source of truth.

## Configuration

The config file is created automatically at:

```text
~/.config/pheme-murmur/config.jsonc
```
