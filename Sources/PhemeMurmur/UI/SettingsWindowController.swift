import AppKit
import SwiftUI

/// Hosts SettingsView in a borderless-looking window: transparent titlebar, full
/// size content, and a transparent window background so the Mark III plate's
/// chamfered corners cut through instead of sitting on a square backing.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()

    let store = SettingsStore()
    private var window: NSWindow?

    private override init() { super.init() }

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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.backgroundColor = .clear
        created.isOpaque = false
        // The plate draws its own shadow; the window's would trace the square
        // frame and give the cut corners a visible right angle.
        created.hasShadow = false
        created.isReleasedWhenClosed = false
        created.delegate = self
        created.contentView = hosting
        created.center()
        window = created

        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window abandons whatever was typed but not submitted; keeping
    /// it would show a stale value next time and could be written to disk by an
    /// unrelated save (`saveGeneral` persists the prefix field). The store skips
    /// the discard while onboarding is still on screen, since the two windows share
    /// it and the edit in flight may be onboarding's.
    func windowWillClose(_ notification: Notification) {
        store.discardUnsavedEditsIfIdle()

        // Release the window and its SwiftUI content instead of keeping them for
        // reuse. With isReleasedWhenClosed == false a closed window only goes
        // off screen, and the console's scanline sweep is a repeatForever
        // animation that keeps redrawing on the main thread for as long as the
        // view exists. Rebuilding on the next open costs a few milliseconds;
        // keeping it cost a steady slice of CPU for the rest of the session.
        let closing = window
        window = nil
        // Deferred so the view is not torn down inside its own window's close.
        DispatchQueue.main.async { closing?.contentView = NSView() }
    }
}
