#!/usr/bin/env swift
import AppKit
import Foundation

func renderEmoji(_ emoji: String, size: Int) -> Data? {
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let fontSize = CGFloat(size) * 0.85
    let font = CTFontCreateWithName("AppleColorEmoji" as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font as Any
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let strSize = str.size()
    let x = (CGFloat(size) - strSize.width) / 2
    let y = (CGFloat(size) - strSize.height) / 2
    str.draw(at: NSPoint(x: x, y: y))

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else { return nil }
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    return bitmapRep.representation(using: .png, properties: [.compressionFactor: 1.0])
}

let emoji = "🗣️"
let iconsetDir = "AppIcon.iconset"
let fm = FileManager.default

try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    guard let data = renderEmoji(emoji, size: size) else {
        print("Failed to render \(name)")
        exit(1)
    }
    let path = "\(iconsetDir)/\(name).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("Generated \(path)")
}

let iconutil = Process()
iconutil.launchPath = "/usr/bin/iconutil"
iconutil.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
iconutil.launch()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
print("Created Resources/AppIcon.icns")

try? fm.removeItem(atPath: iconsetDir)
print("Done!")
