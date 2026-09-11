import AppKit

/// Menu bar artwork. The idle state shows the app icon itself so the menu bar and
/// the Dock/Finder representation are literally the same image; the monochrome
/// waveform is kept as a fallback for builds whose bundle has no icon resource.
enum MenuBarIcon {

    /// The app icon, scaled for the menu bar. Not a template image — it keeps the
    /// deep-space background and the cyan-to-violet bars. The icns already carries
    /// a reduced variant for small sizes (no orbital arc, no star dust), so macOS
    /// picks the legible one at this scale.
    static func appIcon(pointSize: CGFloat = 18) -> NSImage? {
        guard let icon = bundleIcon() else { return nil }
        // Resize rather than redraw: the icns carries every size from 16 to 1024,
        // so AppKit picks the representation that matches the display scale instead
        // of us baking a single 1x bitmap that would blur on a Retina menu bar.
        icon.size = NSSize(width: pointSize, height: pointSize)
        icon.isTemplate = false
        return icon
    }

    /// Monochrome five-bar glyph matching the app icon's waveform, tinted by macOS.
    static func waveformTemplate(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.lockFocus()
        NSColor.black.setFill()
        for bar in WaveformGeometry.bars(in: pointSize) {
            let path = NSBezierPath(roundedRect: bar,
                                    xRadius: bar.width / 2,
                                    yRadius: bar.width / 2)
            path.fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Reads AppIcon.icns straight out of the bundle. `NSApp.applicationIconImage`
    /// is unreliable for LSUIElement apps, so the resource is loaded by name.
    private static func bundleIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: NSImage.applicationIconName)
    }
}
