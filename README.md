# PhemeMurmur

macOS menu bar app — press Right Shift to record, transcribe speech via OpenAI or Apple's on-device speech recognition, auto-paste to the active input field and clipboard.

## Features

- **Menu bar only** — no Dock icon, stays out of your way
- **Zero dependencies** — pure Swift, Apple frameworks only
- **Auto-paste** — transcribed text is written to clipboard and pasted via Cmd+V
- **Right Shift toggle** — press to start/stop recording (Esc to cancel)
- **Prompt templates** — configurable post-processing (translation, formatting, etc.)

## Build Requirements

- macOS 26+
- Xcode Command Line Tools (`xcode-select --install`) only if building from source
- (Optional) API key for [OpenAI](https://platform.openai.com/api-keys) — only needed for the OpenAI provider

## Install

```bash
make clean && make install
```

## First Run

1. Grant **Accessibility** access when prompted (System Settings > Privacy & Security > Accessibility). The hotkey starts working as soon as access is granted, no restart needed.
2. Press **Right Shift** to start recording and grant **Microphone** access when prompted.
3. The default provider is **Apple** (on-device, no API key). The first transcription for a language takes longer while macOS downloads its speech model.
4. To use **OpenAI**, pick it from the **Provider** menu and enter your API key when asked (or use **Set API Key for OpenAI…**). The key is saved to your login Keychain (see [API keys](#api-keys)). Prompt templates with a `prompt` (such as `zh_TW-en_US`) only work with OpenAI.

## API keys

API keys are stored in the login Keychain as generic passwords: service `com.purefuncinc.PhemeMurmur`, account = the provider name from `config.json` (e.g. `OpenAI`). View or delete them in **Keychain Access** by searching for `com.purefuncinc.PhemeMurmur`.

The Keychain only hands the key to the build that saved it without asking. `make app` signs with the self-signed `PhemeMurmurDev` cert so rebuilds keep access; ad-hoc signed builds change identity every build, so macOS asks for your login password the first time each new build reads the key (choose **Always Allow**).

## Launch at Login

Toggle **Launch at Login** from the menu bar to have macOS start PhemeMurmur automatically when you log in. When enabled, the menu item shows a green check; if macOS reports the registration needs approval (or it failed), a gray info icon appears with a tooltip — clicking it opens **System Settings → General → Login Items**.

For builds without an Apple Developer ID Team Identifier (e.g. the default `PhemeMurmurDev` self-signed cert), `SMAppService` cannot register a login item. PhemeMurmur transparently falls back to writing a LaunchAgent plist at `~/Library/LaunchAgents/com.purefuncinc.PhemeMurmur.plist`; `launchd` then starts the app at the next login. Toggling the menu item off removes the plist. On this fallback path the app does not appear in the System Settings → Login Items list — the menu toggle is the source of truth.

## Configuration

The config file is created automatically at:

```text
~/.config/pheme-murmur/config.json
```

It is plain JSON, so comments are not allowed. Options:

| Key | Description |
| --- | --- |
| `providers` | Map of provider name → `{ "type": "openai" \| "apple" }`. `apple` uses on-device speech recognition and needs no key; `openai` reads its key from the Keychain under the provider name. |
| `providers.<name>.post-process` | Optional, OpenAI only: `{ "base-url": "http://localhost:1234/v1", "model": "openai/gpt-oss-20b" }` routes post-processing (chat completions) to an OpenAI-compatible endpoint such as LM Studio. Defaults to OpenAI. |
| `providers.<name>.enabled` | `true` marks the provider in use; picking another one from the menu bar moves the flag there. Without it, the first provider by name is used. |
| `prompt-templates` | Map of template name → `{ "language": "zh", "prompt": "..." }`. `language` is the ISO-639-1 input language; if `prompt` is set, the transcription is post-processed by an LLM. |
| `prompt-templates.<name>.enabled` | `true` marks the template in use; picking another one from the menu bar moves the flag there. Without it, `zh_TW` is used. |
| `hotkey` | `right-shift` (default), `right-option`, `right-control`, `right-command`, or `fn`. |
| `prefix` | Text prepended to every transcription result. |
| `silence-threshold` | RMS energy threshold (0.0–1.0); quieter recordings are discarded. `0` disables it (e.g. `0.003` to enable). |
| `voice-commands` | `true` turns on local formatting commands (換行 / 空行 / 分隔線 / 第一點…第十點). Skipped when the active template has a `prompt`. |
