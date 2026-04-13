# Design: Configurable Hotkey & Audio Feedback

**Date:** 2026-04-13
**Status:** Approved

## Overview

Two independent features:
1. Allow users to configure the trigger hotkey from within the app (menu bar interaction)
2. Play system sounds when recording starts and stops

---

## Feature 1: Configurable Hotkey

### Supported Keys

Only single modifier keys are supported (matching current event tap architecture):
- `right-shift` (default)
- `right-option`
- `right-control`

### Config Format

New optional field in `~/.config/pheme-murmur/config.jsonc`:

```jsonc
{
    "hotkey": "right-shift"   // default if omitted
}
```

The default config template is updated to include this field (commented out).

### HotkeyManager Changes

- Remove hardcoded keycode `0x3C`
- Add `HotkeyKey` enum with cases `.rightShift`, `.rightOption`, `.rightControl`, each mapping to its CGEvent keycode
- `HotkeyManager` accepts a `HotkeyKey` at init or via a `setKey(_:)` method
- Add a "recording mode" that captures the next modifier key press instead of triggering `onToggle`

### Menu Bar Interaction

A new menu item is added above the separator, label: `Hotkey: Right Shift`

**Flow:**
1. User clicks the menu item
2. Label changes to `Press a modifier key...`
3. `HotkeyManager` enters recording mode — next modifier key press is captured instead of triggering recording
4. On detection:
   - Update `HotkeyManager` with the new key
   - Overwrite the `hotkey` field in `config.jsonc` (preserving all other content)
   - Update menu item label to `Hotkey: <new key name>`
5. Timeout: if no key is pressed within 5 seconds, cancel and restore previous state

### Config Persistence

When a new hotkey is saved, the `hotkey` field is written/updated in `config.jsonc` using string replacement. If the field doesn't exist yet, it is appended. All other config content is preserved.

---

## Feature 2: Audio Feedback

### Sound Mapping

| Event | Sound | Timing |
|-------|-------|--------|
| Recording starts | `NSSound(named: "Tink")` | After `startRecording()` succeeds |
| Recording stops | `NSSound(named: "Pop")` | After `stopRecording()` is called |
| Recording cancelled | *(silence)* | No sound — avoids confusion with stop |

### Implementation

- Calls are placed directly in `AppDelegate.startRecording()` and `AppDelegate.stopRecordingAndTranscribe()`
- Uses `NSSound(named:)?.play()` — no new files or dependencies required
- No config option to disable sounds (out of scope)

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/PhemeMurmur/HotkeyManager.swift` | Add `HotkeyKey` enum, inject key, add recording mode |
| `Sources/PhemeMurmur/Config.swift` | Add `hotkey` field to `ConfigFile`, update default template |
| `Sources/PhemeMurmur/main.swift` | Add hotkey menu item, wire recording mode, add `NSSound` calls |
