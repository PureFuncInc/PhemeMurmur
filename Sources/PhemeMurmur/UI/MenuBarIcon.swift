import AppKit

/// The idle menu bar glyph: the same five bars as the app icon, drawn as a
/// template image so macOS tints it for light/dark menu bars automatically.
enum MenuBarIcon {

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
}
