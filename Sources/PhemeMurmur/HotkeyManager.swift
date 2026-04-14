import ApplicationServices
import CoreGraphics
import Foundation
import os

enum HotkeyKey: String, CaseIterable {
    case fn           = "fn"
    case rightCommand = "right-command"
    case rightOption  = "right-option"
    case rightControl = "right-control"
    case rightShift   = "right-shift"

    var keyCode: Int64 {
        switch self {
        case .fn:           return 0x3F
        case .rightCommand: return 0x36
        case .rightOption:  return 0x3D
        case .rightControl: return 0x3E
        case .rightShift:   return 0x3C
        }
    }

    /// Short name used in the parent menu item title (e.g. "Hotkey: Right Shift")
    var shortName: String {
        switch self {
        case .fn:           return "Fn"
        case .rightCommand: return "Right Command"
        case .rightOption:  return "Right Option"
        case .rightControl: return "Right Control"
        case .rightShift:   return "Right Shift"
        }
    }

    /// Full display name with macOS symbol shown in submenu items
    var displayName: String {
        switch self {
        case .fn:           return "Fn"
        case .rightCommand: return "Right Command (⌘)"
        case .rightOption:  return "Right Option (⌥)"
        case .rightControl: return "Right Control (^)"
        case .rightShift:   return "Right Shift (⇧)"
        }
    }

    private var requiredFlag: CGEventFlags {
        switch self {
        case .fn:           return .maskSecondaryFn
        case .rightCommand: return .maskCommand
        case .rightOption:  return .maskAlternate
        case .rightControl: return .maskControl
        case .rightShift:   return .maskShift
        }
    }

    /// Returns true if the flags indicate this key is currently pressed (key-down).
    /// Must be used together with a keyCode check — flags alone do not identify the specific key.
    func isKeyDown(flags: CGEventFlags) -> Bool {
        flags.contains(requiredFlag)
    }
}

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastToggleTime: CFAbsoluteTime = 0

    private let _key = OSAllocatedUnfairLock<HotkeyKey>(initialState: .rightShift)
    var key: HotkeyKey {
        get { _key.withLock { $0 } }
        set { _key.withLock { $0 = newValue } }
    }

    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
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

        guard keyCode == key.keyCode, key.isKeyDown(flags: flags) else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastToggleTime >= Config.debounceInterval else { return }
        lastToggleTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onToggle?()
        }
    }

    private static let escKeyCode: Int64 = 0x35

    fileprivate func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.escKeyCode else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
    }

    fileprivate func reenableIfNeeded() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
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
        manager.reenableIfNeeded()
        return Unmanaged.passUnretained(event)
    }
    switch type {
    case .flagsChanged:
        manager.handleFlagsChanged(event)
    case .keyDown:
        manager.handleKeyDown(event)
    default:
        break
    }

    return Unmanaged.passUnretained(event)
}
