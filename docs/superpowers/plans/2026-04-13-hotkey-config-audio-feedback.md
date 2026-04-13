# Configurable Hotkey & Audio Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to configure the trigger hotkey (right modifier keys) from the menu bar, and play system sounds when recording starts and stops.

**Architecture:** `HotkeyKey` enum replaces the hardcoded keycode in `HotkeyManager`; a boolean `isRecordingKey` flag switches the tap into capture mode. `Config` gains a `hotkey` field and a `saveHotkey(_:)` writer. `AppDelegate` adds a hotkey menu item that drives the 5-second capture flow, and inserts `NSSound` calls around start/stop recording.

**Tech Stack:** Swift 5.9, AppKit, CoreGraphics CGEvent tap, NSSound (macOS system sounds)

---

## File Map

| File | Change |
|------|--------|
| `Sources/PhemeMurmur/HotkeyManager.swift` | Add `HotkeyKey` enum (CaseIterable), `var key`, `isRecordingKey` flag, `onKeyRecorded` callback, `startRecordingKey()` / `stopRecordingKey()` |
| `Sources/PhemeMurmur/Config.swift` | Add `hotkey: String?` to `ConfigFile`, `resolvedHotkey` computed property, `Config.saveHotkey(_:)` static function, update `defaultConfigContent` |
| `Sources/PhemeMurmur/main.swift` | Add `hotkeyMenuItem`, `currentHotkey`, timer; wire `onKeyRecorded`; add `NSSound` calls in `startRecording()` and `stopRecordingAndTranscribe()` |

---

### Task 1: Add HotkeyKey enum and configurable key + recording mode to HotkeyManager

**Files:**
- Modify: `Sources/PhemeMurmur/HotkeyManager.swift`

- [ ] **Step 1: Replace the contents of `HotkeyManager.swift` with the updated version**

```swift
import ApplicationServices
import CoreGraphics
import Foundation

enum HotkeyKey: String, CaseIterable {
    case rightShift   = "right-shift"
    case rightOption  = "right-option"
    case rightControl = "right-control"

    var keyCode: Int64 {
        switch self {
        case .rightShift:   return 0x3C
        case .rightOption:  return 0x3D
        case .rightControl: return 0x3E
        }
    }

    var displayName: String {
        switch self {
        case .rightShift:   return "Right Shift"
        case .rightOption:  return "Right Option"
        case .rightControl: return "Right Control"
        }
    }

    private var requiredFlag: CGEventFlags {
        switch self {
        case .rightShift:   return .maskShift
        case .rightOption:  return .maskAlternate
        case .rightControl: return .maskControl
        }
    }

    func isKeyDown(flags: CGEventFlags) -> Bool {
        flags.contains(requiredFlag)
    }
}

final class HotkeyManager {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastToggleTime: CFAbsoluteTime = 0

    var key: HotkeyKey = .rightShift
    var onToggle: (() -> Void)?

    // Recording mode — captures the next supported modifier key press
    fileprivate var isRecordingKey = false
    var onKeyRecorded: ((HotkeyKey) -> Void)?

    func startRecordingKey() {
        isRecordingKey = true
    }

    func stopRecordingKey() {
        isRecordingKey = false
    }

    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if isRecordingKey {
            // Capture any supported modifier key on key-down
            guard let detected = HotkeyKey.allCases.first(where: { $0.keyCode == keyCode }),
                  detected.isKeyDown(flags: flags) else { return }
            isRecordingKey = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyRecorded?(detected)
            }
            return
        }

        // Normal mode: trigger only the configured key
        guard keyCode == key.keyCode, key.isKeyDown(flags: flags) else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastToggleTime >= Config.debounceInterval else { return }
        lastToggleTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onToggle?()
        }
    }

    static func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    manager.handleFlagsChanged(event)

    return Unmanaged.passUnretained(event)
}
```

- [ ] **Step 2: Verify build succeeds**

```bash
cd /Users/carlos/work/PhemeMurmur && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhemeMurmur/HotkeyManager.swift
git commit -m "feat(hotkey): add HotkeyKey enum and recording mode to HotkeyManager"
```

---

### Task 2: Add hotkey field to Config and saveHotkey writer

**Files:**
- Modify: `Sources/PhemeMurmur/Config.swift`

