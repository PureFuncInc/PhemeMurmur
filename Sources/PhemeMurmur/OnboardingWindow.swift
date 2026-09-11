import AppKit
import SwiftUI

final class OnboardingWindow: NSObject, NSWindowDelegate {
    private static let markerPath: String = {
        let dir = (Config.configPath as NSString).deletingLastPathComponent
        return "\(dir)/.onboarding-done"
    }()

    static var needsOnboarding: Bool {
        !FileManager.default.fileExists(atPath: markerPath)
    }

    static func markOnboardingComplete() {
        FileManager.default.createFile(atPath: markerPath, contents: nil)
    }

    private var window: NSWindow?
    private var onDismiss: (() -> Void)?
    /// True only when the user pressed 完成 on the last page. Closing early with
    /// the red button leaves onboarding pending so it shows again next launch.
    private var didFinish = false

    func showIfNeeded(onDismiss: @escaping () -> Void) {
        guard OnboardingWindow.needsOnboarding else {
            onDismiss()
            return
        }
        self.onDismiss = onDismiss
        showWindow()
    }

    private func showWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        w.isOpaque = false
        // Same reason as the settings window: a square window shadow would
        // square off the plate's chamfered corners.
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        w.contentView = NSHostingView(rootView: OnboardingView(
            onFinish: { [weak self] in self?.dismiss() },
            store: SettingsWindowController.shared.store
        ))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called when the user finishes the flow. Teardown itself happens in
    /// `windowWillClose`, which is the one path both the finish button and the
    /// red close button go through.
    private func dismiss() {
        didFinish = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if didFinish { OnboardingWindow.markOnboardingComplete() }

        // Anything typed but never submitted (an API key the user did not press
        // Enter on) is thrown away rather than left in the shared store, where it
        // would masquerade as the value in effect and block later disk reads.
        SettingsWindowController.shared.store.discardUnsavedEdits()

        // Release the window and its SwiftUI content on both close paths. With
        // isReleasedWhenClosed == false, leaving them referenced kept the whole
        // NSWindow -> NSHostingView -> OnboardingView chain — and its 1 Hz
        // accessibility poll timer — alive for the rest of the app's lifetime.
        let closing = window
        closing?.delegate = nil
        window = nil
        DispatchQueue.main.async { closing?.contentView = NSView() }

        onDismiss?()
        onDismiss = nil
    }
}
