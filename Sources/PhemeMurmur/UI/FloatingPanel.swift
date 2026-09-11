import AppKit

/// A borderless, click-through panel that floats above other windows without
/// ever taking focus. Used for the recording HUD.
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Distance from the screen's usable edges. The HUD card already carries
    /// 24pt of transparent padding inside the panel, so this is on top of that.
    private static let screenMargin: CGFloat = 8

    /// Parks the panel in the bottom-left corner of the active screen.
    ///
    /// Centred at the bottom put it straight under whatever the user was
    /// reading or typing into; the corner keeps it glanceable without sitting in
    /// the line of sight. `visibleFrame` already excludes the menu bar and the
    /// Dock, wherever the Dock happens to live.
    func positionAtBottomCorner() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.minX + Self.screenMargin,
            y: visible.minY + Self.screenMargin
        )
        setFrameOrigin(origin)
    }
}
