#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Mark III app icon: a forge-lit arc reactor on a dark plate, inside the macOS
// squircle with a gold hairline rim.
//
// This script runs standalone (`swift scripts/generate_icon.swift`) so it cannot
// import the app target. The palette below therefore duplicates MarkIII.swift —
// keep the two in sync when the colours change.

let gold       = CGColor(srgbRed: 0.878, green: 0.647, blue: 0.290, alpha: 1)  // #E0A54A
let goldBright = CGColor(srgbRed: 1.000, green: 0.851, blue: 0.541, alpha: 1)  // #FFD98A
let arc        = CGColor(srgbRed: 0.549, green: 0.902, blue: 1.000, alpha: 1)  // #8CE6FF

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ c: CGColor, _ alpha: CGFloat) -> CGColor {
    c.copy(alpha: alpha) ?? c
}

func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// The macOS squircle, approximated with a continuous-curvature rounded rect.
func squirclePath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r = min(radius, min(rect.width, rect.height) / 2)
    // Control-point offset that turns the circular corner into the flatter,
    // continuous curve Apple uses. 1.528 is the standard superellipse factor.
    let k = r * (1 - 1 / 1.528)
    p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
               control1: CGPoint(x: rect.maxX - k, y: rect.minY),
               control2: CGPoint(x: rect.maxX, y: rect.minY + k))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    p.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
               control1: CGPoint(x: rect.maxX, y: rect.maxY - k),
               control2: CGPoint(x: rect.maxX - k, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    p.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
               control1: CGPoint(x: rect.minX + k, y: rect.maxY),
               control2: CGPoint(x: rect.minX, y: rect.maxY - k))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    p.addCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
               control1: CGPoint(x: rect.minX, y: rect.minY + k),
               control2: CGPoint(x: rect.minX + k, y: rect.minY))
    p.closeSubpath()
    return p
}

