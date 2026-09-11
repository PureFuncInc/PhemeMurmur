import AppKit
import SwiftUI

/// The single source of truth for the Mark III palette and type. Fixed colours —
/// the app does not follow the system appearance, the armour is always dark.
///
/// Mark III replaces the Deep Space look: gold and crimson on near-black,
/// chamfered plates, scanlines, and an arc-reactor voice core.
enum MarkIII {

    typealias RGB = (r: Double, g: Double, b: Double)

    // MARK: - Palette

    /// Primary gold. Borders, labels, the calm half of most gradients.
    static let gold: RGB        = (0.878, 0.647, 0.290)  // #E0A54A
    /// Bright gold. Highlights, active text, the lit end of gradients.
    static let goldBright: RGB  = (1.000, 0.851, 0.541)  // #FFD98A
    /// Crimson. Selection fills, armour edges, the failure state.
    static let crimson: RGB     = (0.784, 0.063, 0.180)  // #C8102E
    /// Hot orange-red. The recording tint — the most urgent colour in the kit.
    static let hot: RGB         = (1.000, 0.302, 0.180)  // #FF4D2E
    /// Arc cyan. The reactor's core light, and the idle/done tint.
    static let arc: RGB         = (0.549, 0.902, 1.000)  // #8CE6FF
    /// Dimmed tan. Secondary copy and inactive rows.
    static let dim: RGB         = (0.608, 0.576, 0.510)  // #9B9382
    /// Primary body copy.
    static let ink: RGB         = (0.937, 0.906, 0.855)  // #EFE7DA
    /// Text sitting on a gold fill — near-black with a red cast.
    static let onGold: RGB      = (0.086, 0.024, 0.027)  // #160607

    /// Backdrop stops. `shellWarm` is the red-tinted bloom the consoles fade out
    /// of; `shellMid` and `shellDeep` carry it down to black.
    static let shellWarm: RGB   = (0.110, 0.055, 0.071)  // #1C0E12
    static let shellMid: RGB    = (0.043, 0.039, 0.051)  // #0B0A0D
    static let shellDeep: RGB   = (0.027, 0.027, 0.039)  // #07070A

    /// Armour plate fill stops, top-left to bottom-right.
    static let plateTop: RGB    = (0.082, 0.063, 0.059)  // #15100F
    static let plateMid: RGB    = (0.047, 0.043, 0.055)  // #0C0B0E
    static let plateDeep: RGB   = (0.039, 0.039, 0.047)  // #0A0A0C

    // MARK: - Colour accessors

    static func color(_ rgb: RGB, opacity: Double = 1) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    static func nsColor(_ rgb: RGB, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    static func cgColor(_ rgb: RGB, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    // MARK: - Type

    enum Weight {
        case regular, medium, semibold, bold

        var displayFace: String {
            switch self {
            case .regular: return "ChakraPetch-Regular"
            case .medium: return "ChakraPetch-Medium"
            case .semibold: return "ChakraPetch-SemiBold"
            case .bold: return "ChakraPetch-Bold"
            }
        }

        var monoFace: String {
            switch self {
            case .regular: return "JetBrainsMono-Regular"
            case .medium: return "JetBrainsMono-Medium"
            // JetBrains Mono ships no SemiBold in the bundled subset; Bold is the
            // nearest weight and is what the design's 600/700 labels want anyway.
            case .semibold, .bold: return "JetBrainsMono-Bold"
            }
        }

        var systemWeight: NSFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        var swiftUIWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    /// Chakra Petch — the squared-off display face the design is built on.
    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        registerFonts()
        guard hasFace(weight.displayFace) else {
            return .system(size: size, weight: weight.swiftUIWeight)
        }
        return .custom(weight.displayFace, size: size)
    }

    /// JetBrains Mono — every code, status and telemetry label in the design.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        registerFonts()
        guard hasFace(weight.monoFace) else {
            return .system(size: size, weight: weight.swiftUIWeight, design: .monospaced)
        }
        return .custom(weight.monoFace, size: size)
    }

    /// AppKit counterparts, for the menu bar views and the icon generator.
    static func nsFont(_ size: CGFloat, _ weight: Weight = .regular) -> NSFont {
        registerFonts()
        return NSFont(name: weight.displayFace, size: size)
            ?? .systemFont(ofSize: size, weight: weight.systemWeight)
    }

    static func nsMono(_ size: CGFloat, _ weight: Weight = .regular) -> NSFont {
        registerFonts()
        return NSFont(name: weight.monoFace, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight.systemWeight)
    }

    private static func hasFace(_ name: String) -> Bool {
        NSFont(name: name, size: 12) != nil
    }

    // MARK: - Font registration

    private static var fontsRegistered = false

    /// `ATSApplicationFontsPath` covers the packaged app, but registering by URL
    /// as well keeps the look intact when the binary runs straight out of
    /// `.build/`, where there is no bundle Resources directory.
    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Fonts"),
        ].compactMap { $0 }

        for dir in candidates {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            let fonts = files.filter { $0.pathExtension.lowercased() == "ttf" }
            guard !fonts.isEmpty else { continue }
            for url in fonts {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            return
        }
    }

    // MARK: - Backdrops

    /// The console shell: a wide warm bloom off the top-left corner falling away
    /// to black.
    static func consoleBackdrop(diagonal: CGFloat) -> some View {
        RadialGradient(
            colors: [color(shellWarm), color(shellMid), color(shellDeep)],
            center: UnitPoint(x: 0.18, y: -0.1),
            startRadius: 0, endRadius: diagonal
        )
    }

    /// The boot shell: the bloom sits centred at the top, behind the reactor.
    static func bootBackdrop(diagonal: CGFloat) -> some View {
        RadialGradient(
            colors: [color((0.133, 0.063, 0.059)), color((0.047, 0.039, 0.051)),
                     color((0.031, 0.031, 0.039))],
            center: UnitPoint(x: 0.5, y: 0.06),
            startRadius: 0, endRadius: diagonal
        )
    }

    /// The fill inside an armour plate.
    static var plateFill: LinearGradient {
        LinearGradient(colors: [color(plateTop), color(plateMid), color(plateDeep)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The 1px gradient edge that wraps an armour plate.
    static var plateEdge: LinearGradient {
        LinearGradient(colors: [color(gold, opacity: 0.55),
                                color(crimson, opacity: 0.35),
                                color(gold, opacity: 0.18)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The lit gradient used on primary buttons and active chips.
    static var goldSlab: LinearGradient {
        LinearGradient(colors: [color(goldBright), color(gold)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Chamfer

/// The signature silhouette: top-left and bottom-right corners sliced at 45°.
struct Chamfer: InsettableShape {
    var cut: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        // Clamp so an oversized cut cannot fold the polygon inside out.
        let c = min(cut, min(r.width, r.height) / 2)
        guard c > 0, r.width > 0, r.height > 0 else { return Path(r) }
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Chamfer {
        Chamfer(cut: max(cut - amount, 1), insetAmount: insetAmount + amount)
    }
}

extension MarkIII {
    /// AppKit path for the same silhouette, for the menu bar's custom item views
    /// and the icon generator. AppKit is y-up, so the cuts land on the opposite
    /// corners from the SwiftUI version to read the same on screen.
    static func chamferPath(in rect: CGRect, cut: CGFloat, inset: CGFloat = 0) -> CGPath {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = min(cut, min(r.width, r.height) / 2)
        guard c > 0, r.width > 0, r.height > 0 else {
            return CGPath(rect: r, transform: nil)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        path.closeSubpath()
        return path
    }
}
