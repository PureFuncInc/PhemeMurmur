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
- Xcode Command Line Tools (`xcode-select --install`)
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

## Configuration

The config file is created automatically at:

```text
~/.config/pheme-murmur/config.jsonc
```