/// Renders the icon at one pixel size.
///
/// Detail drops away as the canvas shrinks, exactly like the design's
/// breakpoints: individual sunburst beams become a crisp spoke ring below 44px,
/// and below 15px only the core and its rim survive.
func renderIcon(size: CGFloat, recording: Bool = false) -> CGImage {
    let s = size
    let ctx = CGContext(data: nil,
                        width: Int(s), height: Int(s),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let center = CGPoint(x: s / 2, y: s / 2)
    let detail = s >= 44
    let mid = s >= 15
    let coreDiameter = s * 0.30
    let tint = recording
        ? CGColor(srgbRed: 1.0, green: 0.302, blue: 0.180, alpha: 1)   // #FF4D2E
        : arc

    // Clip everything to the squircle so the plate edge is the icon's silhouette.
    ctx.saveGState()
    ctx.addPath(squirclePath(rect, radius: s * 0.2237))
    ctx.clip()

    // Cold steel-blue plate, darkening to near black at the corners.
    let bg = CGGradient(colorsSpace: space, colors: [
        srgb(0.071, 0.196, 0.255),   // #123241
        srgb(0.039, 0.086, 0.125),   // #0A1620
        srgb(0.031, 0.031, 0.047),   // #08080C
        srgb(0.020, 0.020, 0.027),   // #050507
    ] as CFArray, locations: [0, 0.42, 0.78, 1])!
    ctx.drawRadialGradient(bg, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: s * 0.72,
                           options: [.drawsAfterEndLocation])

    // Coloured bloom behind the reactor.
    if detail {
        let halo = CGGradient(colorsSpace: space, colors: [
            rgba(tint, 0.2), rgba(tint, 0),
        ] as CFArray, locations: [0, 0.7])!
        ctx.drawRadialGradient(halo, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: s * 0.43, options: [])
    }

    if detail {
        // Sixteen tapered beams, white-hot at the rim and fading inward.
        let count = 16
        let w = s * 0.044
        let length = s * 0.215
        let outerRadius = s * 0.255
        for i in 0..<count {
            let angle = CGFloat(i) * (2 * .pi / CGFloat(count))
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: angle)
            // Bar spans [outerRadius - length, outerRadius] along +y.
            let bar = CGRect(x: -w / 2, y: outerRadius - length, width: w, height: length)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: w / 2, cornerHeight: w / 2,
                               transform: nil))
            ctx.clip()
            let beam = CGGradient(colorsSpace: space, colors: [
                srgb(1, 1, 1, 0.9), goldBright, rgba(gold, 0.15),
            ] as CFArray, locations: [0, 0.55, 1])!
            ctx.drawLinearGradient(beam,
                                   start: CGPoint(x: 0, y: outerRadius),
                                   end: CGPoint(x: 0, y: outerRadius - length),
                                   options: [])
            ctx.restoreGState()
        }
    } else {
        // Small sizes: a crisp spoke ring reads better than 16 thin bars.
        let count = s >= 26 ? 12 : 8
        let step = 2 * CGFloat.pi / CGFloat(count)
        let duty = step * 0.28
        let r1 = s * 0.30
        let r2 = s * 0.46
        ctx.setFillColor(goldBright)
        for i in 0..<count {
            let start = CGFloat(i) * step - duty / 2
            let wedge = CGMutablePath()
            wedge.addArc(center: center, radius: r2,
                         startAngle: start, endAngle: start + duty, clockwise: false)
            wedge.addArc(center: center, radius: r1,
                         startAngle: start + duty, endAngle: start, clockwise: true)
            wedge.closeSubpath()
            ctx.addPath(wedge)
            ctx.fillPath()
        }
    }

    if mid {
        // Outer containment circle in the phase tint.
        ctx.setStrokeColor(rgba(tint, 0.4))
        ctx.setLineWidth(max(1, s * 0.022))
        ctx.addEllipse(in: CGRect(x: center.x - s * 0.31, y: center.y - s * 0.31,
                                  width: s * 0.62, height: s * 0.62))
        ctx.strokePath()

        // Gold ring hugging the beam roots.
        let ringRadius = coreDiameter * 1.62 / 2
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.07, color: rgba(gold, 0.65))
        ctx.setStrokeColor(goldBright)
        ctx.setLineWidth(max(1, s * 0.028))
        ctx.addEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                  width: ringRadius * 2, height: ringRadius * 2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // White-hot core.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.16, color: tint)
    ctx.setFillColor(tint)
    ctx.addEllipse(in: CGRect(x: center.x - coreDiameter / 2, y: center.y - coreDiameter / 2,
                              width: coreDiameter, height: coreDiameter))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - coreDiameter / 2, y: center.y - coreDiameter / 2,
                              width: coreDiameter, height: coreDiameter))
    ctx.clip()
    let core = CGGradient(colorsSpace: space, colors: [
        srgb(1, 1, 1), tint, srgb(0.118, 0.471, 0.627, 0.9), srgb(0.039, 0.118, 0.157, 0.9),
    ] as CFArray, locations: [0.18, 0.52, 0.82, 1])!
    ctx.drawRadialGradient(core, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: coreDiameter / 2,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    ctx.restoreGState()

    // Gold hairline rim, drawn last so nothing paints over it.
    ctx.saveGState()
    let rimWidth = max(1, s * 0.016)
    ctx.addPath(squirclePath(rect.insetBy(dx: rimWidth / 2, dy: rimWidth / 2),
                             radius: s * 0.2237 - rimWidth / 2))
    ctx.setStrokeColor(rgba(gold, 0.7))
    ctx.setLineWidth(rimWidth)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Output

let fm = FileManager.default
let repoRoot = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconsetURL = repoRoot.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

/// (pixel size, iconset filename) — the full set macOS expects.
let variants: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),     (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),     (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),  (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),  (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),  (1024, "icon_512x512@2x.png"),
]

for (size, name) in variants {
    let image = renderIcon(size: size)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(name)")
    }
    try data.write(to: iconsetURL.appendingPathComponent(name))
}

let icnsURL = repoRoot.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(task.terminationStatus)")
}

try? fm.removeItem(at: iconsetURL)
print("Wrote \(icnsURL.path)")
