import AppKit
import SwiftUI

/// Hosts SettingsView in a borderless-looking window: transparent titlebar, full
/// size content, so the Deep Space panel reads as one surface.
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    let store = SettingsStore()
    private var window: NSWindow?

    func show() {
        if let window {
            store.reload()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        store.reload()
        let hosting = NSHostingView(rootView: SettingsView(store: store))
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.backgroundColor = DeepSpace.nsColor(DeepSpace.spaceVoidBottom)
        created.isReleasedWhenClosed = false
        created.contentView = hosting
        created.center()
        window = created

        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
