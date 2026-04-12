# Status Bar Icon States Design

## Problem

PhemeMurmur's menu bar icon is a static 🗣️ emoji regardless of app state. Users cannot tell whether the app is idle, recording, or transcribing without opening the menu. This makes the most critical state information invisible during normal use.

## Solution

Replace the static emoji with SF Symbols that change icon and color based on app state. All changes are confined to `AppDelegate` in `main.swift`.

## Icon and Color Mapping

| Visual State   | SF Symbol                      | Color                   | Menu Status Text           |
| -------------- | ------------------------------ | ----------------------- | -------------------------- |
| `idle`         | `waveform`                     | `.secondaryLabelColor`  | Status: Idle               |
| `recording`    | `record.circle`                | `.systemRed`            | Status: Recording...       |
| `transcribing` | `text.bubble`                  | `.systemBlue`           | Status: Transcribing...    |
| error          | `exclamationmark.triangle`     | `.systemOrange`         | Status: Error: ...         |

The first three rows correspond to the `State` enum cases. Error is **not** a `State` enum case — it is a transient visual shown when a recording or transcription error occurs, auto-reverting to the idle icon after 3 seconds.

## Implementation

### Coloring Strategy

`contentTintColor` on `NSStatusBarButton` is broken since macOS 11 (Apple FB8530353). Instead, apply color at the image level:

1. Create the SF Symbol via `NSImage(systemSymbolName:accessibilityDescription:)`.
2. Apply both size and color in a single configuration using `NSImage.SymbolConfiguration(pointSize: 18, weight: .regular, scale: .medium)` composed with `.init(paletteColors: [color])`.
3. Set `image.isTemplate = false` to prevent the system from overriding the color with the menu bar foreground color.
4. Assign the resulting image to `button.image`.

**Trade-off:** `isTemplate = false` means the icon will not auto-adapt to menu bar light/dark mode. This is acceptable because the icon color is state-driven and should remain consistent regardless of appearance mode.

### Icon Helper Design

Two methods handle icon display:

- **`updateIcon()`** (no params) — reads `self.state` and maps it to the corresponding SF Symbol and color from the table above. This is the normal-path method, called from `updateStatus()` and during setup.
- **`setIcon(symbolName:color:)`** — low-level helper that takes an explicit symbol name and color, applies the coloring strategy, and assigns to `button.image`. Both `updateIcon()` and error call sites use this method. If `NSImage(systemSymbolName:)` returns nil, falls back to setting `button.title = "🗣️"` (the current emoji approach).

This two-method design avoids adding an `error` case to the `State` enum. Error call sites use `setIcon(symbolName:color:)` directly with the error symbol/color, bypassing the state-to-icon mapping.

### Changes (all in `main.swift`)

1. **Add `setIcon(symbolName:color:)`** — low-level method that creates the SF Symbol image, applies `SymbolConfiguration` with `paletteColors` and `pointSize`/`weight`/`scale`, sets `isTemplate = false`, and assigns to `button.image`.

2. **Modify the existing `updateIcon()` method** (currently at ~line 129) — replace the body to read `self.state`, map to symbol name + color, and call `setIcon(symbolName:color:)`.

3. **Modify `updateStatus(_:)`** — call `updateIcon()` alongside the existing menu item text update.

4. **Remove `button.title = "🗣️"`** — replace with `updateIcon()` call during setup.

5. **Error icon with auto-revert** — in error catch blocks, call `setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)` directly, then schedule the auto-revert:

   ```swift
   setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)
   DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
       guard let self, self.state == .idle else { return }
       self.updateIcon()
   }
   ```

   The guard prevents the timer from overwriting the icon if the user has already started a new recording within the 3-second window.

### Error Icon Call Sites

The error icon + auto-revert pattern applies to:

- `startRecording()` error handler — recording setup failure
- `stopRecordingAndTranscribe()` error handler — transcription API failure

The missing API key check on launch sets `updateStatus("Error: No API key")` but does **not** auto-revert, since the error is persistent until the user provides a key.

### Files Modified

- `Sources/PhemeMurmur/main.swift` (~30-40 lines changed)

### Files Not Modified

- `AudioRecorder.swift`, `TranscriptionService.swift`, `HotkeyManager.swift`, `PasteService.swift`, `Config.swift` — no changes.

## Compatibility

- SF Symbols 1.0/2.0 required. All four symbols (`waveform`, `record.circle`, `text.bubble`, `exclamationmark.triangle`) are available since macOS 11. The project targets macOS 13+, so this is satisfied.
- `NSImage.SymbolConfiguration(paletteColors:)` requires macOS 12+. macOS 13+ target satisfies this.
- No new dependencies or frameworks required.
