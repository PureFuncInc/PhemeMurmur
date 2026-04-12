# Status Bar Icon States Design

## Problem

PhemeMurmur's menu bar icon is a static 🗣️ emoji regardless of app state. Users cannot tell whether the app is idle, recording, or transcribing without opening the menu. This makes the most critical state information invisible during normal use.

## Solution

Replace the static emoji with SF Symbols that change icon and color based on app state. All changes are confined to `AppDelegate` in `main.swift`.

## State-to-Icon Mapping

| State          | SF Symbol                      | Tint Color              | Menu Status Text           |
| -------------- | ------------------------------ | ----------------------- | -------------------------- |
| `idle`         | `waveform`                     | `.secondaryLabelColor`  | Status: Idle               |
| `recording`    | `record.circle`                | `.systemRed`            | Status: Recording...       |
| `transcribing` | `text.bubble`                  | `.systemBlue`           | Status: Transcribing...    |
| error          | `exclamationmark.triangle`     | `.systemOrange`         | Status: Error: ...         |

Error is not a `State` enum case. It is a transient visual shown when a transcription or recording error occurs, reverting to the idle icon after 3 seconds.

## Implementation

### Changes (all in `main.swift`)

1. **New helper method `updateIcon(for:)`** — sets `statusBarItem.button.image` and `button.contentTintColor` based on the current state.
   - Uses `NSImage(systemSymbolName:accessibilityDescription:)` to create the icon.
   - Applies `withSymbolConfiguration(.init(pointSize: 18, weight: .regular))` for menu bar sizing.
   - Sets `button.contentTintColor` to the mapped color.

2. **Modify `updateStatus(_:)`** — call `updateIcon(for:)` alongside the existing menu item text update.

3. **Remove `button.title = "🗣️"`** — replace with `button.image` set via `updateIcon(for: .idle)` during setup.

4. **Error icon with auto-revert** — in error catch blocks, show the error icon, then `DispatchQueue.main.asyncAfter(deadline: .now() + 3)` to restore idle icon.

### Files Modified

- `Sources/PhemeMurmur/main.swift` (~20-30 lines changed)

### Files Not Modified

- `AudioRecorder.swift` — no changes
- `TranscriptionService.swift` — no changes
- `HotkeyManager.swift` — no changes
- `PasteService.swift` — no changes
- `Config.swift` — no changes

## Compatibility

- SF Symbols requires macOS 11+. The project targets macOS 13+ (`Package.swift`), so this is satisfied.
- No new dependencies or frameworks required.
