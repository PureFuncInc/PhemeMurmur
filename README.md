# PhemeMurmur

macOS menu bar app — press Right Shift to record, transcribe speech via OpenAI or Google Gemini, auto-paste to the active input field and clipboard.

## Features

- **Menu bar only** — no Dock icon, stays out of your way
- **Right Shift toggle** — press to start/stop recording (Esc to cancel)
- **Multi-provider** — switch between OpenAI and Google Gemini at runtime
- **Prompt templates** — configurable post-processing (translation, formatting, etc.)
- **Auto-paste** — transcribed text is written to clipboard and pasted via Cmd+V
- **Zero dependencies** — pure Swift, Apple frameworks only
- **Deep Space UI** — a floating dark-space settings window, and a nebula HUD while recording
- **Recording feedback** — a nebula core with corona beams appears at the bottom of the screen, reacting live to your voice

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) only if building from source
- API key for [OpenAI](https://platform.openai.com/api-keys) or [Google Gemini](https://aistudio.google.com/apikey)

## Install

No checkout needed — this downloads the latest release, installs it to
`/Applications`, and launches it:

```bash
curl -fsSL https://raw.githubusercontent.com/PureFuncInc/PhemeMurmur/main/install.sh | bash
```

From a source checkout instead:

```bash
make clean && make install
```

`make install` keeps whatever onboarding state you already had. Pass `ONBOARD=1`
to replay the boot sequence.

## Updating

PhemeMurmur checks for a new release on launch and every six hours, and the
menu bar shows **更新到 X.Y.Z** when one is out. Choosing it quits the app,
installs the new version and relaunches it. There is also a **檢查更新…** item
to look right now.

Self-updating only works for the copy in `/Applications` — that is the one the
installer replaces. A build running from anywhere else is pointed at the release
page instead.

## Releasing

```bash
make release VERSION=vX.Y.Z
```

Runs the tests, tags, builds, zips, publishes the GitHub release and uploads the
architecture's zip. The tag is what stamps `CFBundleShortVersionString`, which
is the version the updater compares against.

## Setup

On first launch, a guided onboarding walks you through four steps:

1. Welcome
2. Grant **Accessibility** and **Microphone** access — the panel detects both live and unlocks itself once granted
3. Pick a transcription provider and enter its API key
4. Record once to confirm everything works

## Settings

Open **設定…** from the menu bar (or press `Cmd+,` while the menu is open). The
window has five panes: 轉錄服務 (provider and API key), 快捷鍵, 提示模板, 一般
(launch at login, voice commands, silence threshold, prefix) and 診斷 (config
folder, error log). Everything is written back to `~/.config/pheme-murmur/config.jsonc`.

## Launch at Login

Toggle **登入時啟動** in the 一般 pane of the settings window to have macOS start PhemeMurmur automatically when you log in. If macOS reports the registration needs approval (or it failed), clicking the toggle opens **System Settings → General → Login Items** instead of switching on.

For builds without an Apple Developer ID Team Identifier (e.g. the default `PhemeMurmurDev` self-signed cert), `SMAppService` cannot register a login item. PhemeMurmur transparently falls back to writing a LaunchAgent plist at `~/Library/LaunchAgents/com.purefuncinc.PhemeMurmur.plist`; `launchd` then starts the app at the next login. Toggling it off removes the plist. On this fallback path the app does not appear in the System Settings → Login Items list — the settings toggle is the source of truth.

## Configuration

The config file is created automatically at:

```text
~/.config/pheme-murmur/config.jsonc
```
