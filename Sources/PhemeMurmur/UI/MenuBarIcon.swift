import AppKit

/// Menu bar artwork for the four app states.
///
/// Idle shows the app icon itself, so the menu bar and the Dock/Finder
/// representation are literally the same image. The other three states are drawn
/// on demand — they animate, and a reduced glyph reads better than a shrunken
/// icon when the bar has to say "busy" at a glance.
enum MenuBarIcon {

    // MARK: - Palette
    //
    // Duplicated from MarkIII as CGColors because these are drawn into a raw
    // CGContext rather than through SwiftUI.

    private static let gold = CGColor(srgbRed: 1.0, green: 0.851, blue: 0.541, alpha: 1)  // #FFD98A
    private static let hot = CGColor(srgbRed: 1.0, green: 0.302, blue: 0.180, alpha: 1)   // #FF4D2E
    private static let crimson = CGColor(srgbRed: 0.784, green: 0.063, blue: 0.180, alpha: 1) // #C8102E
    private static let ember = CGColor(srgbRed: 1.0, green: 0.722, blue: 0.627, alpha: 1) // #FFB8A0
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: - Idle

    /// The app icon, scaled for the menu bar. Not a template image — it keeps the
    /// plate, the gold rim and the arc core. The icns already carries a reduced
    /// variant for small sizes, so macOS picks the legible one at this scale.
    static func appIcon(pointSize: CGFloat = 18) -> NSImage? {
        guard let icon = bundleIcon() else { return nil }
        // Resize rather than redraw: the icns carries every size from 16 to 1024,
        // so AppKit picks the representation that matches the display scale
        // instead of us baking a single 1x bitmap that would blur on Retina.
        icon.size = NSSize(width: pointSize, height: pointSize)
        icon.isTemplate = false
        return icon
    }

    // MARK: - Recording

    /// Hot ember sphere for the recording state. `phase` (0...1) drives the
    /// breathing pulse — 0 is dimmest and smallest, 1 brightest and widest.
    static func recordingGlyph(pointSize: CGFloat = 18, phase: CGFloat = 1) -> NSImage {
        let phase = clamp(phase)
        return image(pointSize: pointSize) { ctx, rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            // The design's 13px bead inside an 18pt bar, breathing ±7%.
            let radius = pointSize * 0.361 * (0.93 + 0.14 * phase)

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: pointSize * 0.61 * (0.7 + 0.3 * phase),
                          color: hot.copy(alpha: 0.85 * (0.7 + 0.3 * phase)))
            ctx.setFillColor(hot)
            ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2))
            ctx.fillPath()
            ctx.restoreGState()

            // Lit from the upper left, so it reads as a bead rather than a disc.
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2))
            ctx.clip()
            let body = CGGradient(colorsSpace: space,
                                  colors: [ember, hot, crimson] as CFArray,
                                  locations: [0, 0.6, 1])!
            ctx.drawRadialGradient(body,
                                   startCenter: CGPoint(x: center.x - radius * 0.2,
                                                        y: center.y + radius * 0.3),
                                   startRadius: 0,
                                   endCenter: center, endRadius: radius,
                                   options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    // MARK: - Transcribing

    /// Gold arc spinner for the transcribing state: a 35% arc of a ring, rotating.
    /// `angle` is in radians, clockwise from the top.
    static func transcribingGlyph(pointSize: CGFloat = 18, angle: CGFloat = 0) -> NSImage {
        image(pointSize: pointSize) { ctx, rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = pointSize * 0.33
            let lineWidth = pointSize * 0.17

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: pointSize * 0.28, color: gold.copy(alpha: 0.6))
            ctx.setLineCap(.butt)
            ctx.setLineWidth(lineWidth)
            ctx.setStrokeColor(gold)
            // The spec's conic gradient fades out at 65%; an arc of the lit 35%
            // gives the same read at this size without a gradient mask.
            let start = -angle + .pi / 2
            ctx.addArc(center: center, radius: radius,
                       startAngle: start, endAngle: start + 2 * .pi * 0.35,
                       clockwise: true)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Error

    /// Hot warning triangle for the error state.
    static func errorGlyph(pointSize: CGFloat = 18) -> NSImage {
        image(pointSize: pointSize) { ctx, rect in
            let halfWidth = pointSize * 0.389   // the design's 7px half-base at 18pt
            let height = pointSize * 0.667      // and its 12px height
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: center.y + height / 2))
            path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y - height / 2))
            path.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y - height / 2))
            path.closeSubpath()

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: pointSize * 0.33, color: hot)
            ctx.setFillColor(hot)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: - Animation curves

    /// Breathing curve for the recording pulse: a smooth 0...1 cosine over
    /// `period` seconds, starting at full brightness so the first frame is the
    /// brightest.
    static func pulsePhase(at elapsed: TimeInterval, period: TimeInterval = 1.4) -> CGFloat {
        guard period > 0 else { return 1 }
        let t = elapsed.truncatingRemainder(dividingBy: period) / period
        return CGFloat((cos(t * 2 * .pi) + 1) / 2)
    }

    /// Rotation for the transcribing spinner, in radians, one turn per `period`.
    static func spinAngle(at elapsed: TimeInterval, period: TimeInterval = 1.1) -> CGFloat {
        guard period > 0 else { return 0 }
        let t = elapsed.truncatingRemainder(dividingBy: period) / period
        return CGFloat(t * 2 * .pi)
    }

    // MARK: - Plumbing

    private static func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

    /// Shared drawing scaffold. Uses a drawing handler so AppKit re-renders at the
    /// current display scale instead of us baking one bitmap.
    private static func image(pointSize: CGFloat,
                              draw: @escaping (CGContext, CGRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize),
                            flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, rect)
            return true
        }
        image.isTemplate = false
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
