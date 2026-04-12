# Status Bar Icon States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static 🗣️ emoji in the menu bar with SF Symbols that change icon and color based on app state (idle/recording/transcribing/error).

**Architecture:** Two new methods in `AppDelegate` — `setIcon(symbolName:color:)` handles the low-level SF Symbol rendering with `paletteColors` and `isTemplate = false`; `updateIcon()` maps `self.state` to the correct symbol/color and delegates to `setIcon`. Error call sites use `setIcon` directly to show the transient error icon.

**Tech Stack:** AppKit (`NSImage.SymbolConfiguration`, SF Symbols), macOS 13+

**Spec:** `docs/superpowers/specs/2026-04-12-status-bar-icon-states-design.md`

---

## File Structure

Only one file is modified:

- **Modify:** `Sources/PhemeMurmur/main.swift` — all icon and error-handling changes

No new files. No changes to `AudioRecorder.swift`, `TranscriptionService.swift`, `HotkeyManager.swift`, `PasteService.swift`, or `Config.swift`.

---

## Task 1: Add `setIcon(symbolName:color:)` low-level helper

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift:129-134` (replace existing `updateIcon()` body region)

- [ ] **Step 1: Add `setIcon` method after the existing `updateIcon()` method (line 134)**

Add this method to `AppDelegate`:

```swift
private func setIcon(symbolName: String, color: NSColor) {
    guard let button = statusItem?.button else { return }
    let sizeConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular, scale: .medium)
    let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
    let config = sizeConfig.applying(colorConfig)
    if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        image.isTemplate = false
        button.image = image
        button.title = ""
    } else {
        button.image = nil
        button.title = "🗣️"
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/yfr-mac-studio/GitHub/purefuncinc/PhemeMurmur && swift build -c release 2>&1 | tail -5`

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "feat(ui): add setIcon helper for SF Symbol menu bar icons"
```

---

## Task 2: Rewrite `updateIcon()` to map state to SF Symbol

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift:129-134` (the existing `updateIcon()` method)

- [ ] **Step 1: Replace the body of `updateIcon()` (lines 129-134)**

Replace the existing method:

```swift
private func updateIcon() {
    if let button = statusItem?.button {
        button.image = nil
        button.title = "🗣️"
    }
}
```

With:

```swift
private func updateIcon() {
    let symbolName: String
    let color: NSColor
    switch state {
    case .idle:
        symbolName = "waveform"
        color = .secondaryLabelColor
    case .recording:
        symbolName = "record.circle"
        color = .systemRed
    case .transcribing:
        symbolName = "text.bubble"
        color = .systemBlue
    }
    setIcon(symbolName: symbolName, color: color)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/yfr-mac-studio/GitHub/purefuncinc/PhemeMurmur && swift build -c release 2>&1 | tail -5`

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "feat(ui): update menu bar icon based on app state"
```

---

## Task 3: Add error icon with auto-revert to error handlers

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift:77-80` (`startRecording` error handler)
- Modify: `Sources/PhemeMurmur/main.swift:111-116` (`stopRecordingAndTranscribe` transcription error handler)

- [ ] **Step 1: Add error icon to `startRecording()` error handler**

In `startRecording()`, after the existing `updateStatus("Error: ...")` call (line 79), add the error icon and auto-revert. Replace:

```swift
} catch {
    print("Failed to start recording: \(error)")
    updateStatus("Error: \(error.localizedDescription)")
}
```

With:

```swift
} catch {
    print("Failed to start recording: \(error)")
    updateStatus("Error: \(error.localizedDescription)")
    setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
        guard let self, self.state == .idle else { return }
        self.updateIcon()
    }
}
```

- [ ] **Step 2: Add error icon to `stopRecordingAndTranscribe()` transcription error handler**

In the transcription `catch` block (inside `await MainActor.run`), replace:

```swift
await MainActor.run {
    print("Transcription failed: \(error)")
    self.state = .idle
    self.updateStatus("Error: \(error.localizedDescription)")
}
```

With:

```swift
await MainActor.run {
    print("Transcription failed: \(error)")
    self.state = .idle
    self.updateStatus("Error: \(error.localizedDescription)")
    self.setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
        guard let self, self.state == .idle else { return }
        self.updateIcon()
    }
}
```

Note: `updateStatus` calls `updateIcon()` which sets the idle icon, but we immediately override it with `setIcon(...)` for the error icon. The auto-revert timer then restores the idle icon after 3 seconds.

Note: The "no API key" guard at line 91-96 in `stopRecordingAndTranscribe()` is intentionally **not** given the error icon treatment. Like the launch-time API key check, it represents a persistent configuration error — the error text stays in the menu until the user provides a key and restarts.

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/yfr-mac-studio/GitHub/purefuncinc/PhemeMurmur && swift build -c release 2>&1 | tail -5`

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "feat(ui): show error icon with 3s auto-revert on failures"
```

---

## Task 4: Build, bundle, and manual smoke test

- [ ] **Step 1: Build and bundle the app**

Run: `cd /Users/yfr-mac-studio/GitHub/purefuncinc/PhemeMurmur && make app`

Expected: No errors. `PhemeMurmur.app` bundle created.

- [ ] **Step 2: Launch and visually verify**

Run: `cd /Users/yfr-mac-studio/GitHub/purefuncinc/PhemeMurmur && open PhemeMurmur.app`

Verify in the menu bar:
1. **Idle state**: `waveform` icon in gray appears in menu bar
2. **Recording**: Press Right Shift — icon changes to red `record.circle`
3. **Transcribing**: Press Right Shift again — icon changes to blue `text.bubble`
4. **Back to idle**: After transcription completes — icon returns to gray `waveform`
5. **Menu**: Click the icon — menu shows correct "Status: ..." text matching the icon state

- [ ] **Step 3: Verify error path** (optional — requires temporarily breaking API key)

Rename `~/.config/phememurmur/api_key` temporarily, restart app, and attempt a recording cycle. Verify:
- Orange `exclamationmark.triangle` appears
- After 3 seconds, reverts to gray `waveform`
