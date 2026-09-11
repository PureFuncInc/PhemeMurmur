import AppKit
import SwiftUI

/// The single source of truth for the Deep Space palette. Fixed colours — the
/// app does not follow the system appearance, the panels are always dark.
enum DeepSpace {

    typealias RGB = (r: Double, g: Double, b: Double)

    static let spaceVoidTop: RGB    = (0.106, 0.137, 0.314)  // #1B2350
    static let spaceVoidBottom: RGB = (0.031, 0.043, 0.102)  // #080B1A
    static let auroraCyan: RGB      = (0.239, 0.910, 1.000)  // #3DE8FF
    static let auroraViolet: RGB    = (0.482, 0.361, 1.000)  // #7B5CFF
    static let nebulaPink: RGB      = (1.000, 0.431, 0.780)  // #FF6EC7
    static let starDust: RGB        = (0.604, 0.643, 0.784)  // #9AA4C8

    static func nsColor(_ rgb: RGB, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    static func color(_ rgb: RGB, opacity: Double = 1) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    /// Corner radius of a macOS squircle for a given edge length.
    static func cornerRadius(for size: CGFloat) -> CGFloat {
        size * 0.2237
    }
}