- [ ] **Step 1: Add `hotkey` field to `ConfigFile` struct**

In `ConfigFile`, add the new field alongside the existing ones:

```swift
struct ConfigFile: Decodable {
    // Legacy single-key fields
    let openaiApiKey: String?
    let geminiApiKey: String?
    let provider: ProviderType?

    // Multi-provider support
    let providers: [String: ProviderEntry]?
    let activeProvider: String?

    let prefix: String?
    let promptTemplates: [String: PromptTemplate]?
    let hotkey: String?                                // ← new

    enum CodingKeys: String, CodingKey {
        case openaiApiKey    = "openai-api-key"
        case geminiApiKey    = "gemini-api-key"
        case provider
        case providers
        case activeProvider  = "active-provider"
        case prefix
        case promptTemplates = "prompt-templates"
        case hotkey                                    // ← new
    }

    // ... (resolvedProviders and resolvedActiveProvider unchanged)

    var resolvedHotkey: HotkeyKey {                    // ← new
        guard let raw = hotkey, let k = HotkeyKey(rawValue: raw) else { return .rightShift }
        return k
    }
}
```

- [ ] **Step 2: Add `saveHotkey(_:)` to the `Config` enum**

Add after the `loadConfig()` function:

```swift
/// Writes (or updates) the "hotkey" field in config.jsonc, preserving all other content.
static func saveHotkey(_ key: HotkeyKey) {
    guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }
    let newEntry = "\"hotkey\": \"\(key.rawValue)\""

    // Replace existing hotkey field if present
    if let range = content.range(of: #""hotkey"\s*:\s*"[^"]*""#, options: .regularExpression) {
        content.replaceSubrange(range, with: newEntry)
    } else if let idx = content.firstIndex(of: "{") {
        // Insert as first field after the opening brace
        content.insert(contentsOf: "\n    \(newEntry),", at: content.index(after: idx))
    }

    try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
}
```

- [ ] **Step 3: Update `defaultConfigContent` to document the hotkey option**

Find the `defaultConfigContent` string and add a comment line for `hotkey` after the `active-provider` line:

```swift
static let defaultConfigContent = """
{
    "providers": {
        "OpenAI": { "type": "openai", "api-key": "sk-proj-xxx" },
        "Gemini": { "type": "gemini", "api-key": "..." }
    },
    "active-provider": "OpenAI",

    // Hotkey to start/stop recording. Options: right-shift (default), right-option, right-control
    // "hotkey": "right-shift",

    // Optional: text to prepend before every transcription result
    // "prefix": "",

    // Prompt templates — switchable from the menu bar.
    //   "language": input audio language (ISO-639-1), helps transcription accuracy
    //   "prompt": if set, sends transcribed text through LLM for post-processing
    "prompt-templates": {
        "zh_TW": { "language": "zh" },
        "zh_TW-en_US": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
    }
}
"""
```

- [ ] **Step 4: Verify build succeeds**

```bash
cd /Users/carlos/work/PhemeMurmur && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/PhemeMurmur/Config.swift
git commit -m "feat(config): add hotkey field parsing and saveHotkey writer"
```

---

### Task 3: Wire hotkey configuration menu item in AppDelegate

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift`

- [ ] **Step 1: Add new stored properties to `AppDelegate`**

After the existing property declarations (before `private var activeProvider`), add:

```swift
private var hotkeyMenuItem: NSMenuItem!
private var currentHotkey: HotkeyKey = .rightShift
private var hotkeyRecordingTimer: DispatchWorkItem?
```

- [ ] **Step 2: Initialize `currentHotkey` from config in `setupApp()`**

In the `if let config = Config.loadConfig()` block, after `prefix = config.prefix`, add:

```swift
currentHotkey = config.resolvedHotkey
hotkeyManager.key = currentHotkey
```

- [ ] **Step 3: Add the hotkey menu item to the status menu in `setupApp()`**

After `statusMenu.setSubmenu(promptSubmenu, for: promptMenuItem)` and before the following `statusMenu.addItem(NSMenuItem.separator())`, insert:

```swift
hotkeyMenuItem = NSMenuItem(
    title: "Hotkey: \(currentHotkey.displayName)",
    action: #selector(startHotkeyRecording),
    keyEquivalent: ""
)
statusMenu.addItem(hotkeyMenuItem)
```

This places the hotkey item in the same section as Provider and Prompt, resulting in:
```
Provider
Prompt
Hotkey: Right Shift   ← new
---
Open Config Folder
Restart
Quit
```

- [ ] **Step 4: Add `startHotkeyRecording` and `cancelHotkeyRecording` methods**

Add before the `updateStatus` method:

```swift
@objc private func startHotkeyRecording() {
    guard state == .idle else { return }
    hotkeyMenuItem.title = "Press a modifier key..."
    hotkeyMenuItem.action = nil  // prevent re-click during capture

    hotkeyManager.startRecordingKey()

    let timer = DispatchWorkItem { [weak self] in
        self?.cancelHotkeyRecording()
    }
    hotkeyRecordingTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)
}

