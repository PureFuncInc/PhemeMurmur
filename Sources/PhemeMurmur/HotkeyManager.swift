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
