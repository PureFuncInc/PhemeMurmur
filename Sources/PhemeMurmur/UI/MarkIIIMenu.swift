import AppKit

/// Mark III styling for the status bar menu.
///
/// The menu stays a real `NSMenu` — that is what gives a menu bar extra its Esc
/// handling, click-outside dismissal, keyboard navigation and screen placement.
/// Every row is a custom view instead, painting the armour plate edge to edge,
/// so the only part the system still draws is the rounded container behind them.
enum MarkIIIMenu {

    static let width: CGFloat = 252

    /// Two-line telemetry header: the state on top, the active provider and
    /// hotkey underneath.
    static func statusHeader() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = StatusHeaderView()
        return item
    }

    /// A gold hairline between groups. A real `NSMenuItem.separator()` would draw
    /// the system's grey line on a transparent strip and break the plate.
    static func separator() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = SeparatorView()
        return item
    }

    /// A clickable row. `shortcut` is drawn as text only; the real key equivalent
    /// still has to be set on the item so the shortcut actually works.
    static func item(title: String,
                     shortcut: String = "",
                     action: Selector,
                     target: AnyObject,
                     keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.view = RowView(title: title, shortcut: shortcut)
        return item
    }

    // MARK: - Shared drawing

    fileprivate static let rowInset: CGFloat = 8

    /// The plate gradient behind every row, so adjacent items join seamlessly.
    fileprivate static func fillBackground(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [CGColor(srgbRed: 0.118, green: 0.071, blue: 0.063, alpha: 0.97),
                     CGColor(srgbRed: 0.047, green: 0.043, blue: 0.055, alpha: 0.97)] as CFArray,
            locations: [0, 1])!
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: - Views

    /// Base class handling the parts every row shares: the plate background and
    /// the fixed menu width.
    fileprivate class PlateView: NSView {
        override var isFlipped: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            MarkIIIMenu.fillBackground(in: bounds)
        }
    }

    fileprivate final class StatusHeaderView: PlateView {

        /// Refreshed from `AppDelegate` right before the menu opens.
        static var statusLine: String = "STATUS · IDLE"
        static var contextLine: String = ""

        init() {
            super.init(frame: NSRect(x: 0, y: 0, width: MarkIIIMenu.width, height: 40))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let x = MarkIIIMenu.rowInset + 10
            let status = NSAttributedString(string: Self.statusLine, attributes: [
                .font: MarkIII.nsMono(10, .medium),
                .kern: 1.4,
                .foregroundColor: MarkIII.nsColor(MarkIII.dim),
            ])
            status.draw(at: CGPoint(x: x, y: bounds.maxY - 18))

            guard !Self.contextLine.isEmpty else { return }
            let context = NSAttributedString(string: Self.contextLine, attributes: [
                .font: MarkIII.nsMono(10, .medium),
                .kern: 1.4,
                .foregroundColor: MarkIII.nsColor(MarkIII.gold, alpha: 0.8),
            ])
            context.draw(at: CGPoint(x: x, y: bounds.maxY - 33))
        }
    }

    fileprivate final class SeparatorView: PlateView {

        init() {
            super.init(frame: NSRect(x: 0, y: 0, width: MarkIIIMenu.width, height: 11))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            MarkIII.nsColor(MarkIII.gold, alpha: 0.2).setFill()
            NSRect(x: MarkIIIMenu.rowInset + 4, y: bounds.midY - 0.5,
                   width: bounds.width - (MarkIIIMenu.rowInset + 4) * 2, height: 1).fill()
        }
    }

    fileprivate final class RowView: PlateView {

        private let title: String
        private let shortcut: String
        private var hovering = false

        init(title: String, shortcut: String) {
            self.title = title
            self.shortcut = shortcut
            super.init(frame: NSRect(x: 0, y: 0, width: MarkIIIMenu.width, height: 30))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

        /// A custom view has to invoke its own item; the menu does not do it for
        /// us the way it would for a plain title row.
        override func mouseUp(with event: NSEvent) {
            guard let item = enclosingMenuItem, let menu = item.menu else { return }
            menu.cancelTracking()
            menu.performActionForItem(at: menu.index(of: item))
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            if hovering {
                let inset = MarkIIIMenu.rowInset
                let highlight = bounds.insetBy(dx: inset, dy: 1)
                let path = NSBezierPath(cgPath: MarkIII.chamferPath(in: highlight, cut: 7))
                MarkIII.nsColor(MarkIII.crimson, alpha: 0.35).setFill()
                path.fill()
            }

            let x = MarkIIIMenu.rowInset + 10
            let label = NSAttributedString(string: title, attributes: [
                .font: MarkIII.nsFont(13.5, hovering ? .semibold : .regular),
                .foregroundColor: hovering ? NSColor.white : MarkIII.nsColor(MarkIII.ink),
            ])
            let labelSize = label.size()
            label.draw(at: CGPoint(x: x, y: (bounds.height - labelSize.height) / 2))

            guard !shortcut.isEmpty else { return }
            let key = NSAttributedString(string: shortcut, attributes: [
                .font: MarkIII.nsMono(11),
                .foregroundColor: MarkIII.nsColor(MarkIII.dim),
            ])
            let keySize = key.size()
            key.draw(at: CGPoint(x: bounds.maxX - MarkIIIMenu.rowInset - 10 - keySize.width,
                                 y: (bounds.height - keySize.height) / 2))
        }
    }
}

/// Updates the header text. Kept outside the view so `AppDelegate` does not need
/// to know the view type.
extension MarkIIIMenu {
    static func updateStatus(_ status: String, context: String) {
        StatusHeaderView.statusLine = status
        StatusHeaderView.contextLine = context
    }

    /// The status line as last set, so a refresh can update only the context.
    static var currentStatusLine: String { StatusHeaderView.statusLine }
}

extension NSBezierPath {
    /// AppKit's `NSBezierPath(cgPath:)` is unavailable in some toolchains this
    /// project builds with, so the conversion is written out.
    convenience init(cgPath: CGPath) {
        self.init()
        cgPath.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                self.move(to: element.points[0])
            case .addLineToPoint:
                self.line(to: element.points[0])
            case .addQuadCurveToPoint:
                // Elevate the quadratic to the cubic AppKit understands.
                let control = element.points[0], end = element.points[1]
                let start = self.currentPoint
                self.curve(to: end,
                           controlPoint1: CGPoint(x: start.x + 2.0 / 3.0 * (control.x - start.x),
                                                  y: start.y + 2.0 / 3.0 * (control.y - start.y)),
                           controlPoint2: CGPoint(x: end.x + 2.0 / 3.0 * (control.x - end.x),
                                                  y: end.y + 2.0 / 3.0 * (control.y - end.y)))
            case .addCurveToPoint:
                self.curve(to: element.points[2],
                           controlPoint1: element.points[0],
                           controlPoint2: element.points[1])
            case .closeSubpath:
                self.close()
            @unknown default:
                break
            }
        }
    }
}
