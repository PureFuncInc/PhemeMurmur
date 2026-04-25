# Voice command post-processor

Date: 2026-04-25
Status: Draft

## Problem

The transcription result returned by `provider.transcribe()` is pasted verbatim
(`main.swift:299-310`). Users have no way to dictate structural markers — line
breaks, numbered list items, paragraph breaks, separators — they have to reach
for the keyboard after pasting and hand-format the text.

## Goal

When the user speaks specific Chinese trigger phrases, replace them in the
transcription with the corresponding formatting before pasting:

- `換行` → `\n`
- `空行` → `\n\n`
- `分隔線` → `\n\n---\n\n`
- `第一點` … `第十點` → `\n1. ` … `\n10. `

Surrounding half-/full-width punctuation and whitespace around each trigger is
absorbed (the STT model usually inserts a comma where the user paused). The
feature is opt-in via a new `voice-commands` config flag, defaulting to `false`.

Non-goals:

- LLM-based command interpretation. This is a deterministic, local string
  substitution.
- Stateful triggers like `下一點` (auto-incrementing). Users say the literal
  number they want.
- Cross-language triggers (e.g. English "newline"). Triggers are zh-TW only;
  see "Future extensions".
- Mid-pipeline interception inside a provider that runs LLM post-processing
  (`prompt`-bearing template). When such a template is active, post-processing
  is skipped entirely — see C2 below.
- User-customisable trigger table in `config.jsonc`. Hard-coded for v1.

## Decisions

### A. Trigger table is hard-coded but structured for easy extension

A single Swift file declares two tables (a static map and a numbered-point
list). Adding new triggers is a one-line edit; no schema or migration.

### B. Boundary handling: absorb surrounding half- and full-width punctuation

The match for any trigger eats surrounding whitespace (`space`, `tab`) and
punctuation (`,` `.` `，` `。` `、`) on both sides. Example:

```
input:  "今天有兩個重點，第一點，要先處理 A，第二點，是 B，換行，記得通知大家"
output: "今天有兩個重點\n1. 要先處理 A\n2. 是 B\n記得通知大家"
```

Rationale: STT models almost always insert punctuation where the user paused
before/after a trigger word. Without absorption the output looks like
`重點，\n1. 要先處理`, with a trailing comma that breaks the list.

### C. Pipeline placement: post-transcription, only when `template?.prompt == nil`

```
provider.transcribe() returns finalText
        ↓
  __SILENCE__ check
        ↓
  if voiceCommandsEnabled && template?.prompt == nil:
      finalText = VoiceCommandProcessor.process(finalText)
        ↓
  output = (prefix ?? "") + finalText
        ↓
  PasteService.pasteText(output)
```

Why skip when `template?.prompt` is set:

- LLM post-processing happens **inside** the same Gemini API call as STT (see
  `GeminiProvider.swift:38-48`). We cannot intercept between STT and LLM.
- A template like `zh_TW-en_US` translates the transcription to English; the
  LLM will translate `第一點` to `First point` and our regex won't match.
- Running post-processing after the LLM would silently fail for users; doing
  nothing is clearer.

### D. Output formats

| Trigger | Output |
|---------|--------|
| 換行 | `\n` |
| 空行 | `\n\n` |
| 分隔線 | `\n\n---\n\n` |
| 第一點 | `\n1. ` |
| 第二點 | `\n2. ` |
| … | … |
| 第十點 | `\n10. ` |

`第 N 點` is rendered as Markdown-style ordered list (`\n1. `, trailing space)
because the dictated content immediately follows.

### E. Default: off

A new top-level `voice-commands` field in `config.jsonc`, default `false`. Users
must explicitly opt in. When `false`, the transcription pipeline is unchanged.

## Architecture

### New file: `Sources/PhemeMurmur/VoiceCommandProcessor.swift`

