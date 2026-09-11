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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = DeepSpace.nsColor(DeepSpace.spaceVoidBottom)
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

    private func dismiss() {
        OnboardingWindow.markOnboardingComplete()
        window?.close()
        window = nil
        onDismiss?()
    }

    func windowWillClose(_ notification: Notification) {
        OnboardingWindow.markOnboardingComplete()
        onDismiss?()
        onDismiss = nil
    }
}
