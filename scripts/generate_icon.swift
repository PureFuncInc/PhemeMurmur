#!/usr/bin/env swift
import AppKit
import Foundation

// Geometry mirrors Sources/PhemeMurmur/UI/WaveformGeometry.swift. This script runs
// standalone via `swift scripts/generate_icon.swift`, so it cannot import the target.
let heightRatios: [CGFloat] = [0.33, 0.66, 1.0, 0.66, 0.33]
let tallestRatio: CGFloat = 0.54
let barWidthRatio: CGFloat = 0.065
let gapRatio: CGFloat = 0.055

func bars(in size: CGFloat) -> [CGRect] {
    let barWidth = size * barWidthRatio
    let gap = size * gapRatio
    let total = barWidth * CGFloat(heightRatios.count) + gap * CGFloat(heightRatios.count - 1)
    let startX = (size - total) / 2
    return heightRatios.enumerated().map { index, ratio in
        let height = size * tallestRatio * ratio
        let x = startX + CGFloat(index) * (barWidth + gap)
        return CGRect(x: x, y: (size - height) / 2, width: barWidth, height: height)
    }
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let spaceTop = rgb(0.106, 0.137, 0.314)
let spaceBottom = rgb(0.031, 0.043, 0.102)
let cyan = rgb(0.239, 0.910, 1.000)
let violet = rgb(0.482, 0.361, 1.000)
let iceWhite = rgb(0.714, 0.984, 1.000)

// Star dust positions as fractions of the canvas, fixed so every size matches.
let starDust: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
    (0.21, 0.81, 0.0085, 0.75),
    (0.80, 0.74, 0.0065, 0.55),
    (0.75, 0.24, 0.0075, 0.50),
    (0.27, 0.18, 0.0055, 0.45),
]

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let minimal = size <= 32

    // Squircle clip.
    let radius = s * 0.2237
    let clipPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()

    // Deep space radial background.
    let bgGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                colors: [spaceTop, spaceBottom] as CFArray,
                                locations: [0, 1])!
    ctx.drawRadialGradient(bgGradient,
                           startCenter: CGPoint(x: s * 0.5, y: s * 0.62), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.78,
                           options: [.drawsAfterEndLocation])

    if !minimal {
        // Horizon glow band beneath the bars.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.09, color: cyan.copy(alpha: 0.55))
        ctx.setFillColor(cyan.copy(alpha: 0.32)!)
        let band = CGRect(x: s * 0.13, y: s * 0.28, width: s * 0.74, height: s * 0.035)
        ctx.addPath(CGPath(ellipseIn: band, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        // Orbital arc on the right, fading at both ends via a gradient-filled stroke.
        ctx.saveGState()
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: s * 0.5, y: s * 0.5), radius: s * 0.46,
                   startAngle: -.pi / 2.6, endAngle: .pi / 2.6, clockwise: false)
        ctx.addPath(arc.copy(strokingWithWidth: s * 0.017, lineCap: .round,
                             lineJoin: .round, miterLimit: 10))
        ctx.clip()
        let arcGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     colors: [violet, cyan, violet] as CFArray,
                                     locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(arcGradient,
                               start: CGPoint(x: s, y: 0), end: CGPoint(x: s, y: s),
                               options: [])
        ctx.restoreGState()

        // Star dust.
        for star in starDust {
            ctx.setFillColor(rgb(0.812, 0.902, 1.0, Double(star.a)))
            ctx.fillEllipse(in: CGRect(x: s * star.x - s * star.r, y: s * star.y - s * star.r,
                                       width: s * star.r * 2, height: s * star.r * 2))
        }
    }

    // Waveform bars, cyan-to-violet vertical gradient with an outer glow.
    let barPath = CGMutablePath()
    for bar in bars(in: s) {
        barPath.addRoundedRect(in: bar, cornerWidth: bar.width / 2, cornerHeight: bar.width / 2)
    }

    if !minimal {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.05, color: cyan.copy(alpha: 0.7))
        ctx.setFillColor(cyan.copy(alpha: 0.9)!)
        ctx.addPath(barPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.clip()
    let barGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 colors: [violet, cyan, iceWhite] as CFArray,
                                 locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(barGradient,
                           start: CGPoint(x: 0, y: s * 0.2), end: CGPoint(x: 0, y: s * 0.8),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: cgImage)
        .representation(using: .png, properties: [.compressionFactor: 1.0])
}

let iconsetDir = "AppIcon.iconset"
let fm = FileManager.default
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    guard let data = renderIcon(size: size) else {
        print("Failed to render \(name)")
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name).png"))
    print("Generated \(iconsetDir)/\(name).png")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
print("Created Resources/AppIcon.icns")
try? fm.removeItem(atPath: iconsetDir)
print("Done!")