private func cancelHotkeyRecording() {
    hotkeyManager.stopRecordingKey()
    hotkeyMenuItem.title = "Hotkey: \(currentHotkey.displayName)"
    hotkeyMenuItem.action = #selector(startHotkeyRecording)
    hotkeyRecordingTimer = nil
}
```

- [ ] **Step 5: Wire `onKeyRecorded` callback in `setupApp()`**

After the `hotkeyManager.onToggle = { ... }` block, add:

```swift
hotkeyManager.onKeyRecorded = { [weak self] key in
    guard let self else { return }
    self.hotkeyRecordingTimer?.cancel()
    self.hotkeyRecordingTimer = nil
    self.currentHotkey = key
    self.hotkeyMenuItem.title = "Hotkey: \(key.displayName)"
    self.hotkeyMenuItem.action = #selector(AppDelegate.startHotkeyRecording)
    Config.saveHotkey(key)
    print("Hotkey changed to: \(key.displayName)")
}
```

- [ ] **Step 6: Verify build succeeds**

```bash
cd /Users/carlos/work/PhemeMurmur && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "feat(ui): add hotkey configuration menu item with 5s capture flow"
```

---

### Task 4: Add audio feedback with NSSound

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift`

- [ ] **Step 1: Play "Tink" when recording starts**

In `startRecording()`, after `try audioRecorder.startRecording()` succeeds (after `state = .recording`), add:

```swift
NSSound(named: "Tink")?.play()
```

The method should look like:

```swift
private func startRecording() {
    do {
        try audioRecorder.startRecording()
        state = .recording
        updateStatus("Recording...")
        NSSound(named: "Tink")?.play()
        print("🎙 Recording... Press Right Shift to stop, Esc to cancel.")
    } catch {
        print("Failed to start recording: \(error)")
        updateStatus("Error: \(error.localizedDescription)")
        showErrorIcon()
    }
}
```

- [ ] **Step 2: Play "Pop" when recording stops**

In `stopRecordingAndTranscribe()`, after `guard let fileURL = audioRecorder.stopRecording()` succeeds (after the guard, before `guard let provider`), add:

```swift
NSSound(named: "Pop")?.play()
```

The beginning of the method should look like:

```swift
private func stopRecordingAndTranscribe() {
    guard let fileURL = audioRecorder.stopRecording() else {
        state = .idle
        updateStatus("Idle")
        print("No audio captured or too short.")
        return
    }

    NSSound(named: "Pop")?.play()

    guard let provider = activeProvider else {
        // ...
    }
    // ...
}
```

- [ ] **Step 3: Verify build succeeds**

```bash
cd /Users/carlos/work/PhemeMurmur && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Build app and do a manual smoke test**

```bash
cd /Users/carlos/work/PhemeMurmur && make run
```

Manual checks:
- Press configured hotkey → hear "Tink", icon turns red
- Press again → hear "Pop", icon turns blue (transcribing)
- Open menu bar → see "Hotkey: Right Shift"
- Click "Hotkey: Right Shift" → label changes to "Press a modifier key..."
- Press Right Option → label changes to "Hotkey: Right Option", config.jsonc is updated
- Wait 5 seconds without pressing → label reverts to previous hotkey name
- Restart app → hotkey persists from config

- [ ] **Step 5: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "feat(ui): add Tink/Pop audio feedback on recording start and stop"
```
