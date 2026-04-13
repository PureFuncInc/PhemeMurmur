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
make install   # build + bundle + copy to /Applications
```

Other targets:

```bash
make run       # build + launch without installing
make clean     # remove build artifacts
```

## Setup

On first launch, a guided onboarding walks you through:

1. Grant **Microphone** access (system prompt)
2. Grant **Accessibility** access (System Settings > Privacy & Security > Accessibility)
3. Add your API key to the config file

The config file is created automatically at:

```text
~/.config/pheme-murmur/config.jsonc
```

### Config example

```jsonc
{
  "providers": {
    "OpenAI": { "type": "openai", "api-key": "sk-proj-xxx" },
    "Gemini": { "type": "gemini", "api-key": "..." },
  },
  "active-provider": "OpenAI",

  // Optional: text to prepend before every transcription result
  // "prefix": "",

  // Prompt templates — switchable from the menu bar
  //   "language": input audio language (ISO-639-1), helps transcription accuracy
  //   "prompt": if set, sends transcribed text through LLM for post-processing
  "prompt-templates": {
    "zh_TW": { "language": "zh" },
    "zh_TW-en_US": {
      "language": "zh",
      "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else.",
    },
  },
}
```

### Config fields

| Field              | Type   | Description                                                                                         |
| ------------------ | ------ | --------------------------------------------------------------------------------------------------- |
| `providers`        | Object | Map of provider name to `{type, api-key}`. Type is `"openai"` or `"gemini"`                         |
| `active-provider`  | String | Which provider to use on launch (defaults to first)                                                 |
| `prefix`           | String | Text prepended to every transcription result                                                        |
| `prompt-templates` | Object | Named templates with optional `language` (ISO-639-1) and `prompt` (LLM post-processing instruction) |

## Usage

| Action                      | Key         |
| --------------------------- | ----------- |
| Start recording             | Right Shift |
| Stop recording & transcribe | Right Shift |
| Cancel recording            | Esc         |

The menu bar icon changes to reflect current state:

| State        | Icon             | Color  |
| ------------ | ---------------- | ------ |
| Idle         | Waveform         | White  |
| Recording    | Record circle    | Red    |
| Transcribing | Text bubble      | Blue   |
| Error        | Warning triangle | Orange |

Use the menu bar dropdown to switch providers, change prompt templates, or open the config folder.

## Error Handling

| Scenario            | Status Text                      | Recovery                    |
| ------------------- | -------------------------------- | --------------------------- |
| Invalid config JSON | Error: Invalid config syntax     | Fix `config.jsonc`, restart |
| Missing API key     | Error: No API key                | Add key to config, restart  |
| Recording < 0.5s    | (silent, returns to Idle)        | Re-record                   |
| API failure         | Error: API error (code): message | Auto-recovers after 3s      |
| Parse error         | Error: Cannot parse API response | Auto-recovers after 3s      |

## Permissions

| Permission    | Why                                              | How to grant                                         |
| ------------- | ------------------------------------------------ | ---------------------------------------------------- |
| Microphone    | Record audio via AVAudioEngine                   | System prompts automatically on first use            |
| Accessibility | Global hotkey detection + Cmd+V paste simulation | System Settings > Privacy & Security > Accessibility |

## Architecture

```txt
Sources/PhemeMurmur/
├── main.swift                  # AppDelegate, state machine, menu bar UI
├── Config.swift                # JSONC config parsing
├── HotkeyManager.swift         # CGEvent tap for Right Shift detection
├── AudioRecorder.swift          # AVAudioEngine, 16kHz mono WAV output
├── TranscriptionProvider.swift  # Provider protocol
├── OpenAIProvider.swift         # OpenAI gpt-4o-mini-transcribe
├── GeminiProvider.swift         # Google Gemini Flash
├── TranscriptionService.swift   # Shared HTTP error handling
├── PasteService.swift           # Clipboard + Cmd+V simulation
└── OnboardingWindow.swift       # First-launch setup wizard
```

Built with Swift Package Manager. No external dependencies.