```swift
enum VoiceCommandProcessor {
    private static let staticReplacements: [(trigger: String, output: String)] = [
        ("換行", "\n"),
        ("空行", "\n\n"),
        ("分隔線", "\n\n---\n\n"),
    ]

    private static let numberedPoints: [(trigger: String, output: String)] = [
        ("第一點", "\n1. "), ("第二點", "\n2. "), ("第三點", "\n3. "),
        ("第四點", "\n4. "), ("第五點", "\n5. "), ("第六點", "\n6. "),
        ("第七點", "\n7. "), ("第八點", "\n8. "), ("第九點", "\n9. "),
        ("第十點", "\n10. "),
    ]

    /// Boundary characters absorbed around any trigger.
    /// Includes ASCII space/tab, full-width space, and common half-/full-width
    /// punctuation that STT models tend to insert on pauses.
    private static let boundaryClass = #"[ \t\u{3000}，。、,.]*"#

    static func process(_ text: String) -> String { /* … */ }
}
```

`process` runs every entry through one regex per trigger:

```
\(boundaryClass)\(escapedTrigger)\(boundaryClass)
```

…replacing the whole match (including absorbed boundary chars) with the
trigger's output. Triggers are processed longest-first to avoid partial
matches (none in the v1 table actually conflict, but ordering by length keeps
this future-proof).

### Config changes

`Sources/PhemeMurmur/Config.swift`:

- `ConfigFile` gains an optional `voiceCommands: Bool?` decoded from
  `voice-commands`.
- A computed `resolvedVoiceCommands: Bool` returns `voiceCommands ?? false`.
- `defaultConfigContent` includes a commented-out line so users discover the
  flag:
  ```jsonc
  // Optional: enable local voice-command post-processing (換行, 第一點, etc.).
  // Only active when the current prompt template has no "prompt" field.
  // "voice-commands": true,
  ```

### Wiring in `main.swift`

Around line 299, between the `__SILENCE__` check and the prefix concatenation:

```swift
var processed = finalText
if self.voiceCommandsEnabled, template?.prompt == nil {
    processed = VoiceCommandProcessor.process(processed)
}
let output = (self.prefix ?? "") + processed
```

`voiceCommandsEnabled` is loaded once at startup from
`ConfigFile.resolvedVoiceCommands` and refreshed on config reload (same path
the existing `prefix` and `silenceThreshold` use).

## Testing

New file: `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift`

Cases:

- Empty input → empty output
- No triggers → output equals input
- Single `換行` mid-sentence with surrounding half-width comma absorbed
- Single `換行` mid-sentence with surrounding full-width `，` absorbed
- `第一點 … 第二點 … 第三點` produces `\n1. ` `\n2. ` `\n3. `
- `第十點` produces `\n10. ` (two-digit edge)
- Consecutive triggers without content between (`換行 換行`) → `\n\n`
- Trigger at start of text (no leading whitespace required)
- Trigger at end of text (no trailing whitespace required)
- Trigger inside an unrelated word should NOT match — though current triggers
  are unlikely to overlap with normal speech (`第一點` is a complete phrase),
  the test pins this against future regressions
- Mixed: `分隔線` + `空行` + `第一點` in one input

The test target is added to `Package.swift`. (One-time scaffolding, since the
project has no test target yet.)

## Out of scope (YAGNI)

- Auto-renumbering when the user dictates `第一點 … 第一點` again.
- Stateful `下一點` triggers.
- English / Japanese / other language triggers.
- Trigger table in `config.jsonc`.
- Triggers that work inside an LLM `prompt` template.
- Menu-bar toggle for `voice-commands` (config-file only for v1).

## Future extensions

If users ask for any of these, the structured trigger tables and boundary regex
make them easy:

- Append `第十一點 … 第二十點` as additional rows.
- Migrate the table into `config.jsonc` once a real customisation case appears
  (the `(trigger, output)` shape maps cleanly to JSON).
- Add an English mirror table guarded by the active template's language.
