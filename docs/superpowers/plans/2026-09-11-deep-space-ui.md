# Deep Space UI 改版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 PhemeMurmur 的 App Icon 與三個使用者介面（設定視窗、錄音監聽面板、Onboarding）換成統一的 Deep Space 視覺語言。

**Architecture:** 新增 `Sources/PhemeMurmur/UI/` 放全部視覺層。可測的幾何、音量、狀態、權限判斷都抽成純函式並以 XCTest 覆蓋；SwiftUI View 本身不做自動化測試，由 `NSHostingView` 掛進既有的 AppKit 殼。錄音、轉錄、貼上、hotkey 的核心邏輯完全不動。

**Tech Stack:** Swift 5.9、SwiftUI + AppKit（`NSHostingView` / `NSPanel`）、Core Graphics（icon 生成）、AVFoundation、XCTest。零第三方依賴。

**Spec:** `docs/superpowers/specs/2026-09-11-deep-space-ui-design.md`

## Global Constraints

- 部署目標 `.macOS(.v13)`（`Package.swift` 既有設定，不得提高）。
- 零第三方依賴，只用 Apple frameworks。
- 色票固定：`spaceVoid` `#080B1A`→`#0E1230`、`auroraCyan` `#3DE8FF`、`auroraViolet` `#7B5CFF`、`nebulaPink` `#FF6EC7`、`starDust` `#9AA4C8`。
- 不做淺色主題，不隨系統外觀切換配色。
- 所有面板無標題列、圓角、半透明，不呈現傳統視窗外觀。
- 使用者可見文字一律繁體中文。
- 每個 task 結束都必須 `swift build` 通過再 commit。

---

### Task 1: 視覺基礎（色票 + 波形幾何）

**Files:**
- Create: `Sources/PhemeMurmur/UI/DeepSpace.swift`
- Create: `Sources/PhemeMurmur/UI/WaveformGeometry.swift`
- Test: `Tests/PhemeMurmurTests/WaveformGeometryTests.swift`

**Interfaces:**
- Consumes: 無
- Produces:
  - `enum DeepSpace` 靜態常數：`spaceVoidTop/spaceVoidBottom/auroraCyan/auroraViolet/nebulaPink/starDust`，型別皆為 `(r: Double, g: Double, b: Double)`，另有 `static func nsColor(_ rgb:) -> NSColor` 與 `static func color(_ rgb:) -> Color`
  - `enum WaveformGeometry`：`static let heightRatios: [CGFloat]`、`static func bars(in size: CGFloat) -> [CGRect]`、`static func detail(for size: CGFloat) -> Detail`、`enum Detail { case full, minimal }`

- [ ] **Step 1: 寫失敗的測試**

建立 `Tests/PhemeMurmurTests/WaveformGeometryTests.swift`：

```swift
import XCTest
@testable import PhemeMurmur

final class WaveformGeometryTests: XCTestCase {

    func testFiveBars() {
        XCTAssertEqual(WaveformGeometry.bars(in: 1024).count, 5)
    }

    func testMiddleBarIsTallest() {
        let bars = WaveformGeometry.bars(in: 1024)
        let tallest = bars.max(by: { $0.height < $1.height })
        XCTAssertEqual(tallest, bars[2])
    }

    func testHeightsAreSymmetric() {
        let bars = WaveformGeometry.bars(in: 1024)
        XCTAssertEqual(bars[0].height, bars[4].height, accuracy: 0.01)
        XCTAssertEqual(bars[1].height, bars[3].height, accuracy: 0.01)
    }

    func testBarsAreVerticallyCentered() {
        let size: CGFloat = 1024
        for bar in WaveformGeometry.bars(in: size) {
            XCTAssertEqual(bar.midY, size / 2, accuracy: 0.01)
        }
    }

    func testBarsStayInsideCanvas() {
        let size: CGFloat = 1024
        for bar in WaveformGeometry.bars(in: size) {
            XCTAssertGreaterThanOrEqual(bar.minX, 0)
            XCTAssertGreaterThanOrEqual(bar.minY, 0)
            XCTAssertLessThanOrEqual(bar.maxX, size)
            XCTAssertLessThanOrEqual(bar.maxY, size)
        }
    }

    func testBarsScaleProportionally() {
        let small = WaveformGeometry.bars(in: 256)
        let large = WaveformGeometry.bars(in: 1024)
        XCTAssertEqual(large[2].height, small[2].height * 4, accuracy: 0.01)
    }

    func testDetailIsMinimalAtOrBelow32() {
        XCTAssertEqual(WaveformGeometry.detail(for: 16), .minimal)
        XCTAssertEqual(WaveformGeometry.detail(for: 32), .minimal)
    }

    func testDetailIsFullAbove32() {
        XCTAssertEqual(WaveformGeometry.detail(for: 64), .full)
        XCTAssertEqual(WaveformGeometry.detail(for: 1024), .full)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter WaveformGeometryTests`
Expected: 編譯失敗，`cannot find 'WaveformGeometry' in scope`

- [ ] **Step 3: 實作 `WaveformGeometry`**

建立 `Sources/PhemeMurmur/UI/WaveformGeometry.swift`：

```swift
import CoreGraphics

/// Shared geometry for the five-bar waveform used by the app icon, the menu bar
/// template image and the recording HUD. All values are expressed as a fraction
/// of the canvas edge length so a single definition scales to every size.
enum WaveformGeometry {

    enum Detail {
        /// Full artwork: background, glow, star dust, orbital arc.
        case full
        /// Small sizes: background and bars only.
        case minimal
    }

    /// Bar heights as a fraction of the canvas edge, low-mid-high-mid-low.
    static let heightRatios: [CGFloat] = [0.33, 0.66, 1.0, 0.66, 0.33]

    /// Tallest bar occupies this fraction of the canvas edge.
    private static let tallestRatio: CGFloat = 0.54
    private static let barWidthRatio: CGFloat = 0.065
    private static let gapRatio: CGFloat = 0.055

    static func bars(in size: CGFloat) -> [CGRect] {
        let barWidth = size * barWidthRatio
        let gap = size * gapRatio
        let totalWidth = barWidth * CGFloat(heightRatios.count)
            + gap * CGFloat(heightRatios.count - 1)
        let startX = (size - totalWidth) / 2

        return heightRatios.enumerated().map { index, ratio in
            let height = size * tallestRatio * ratio
            let x = startX + CGFloat(index) * (barWidth + gap)
            let y = (size - height) / 2
            return CGRect(x: x, y: y, width: barWidth, height: height)
        }
    }

    static func detail(for size: CGFloat) -> Detail {
        size <= 32 ? .minimal : .full
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter WaveformGeometryTests`
Expected: 8 個測試全部 PASS

- [ ] **Step 5: 實作色票**

建立 `Sources/PhemeMurmur/UI/DeepSpace.swift`：

```swift
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
```

- [ ] **Step 6: 建置並跑全部測試**

Run: `swift build && swift test`
Expected: build 成功，所有測試 PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/PhemeMurmur/UI/DeepSpace.swift \
        Sources/PhemeMurmur/UI/WaveformGeometry.swift \
        Tests/PhemeMurmurTests/WaveformGeometryTests.swift
git commit -m "feat(ui): add Deep Space palette and shared waveform geometry"
```

---

### Task 2: App Icon 以 Core Graphics 重繪

**Files:**
- Rewrite: `scripts/generate_icon.swift`
- Modify: `Sources/PhemeMurmur/main.swift:657-697`（`updateIcon()` / `setIcon()`）
- Create: `Sources/PhemeMurmur/UI/MenuBarIcon.swift`

**Interfaces:**
- Consumes: `WaveformGeometry.bars(in:)`、`WaveformGeometry.detail(for:)`、`DeepSpace`
- Produces: `enum MenuBarIcon { static func waveformTemplate(pointSize: CGFloat) -> NSImage }`

腳本以 `swift scripts/generate_icon.swift` 獨立執行，不屬於 package target，因此不能 `import PhemeMurmur`。波形比例常數在腳本內重複一份，並加註解指向 `WaveformGeometry`。

- [ ] **Step 1: 重寫 icon 生成腳本**

以下內容完整取代 `scripts/generate_icon.swift`：

```swift
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
```

- [ ] **Step 2: 產生 icon 並目視檢查**

Run:
```bash
make icon
qlmanage -p Resources/AppIcon.icns >/dev/null 2>&1 &
```
Expected: 10 個尺寸全部 `Generated`，最後印出 `Created Resources/AppIcon.icns`。預覽中 1024px 看得到深空底、發光波形、右側軌道弧與四顆星塵；16px 只剩底色與波形且輪廓清楚。

- [ ] **Step 3: 實作 menu bar template icon**

建立 `Sources/PhemeMurmur/UI/MenuBarIcon.swift`：

```swift
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
```

- [ ] **Step 4: 把 idle 狀態換成新 glyph**

在 `Sources/PhemeMurmur/main.swift` 的 `updateIcon()` 中，把 idle 分支從 SF Symbol 改為新 glyph：

```swift
    private func updateIcon() {
        switch state {
        case .idle:
            setWaveformIcon()
        case .recording:
            setIcon(symbolName: "record.circle", color: .systemRed)
        case .transcribing:
            setIcon(symbolName: "text.bubble", color: .systemBlue)
        }
    }

    private func setWaveformIcon() {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarIcon.waveformTemplate()
        button.title = ""
    }
```

`setIcon(symbolName:color:)` 其餘部分保持原樣，recording / transcribing / error 三個狀態繼續使用既有的 SF Symbol 路徑。

- [ ] **Step 5: 建置、跑測試、目視確認 menu bar**

Run: `swift build && swift test && make install`
Expected: build 與測試通過；app 啟動後 menu bar 顯示五條波形（不是 🗣️ 也不是 SF Symbol 的 `waveform`），且在淺色與深色 menu bar 下都自動變色。

- [ ] **Step 6: Commit**

```bash
git add scripts/generate_icon.swift Resources/AppIcon.icns \
        Sources/PhemeMurmur/UI/MenuBarIcon.swift Sources/PhemeMurmur/main.swift
git commit -m "feat(icon): redraw app icon and menu bar glyph with Deep Space waveform"
```

---

### Task 3: 即時音量輸出

**Files:**
- Create: `Sources/PhemeMurmur/UI/AudioLevelMeter.swift`
- Modify: `Sources/PhemeMurmur/AudioRecorder.swift`
- Test: `Tests/PhemeMurmurTests/AudioLevelMeterTests.swift`

**Interfaces:**
- Consumes: 無
- Produces:
  - `enum AudioLevelMeter { static func segmentLevels(_ samples: [Float], segments: Int) -> [Float] }` — 回傳長度恰為 `segments` 的陣列，每個值為該段的 RMS 經 clamp 到 `0...1`
  - `AudioRecorder.onLevel: (([Float]) -> Void)?` — 錄音期間在主執行緒回拋 15 段音量，節流至約 30Hz

- [ ] **Step 1: 寫失敗的測試**

建立 `Tests/PhemeMurmurTests/AudioLevelMeterTests.swift`：

```swift
import XCTest
@testable import PhemeMurmur

final class AudioLevelMeterTests: XCTestCase {

    func testReturnsRequestedSegmentCount() {
        let samples = [Float](repeating: 0.5, count: 1024)
        XCTAssertEqual(AudioLevelMeter.segmentLevels(samples, segments: 15).count, 15)
    }

    func testSilenceProducesZeros() {
        let samples = [Float](repeating: 0, count: 1024)
        for level in AudioLevelMeter.segmentLevels(samples, segments: 15) {
            XCTAssertEqual(level, 0, accuracy: 0.0001)
        }
    }

    func testFullScaleProducesOne() {
        let samples = [Float](repeating: 1.0, count: 1024)
        for level in AudioLevelMeter.segmentLevels(samples, segments: 15) {
            XCTAssertEqual(level, 1.0, accuracy: 0.0001)
        }
    }

    func testLevelsAreClampedToUnitRange() {
        let samples = [Float](repeating: 4.0, count: 1024)
        for level in AudioLevelMeter.segmentLevels(samples, segments: 15) {
            XCTAssertLessThanOrEqual(level, 1.0)
            XCTAssertGreaterThanOrEqual(level, 0.0)
        }
    }

    func testLoudSegmentReadsHigherThanQuietSegment() {
        var samples = [Float](repeating: 0.01, count: 1000)
        for i in 0..<100 { samples[i] = 0.9 }
        let levels = AudioLevelMeter.segmentLevels(samples, segments: 10)
        XCTAssertGreaterThan(levels[0], levels[5])
    }

    func testEmptyInputProducesZeros() {
        let levels = AudioLevelMeter.segmentLevels([], segments: 15)
        XCTAssertEqual(levels.count, 15)
        XCTAssertEqual(levels.reduce(0, +), 0, accuracy: 0.0001)
    }

    func testFewerSamplesThanSegmentsStillProducesFullArray() {
        let levels = AudioLevelMeter.segmentLevels([0.5, 0.5, 0.5], segments: 15)
        XCTAssertEqual(levels.count, 15)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter AudioLevelMeterTests`
Expected: 編譯失敗，`cannot find 'AudioLevelMeter' in scope`

- [ ] **Step 3: 實作 `AudioLevelMeter`**

建立 `Sources/PhemeMurmur/UI/AudioLevelMeter.swift`：

```swift
import Foundation

/// Turns a PCM buffer into a fixed number of amplitude values, one per corona
/// beam in the recording HUD. Time-sliced RMS, not a spectrum — enough visual
/// variation without pulling in an FFT.
enum AudioLevelMeter {

    static func segmentLevels(_ samples: [Float], segments: Int) -> [Float] {
        guard segments > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: segments) }

        let chunk = max(1, samples.count / segments)
        return (0..<segments).map { index in
            let start = min(index * chunk, samples.count)
            let end = min(start + chunk, samples.count)
            guard start < end else { return 0 }

            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            let rms = (sum / Float(end - start)).squareRoot()
            return min(max(rms, 0), 1)
        }
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter AudioLevelMeterTests`
Expected: 7 個測試全部 PASS

- [ ] **Step 5: 在 `AudioRecorder` 加上 level callback**

在 `Sources/PhemeMurmur/AudioRecorder.swift` 的類別宣告區加入屬性：

```swift
    /// Emits `beamCount` amplitude values on the main thread while recording,
    /// throttled to roughly 30Hz. Nil when nothing is observing.
    var onLevel: (([Float]) -> Void)?

    private static let beamCount = 15
    private static let levelInterval: TimeInterval = 1.0 / 30.0
    private var lastLevelEmit: TimeInterval = 0
```

在 `installTap` 的 closure 內，`self.buffers.append(convertedBuffer)` 之後、closure 結尾之前插入：

```swift
            guard self.onLevel != nil else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastLevelEmit >= Self.levelInterval else { return }
            self.lastLevelEmit = now

            guard let channel = convertedBuffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel,
                                                    count: Int(convertedBuffer.frameLength)))
            let levels = AudioLevelMeter.segmentLevels(samples, segments: Self.beamCount)
            DispatchQueue.main.async { self.onLevel?(levels) }
```

在 `startRecording()` 開頭、`buffers.removeAll()` 附近重置節流狀態：

```swift
        lastLevelEmit = 0
```

- [ ] **Step 6: 建置並跑全部測試**

Run: `swift build && swift test`
Expected: build 成功，所有測試 PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/PhemeMurmur/UI/AudioLevelMeter.swift \
        Sources/PhemeMurmur/AudioRecorder.swift \
        Tests/PhemeMurmurTests/AudioLevelMeterTests.swift
git commit -m "feat(audio): emit throttled segment levels during recording"
```

---

### Task 4: 錄音監聽面板（日冕光束 HUD）

**Files:**
- Create: `Sources/PhemeMurmur/UI/FloatingPanel.swift`
- Create: `Sources/PhemeMurmur/UI/HUDPhase.swift`
- Create: `Sources/PhemeMurmur/UI/NebulaHUDView.swift`
- Create: `Sources/PhemeMurmur/UI/RecordingHUDController.swift`
- Modify: `Sources/PhemeMurmur/main.swift`
- Test: `Tests/PhemeMurmurTests/HUDPhaseTests.swift`

**Interfaces:**
- Consumes: `DeepSpace`、`AudioRecorder.onLevel`
- Produces:
  - `enum HUDPhase { case recording(elapsed: TimeInterval), transcribing(provider: String), done, failed(message: String) }`
  - `HUDPhase.presentation` → `struct HUDPresentation { let coreTint: DeepSpace.RGB; let capsuleText: String; let ringSpeed: Double; let autoDismissAfter: TimeInterval? }`
  - `final class RecordingHUDController { func show(_ phase: HUDPhase); func update(levels: [Float]); func hide() }`

- [ ] **Step 1: 寫失敗的測試**

建立 `Tests/PhemeMurmurTests/HUDPhaseTests.swift`：

```swift
import XCTest
@testable import PhemeMurmur

final class HUDPhaseTests: XCTestCase {

    func testRecordingCapsuleShowsElapsedAndEscHint() {
        let p = HUDPhase.recording(elapsed: 7).presentation
        XCTAssertEqual(p.capsuleText, "LISTENING · 0:07 · ESC")
    }

    func testRecordingFormatsMinutes() {
        let p = HUDPhase.recording(elapsed: 75).presentation
        XCTAssertEqual(p.capsuleText, "LISTENING · 1:15 · ESC")
    }

    func testRecordingNeverAutoDismisses() {
        XCTAssertNil(HUDPhase.recording(elapsed: 3).presentation.autoDismissAfter)
    }

    func testTranscribingShowsProviderAndSpinsFaster() {
        let recording = HUDPhase.recording(elapsed: 3).presentation
        let p = HUDPhase.transcribing(provider: "OpenAI").presentation
        XCTAssertEqual(p.capsuleText, "TRANSCRIBING · OPENAI")
        // ringSpeed is seconds per rotation, so faster means a smaller value.
        XCTAssertLessThan(p.ringSpeed, recording.ringSpeed)
        XCTAssertNil(p.autoDismissAfter)
    }

    func testDoneDismissesAfterShortDelay() {
        let p = HUDPhase.done.presentation
        XCTAssertEqual(p.capsuleText, "DONE")
        XCTAssertEqual(p.autoDismissAfter, 1.2)
    }

    func testFailedShowsMessageAndLingersLonger() {
        let p = HUDPhase.failed(message: "沒有網路").presentation
        XCTAssertEqual(p.capsuleText, "沒有網路")
        XCTAssertEqual(p.autoDismissAfter, 3.0)
    }

    func testFailedTintDiffersFromRecordingTint() {
        let failed = HUDPhase.failed(message: "x").presentation.coreTint
        let recording = HUDPhase.recording(elapsed: 1).presentation.coreTint
        XCTAssertNotEqual(failed.r, recording.r, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter HUDPhaseTests`
Expected: 編譯失敗，`cannot find 'HUDPhase' in scope`

- [ ] **Step 3: 實作 `HUDPhase`**

建立 `Sources/PhemeMurmur/UI/HUDPhase.swift`：

```swift
import Foundation

struct HUDPresentation {
    let coreTint: DeepSpace.RGB
    let capsuleText: String
    /// Seconds per full rotation of the orbital ring.
    let ringSpeed: Double
    /// Nil means the HUD stays until the next phase arrives.
    let autoDismissAfter: TimeInterval?
}

enum HUDPhase {
    case recording(elapsed: TimeInterval)
    case transcribing(provider: String)
    case done
    case failed(message: String)

    var presentation: HUDPresentation {
        switch self {
        case .recording(let elapsed):
            return HUDPresentation(
                coreTint: DeepSpace.auroraViolet,
                capsuleText: "LISTENING · \(Self.clock(elapsed)) · ESC",
                ringSpeed: 4.0,
                autoDismissAfter: nil
            )
        case .transcribing(let provider):
            return HUDPresentation(
                coreTint: DeepSpace.auroraCyan,
                capsuleText: "TRANSCRIBING · \(provider.uppercased())",
                ringSpeed: 1.4,
                autoDismissAfter: nil
            )
        case .done:
            return HUDPresentation(
                coreTint: DeepSpace.auroraCyan,
                capsuleText: "DONE",
                ringSpeed: 4.0,
                autoDismissAfter: 1.2
            )
        case .failed(let message):
            return HUDPresentation(
                coreTint: DeepSpace.nebulaPink,
                capsuleText: message,
                ringSpeed: 6.0,
                autoDismissAfter: 3.0
            )
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter HUDPhaseTests`
Expected: 7 個測試全部 PASS

- [ ] **Step 5: 實作浮動面板容器**

建立 `Sources/PhemeMurmur/UI/FloatingPanel.swift`：

```swift
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

    /// Centres the panel horizontally, 140pt above the bottom of the active screen.
    func positionAtBottomCentre() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.minY + 140
        )
        setFrameOrigin(origin)
    }
}
```

- [ ] **Step 6: 實作日冕光束視圖**

建立 `Sources/PhemeMurmur/UI/NebulaHUDView.swift`：

```swift
import SwiftUI

/// The recording HUD: a breathing nebula core, corona beams driven by live audio
/// levels, one slow orbital ring, and a detached status capsule underneath.
struct NebulaHUDView: View {

    let phase: HUDPhase
    /// One value per beam, 0...1. All zeros renders a calm idle corona.
    let levels: [Float]
    /// Onboarding reuses the core as decoration and hides the status capsule.
    var showsCapsule: Bool = true

    private let beamCount = 15
    private let systemSize: CGFloat = 150

    @State private var ringAngle: Double = 0
    @State private var breathe = false

    private var presentation: HUDPresentation { phase.presentation }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                corona
                ring
                core
            }
            .frame(width: systemSize, height: systemSize)

            if showsCapsule { capsule }
        }
        .padding(20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.linear(duration: presentation.ringSpeed).repeatForever(autoreverses: false)) {
                ringAngle = 360
            }
        }
    }

    private var corona: some View {
        ZStack {
            ForEach(0..<beamCount, id: \.self) { index in
                let level = CGFloat(index < levels.count ? levels[index] : 0)
                let length = 14 + level * 44
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                DeepSpace.color(DeepSpace.auroraCyan, opacity: 0.95),
                                DeepSpace.color(DeepSpace.auroraViolet, opacity: 0.35),
                                .clear,
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 7, height: length)
                    .blur(radius: 3)
                    .offset(y: -(28 + length / 2))
                    .rotationEffect(.degrees(Double(index) / Double(beamCount) * 360))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
    }

    private var ring: some View {
        Circle()
            .trim(from: 0, to: 0.62)
            .stroke(
                AngularGradient(
                    colors: [
                        DeepSpace.color(DeepSpace.auroraCyan),
                        DeepSpace.color(DeepSpace.auroraViolet, opacity: 0.6),
                        .clear,
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
            )
            .frame(width: 104, height: 104)
            .rotationEffect(.degrees(ringAngle))
    }

    private var core: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        DeepSpace.color(presentation.coreTint),
                        DeepSpace.color(DeepSpace.spaceVoidTop),
                        DeepSpace.color(DeepSpace.spaceVoidBottom),
                    ],
                    center: UnitPoint(x: 0.42, y: 0.36),
                    startRadius: 2, endRadius: 44
                )
            )
            .frame(width: 56, height: 56)
            .overlay(Circle().strokeBorder(DeepSpace.color(DeepSpace.starDust, opacity: 0.28), lineWidth: 1))
            .shadow(color: DeepSpace.color(presentation.coreTint, opacity: 0.55), radius: 22)
            .scaleEffect(breathe ? 1.06 : 0.94)
    }

    private var capsule: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(DeepSpace.color(DeepSpace.auroraCyan))
                .frame(width: 5, height: 5)
                .shadow(color: DeepSpace.color(DeepSpace.auroraCyan), radius: 4)
            Text(presentation.capsuleText)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .kerning(1.1)
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(DeepSpace.color(DeepSpace.spaceVoidBottom, opacity: 0.6)))
                .overlay(Capsule().strokeBorder(DeepSpace.color(DeepSpace.starDust, opacity: 0.22), lineWidth: 1))
        )
    }
}
```

- [ ] **Step 7: 實作 HUD 控制器**

建立 `Sources/PhemeMurmur/UI/RecordingHUDController.swift`：

```swift
import AppKit
import SwiftUI

/// Owns the floating HUD panel: shows it, feeds it audio levels, and hides it
/// after phases that carry an auto-dismiss delay.
final class RecordingHUDController {

    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<NebulaHUDView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var phase: HUDPhase = .done
    private var levels: [Float] = Array(repeating: 0, count: 15)

    func show(_ phase: HUDPhase) {
        dismissWorkItem?.cancel()
        self.phase = phase

        let panel = existingPanel()
        render()
        panel.positionAtBottomCentre()
        panel.orderFrontRegardless()

        if let delay = phase.presentation.autoDismissAfter {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func update(levels: [Float]) {
        self.levels = levels
        render()
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        levels = Array(repeating: 0, count: 15)
    }

    private func existingPanel() -> FloatingPanel {
        if let panel { return panel }
        let created = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 210))
        let hosting = NSHostingView(rootView: NebulaHUDView(phase: phase, levels: levels))
        created.contentView = hosting
        panel = created
        hostingView = hosting
        return created
    }

    private func render() {
        hostingView?.rootView = NebulaHUDView(phase: phase, levels: levels)
    }
}
```

- [ ] **Step 8: 接進 `main.swift`**

在 `AppDelegate` 的屬性區加入：

```swift
    private let hud = RecordingHUDController()
    private var recordingStartedAt: Date?
    private var hudTickTimer: Timer?
```

在 `startRecording()` 內，實際開始錄音成功之後加入：

```swift
        recordingStartedAt = Date()
        audioRecorder.onLevel = { [weak self] levels in
            self?.hud.update(levels: levels)
        }
        hud.show(.recording(elapsed: 0))
        hudTickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let started = self.recordingStartedAt else { return }
            self.hud.show(.recording(elapsed: Date().timeIntervalSince(started)))
        }
```

在 `stopRecordingAndTranscribe()` 開頭加入：

```swift
        hudTickTimer?.invalidate()
        hudTickTimer = nil
        recordingStartedAt = nil
        audioRecorder.onLevel = nil
        hud.show(.transcribing(provider: activeProviderName))
```

在該函式轉錄成功的分支（貼上完成後）加入 `hud.show(.done)`，在失敗分支加入 `hud.show(.failed(message: Self.truncate(errorMessage)))`，其中 `errorMessage` 為該分支既有的錯誤字串。

在 `handleCancel()` 內加入：

```swift
        hudTickTimer?.invalidate()
        hudTickTimer = nil
        recordingStartedAt = nil
        audioRecorder.onLevel = nil
        hud.hide()
```

- [ ] **Step 9: 建置、測試、實機驗收**

Run: `swift build && swift test && make install`
Expected: build 與測試通過。按快捷鍵後螢幕底部中央出現星雲球 HUD，光束隨說話強弱伸縮；HUD 不搶焦點（正在打字的視窗仍保有游標）、點不到也擋不住底下的內容；停止後轉為 TRANSCRIBING，完成後約 1.2 秒消失；按 Esc 立即消失。

- [ ] **Step 10: Commit**

```bash
git add Sources/PhemeMurmur/UI/FloatingPanel.swift \
        Sources/PhemeMurmur/UI/HUDPhase.swift \
        Sources/PhemeMurmur/UI/NebulaHUDView.swift \
        Sources/PhemeMurmur/UI/RecordingHUDController.swift \
        Sources/PhemeMurmur/main.swift \
        Tests/PhemeMurmurTests/HUDPhaseTests.swift
git commit -m "feat(ui): add floating nebula recording HUD"
```

---

### Task 5: 權限狀態查詢

**Files:**
- Create: `Sources/PhemeMurmur/UI/PermissionStatus.swift`
- Test: `Tests/PhemeMurmurTests/PermissionStatusTests.swift`

**Interfaces:**
- Consumes: 無
- Produces:
  - `enum PermissionKind { case accessibility, microphone }`（含 `var title: String`、`var detail: String`、`var settingsURL: URL`）
  - `struct PermissionItem { let kind: PermissionKind; let granted: Bool }`
  - `enum PermissionStatus { static func items(accessibility: Bool, microphone: AVAuthorizationStatus) -> [PermissionItem]; static func current() -> [PermissionItem]; static func openSettings(for kind: PermissionKind) }`

- [ ] **Step 1: 寫失敗的測試**

建立 `Tests/PhemeMurmurTests/PermissionStatusTests.swift`：

```swift
import XCTest
import AVFoundation
@testable import PhemeMurmur

final class PermissionStatusTests: XCTestCase {

    func testReturnsBothPermissionsInFixedOrder() {
        let items = PermissionStatus.items(accessibility: false, microphone: .notDetermined)
        XCTAssertEqual(items.map(\.kind), [.accessibility, .microphone])
    }

    func testAccessibilityGrantedIsReflected() {
        let items = PermissionStatus.items(accessibility: true, microphone: .notDetermined)
        XCTAssertTrue(items[0].granted)
    }

    func testMicrophoneAuthorizedIsGranted() {
        let items = PermissionStatus.items(accessibility: false, microphone: .authorized)
        XCTAssertTrue(items[1].granted)
    }

    func testMicrophoneDeniedIsNotGranted() {
        let items = PermissionStatus.items(accessibility: false, microphone: .denied)
        XCTAssertFalse(items[1].granted)
    }

    func testMicrophoneRestrictedIsNotGranted() {
        let items = PermissionStatus.items(accessibility: false, microphone: .restricted)
        XCTAssertFalse(items[1].granted)
    }

    func testEachKindHasChineseTitle() {
        XCTAssertEqual(PermissionKind.accessibility.title, "輔助使用")
        XCTAssertEqual(PermissionKind.microphone.title, "麥克風")
    }

    func testSettingsURLsPointAtPrivacyPanes() {
        XCTAssertEqual(PermissionKind.accessibility.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(PermissionKind.microphone.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter PermissionStatusTests`
Expected: 編譯失敗，`cannot find 'PermissionStatus' in scope`

- [ ] **Step 3: 實作 `PermissionStatus`**

建立 `Sources/PhemeMurmur/UI/PermissionStatus.swift`：

```swift
import AppKit
import AVFoundation

enum PermissionKind {
    case accessibility
    case microphone

    var title: String {
        switch self {
        case .accessibility: return "輔助使用"
        case .microphone: return "麥克風"
        }
    }

    var detail: String {
        switch self {
        case .accessibility: return "監聽快捷鍵並把文字貼進其他 app"
        case .microphone: return "錄下你的聲音以進行轉錄"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        }
    }
}

struct PermissionItem {
    let kind: PermissionKind
    let granted: Bool
}

enum PermissionStatus {

    static func items(accessibility: Bool, microphone: AVAuthorizationStatus) -> [PermissionItem] {
        [
            PermissionItem(kind: .accessibility, granted: accessibility),
            PermissionItem(kind: .microphone, granted: microphone == .authorized),
        ]
    }

    static func current() -> [PermissionItem] {
        items(
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    static func openSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter PermissionStatusTests`
Expected: 7 個測試全部 PASS

- [ ] **Step 5: 建置並跑全部測試**

Run: `swift build && swift test`
Expected: build 成功，所有測試 PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/PhemeMurmur/UI/PermissionStatus.swift \
        Tests/PhemeMurmurTests/PermissionStatusTests.swift
git commit -m "feat(ui): add permission status helper"
```

---

### Task 6: 設定視窗（側邊欄五分頁）與選單瘦身

**Files:**
- Create: `Sources/PhemeMurmur/UI/SettingsTab.swift`
- Create: `Sources/PhemeMurmur/UI/SettingsStore.swift`
- Create: `Sources/PhemeMurmur/UI/SettingsView.swift`
- Create: `Sources/PhemeMurmur/UI/SettingsWindowController.swift`
- Modify: `Sources/PhemeMurmur/main.swift`（`setupApp()` 選單建構、移除 `rebuildProviderSubmenu` / `rebuildPromptSubmenu` / `rebuildHotkeySubmenu` / `runAPIKeyPrompt` / `setAPIKeyForActive` 及其選單項）
- Test: `Tests/PhemeMurmurTests/SettingsTabTests.swift`

**Interfaces:**
- Consumes: `Config`、`PermissionStatus`、`DeepSpace`、`HotkeyKey`
- Produces:
  - `enum SettingsTab: CaseIterable { case transcription, hotkey, promptTemplate, general, diagnostics }`（含 `var title: String`、`var symbolName: String`）
  - `final class SettingsStore: ObservableObject` — 發佈 `providerNames`、`activeProvider`、`apiKey`、`hotkey`、`templateNames`、`activeTemplate`、`launchAtLoginEnabled`、`voiceCommands`、`silenceThreshold`、`prefix`；方法 `reload()`、`selectProvider(_:)`、`saveAPIKey()`、`selectHotkey(_:)`、`selectTemplate(_:)`、`saveGeneral()`、`toggleLaunchAtLogin()`；`var onChange: (() -> Void)?`
  - `final class SettingsWindowController { static let shared: SettingsWindowController; func show() }`

- [ ] **Step 1: 寫失敗的測試**

建立 `Tests/PhemeMurmurTests/SettingsTabTests.swift`：

```swift
import XCTest
@testable import PhemeMurmur

final class SettingsTabTests: XCTestCase {

    func testTabOrderMatchesSpec() {
        XCTAssertEqual(SettingsTab.allCases,
                       [.transcription, .hotkey, .promptTemplate, .general, .diagnostics])
    }

    func testTitlesAreTraditionalChinese() {
        XCTAssertEqual(SettingsTab.transcription.title, "轉錄服務")
        XCTAssertEqual(SettingsTab.hotkey.title, "快捷鍵")
        XCTAssertEqual(SettingsTab.promptTemplate.title, "提示模板")
        XCTAssertEqual(SettingsTab.general.title, "一般")
        XCTAssertEqual(SettingsTab.diagnostics.title, "診斷")
    }

    func testEverySymbolNameResolvesToASystemSymbol() {
        for tab in SettingsTab.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil),
                            "\(tab) has an invalid SF Symbol: \(tab.symbolName)")
        }
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter SettingsTabTests`
Expected: 編譯失敗，`cannot find 'SettingsTab' in scope`

- [ ] **Step 3: 實作 `SettingsTab`**

建立 `Sources/PhemeMurmur/UI/SettingsTab.swift`：

```swift
import Foundation

enum SettingsTab: CaseIterable, Hashable {
    case transcription
    case hotkey
    case promptTemplate
    case general
    case diagnostics

    var title: String {
        switch self {
        case .transcription: return "轉錄服務"
        case .hotkey: return "快捷鍵"
        case .promptTemplate: return "提示模板"
        case .general: return "一般"
        case .diagnostics: return "診斷"
        }
    }

    var symbolName: String {
        switch self {
        case .transcription: return "waveform.circle"
        case .hotkey: return "keyboard"
        case .promptTemplate: return "text.quote"
        case .general: return "gearshape"
        case .diagnostics: return "stethoscope"
        }
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter SettingsTabTests`
Expected: 3 個測試全部 PASS

- [ ] **Step 5a: 讓 `Config` 能寫回非字串欄位**

現有的 `Config.saveTopLevelStringField(_:value:)`（`Config.swift:221`）只處理帶引號的字串欄位，而「一般」分頁要寫 `voice-commands`（Bool）與 `silence-threshold`（Double）。在 `Config.swift` 的 `saveActivePromptTemplate` 之後加入：

```swift
    /// Writes (or updates) a top-level field whose value is not a JSON string
    /// (booleans, numbers). Same preserve-the-rest-of-the-file approach as
    /// saveTopLevelStringField, but without quoting the value.
    private static func saveTopLevelRawField(_ fieldName: String, rawValue: String) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        let newEntry = "\"\(fieldName)\": \(rawValue)"
        let escapedName = NSRegularExpression.escapedPattern(for: fieldName)
        let pattern = "\"\(escapedName)\"\\s*:\\s*[^,\\n}]+"
        if let range = content.range(of: pattern, options: .regularExpression) {
            content.replaceSubrange(range, with: newEntry)
        } else if let idx = content.firstIndex(of: "{") {
            content.insert(contentsOf: "\n    \(newEntry),", at: content.index(after: idx))
        }

        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Writes (or updates) the "voice-commands" field in config.jsonc.
    static func saveVoiceCommands(_ enabled: Bool) {
        saveTopLevelRawField("voice-commands", rawValue: enabled ? "true" : "false")
    }

    /// Writes (or updates) the "silence-threshold" field in config.jsonc.
    static func saveSilenceThreshold(_ value: Double) {
        saveTopLevelRawField("silence-threshold", rawValue: String(format: "%.4f", value))
    }

    /// Writes (or updates) the "prefix" field in config.jsonc.
    static func savePrefix(_ value: String) {
        saveTopLevelStringField("prefix", value: value)
    }
```

在 `Tests/PhemeMurmurTests/ConfigTests.swift` 追加往返測試（沿用該檔既有的 decode 風格，驗證寫出的字串能被 `ConfigFile` 解回來）：

```swift
    func testSavedBooleanFieldDecodesBack() throws {
        let json = """
        {"providers": {}, "voice-commands": true, "silence-threshold": 0.0250}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertTrue(cfg.resolvedVoiceCommands)
        XCTAssertEqual(try XCTUnwrap(cfg.silenceThreshold), 0.025, accuracy: 0.0001)
    }
```

Run: `swift test --filter ConfigTests`
Expected: 全部 PASS

- [ ] **Step 5b: 實作 `SettingsStore`**

建立 `Sources/PhemeMurmur/UI/SettingsStore.swift`。這層把 SwiftUI 與既有的 `Config` 隔開，讀寫都走 `Config` 現有 API：

```swift
import SwiftUI

/// Bridges the SwiftUI settings UI to the existing jsonc-backed Config. Reads on
/// init, writes through the same Config helpers the menu used to call.
final class SettingsStore: ObservableObject {

    @Published var providerNames: [String] = []
    @Published var activeProvider: String = ""
    @Published var apiKey: String = ""
    @Published var hotkey: HotkeyKey = .rightShift
    @Published var templateNames: [String] = []
    @Published var activeTemplate: String = Config.defaultPromptTemplateName
    @Published var launchAtLoginEnabled: Bool = false
    @Published var voiceCommands: Bool = false
    @Published var silenceThreshold: Double = 0
    @Published var prefix: String = ""

    /// Called after any change that the AppDelegate must react to (provider swap,
    /// hotkey change, template change). Set by AppDelegate when it creates the store.
    var onChange: (() -> Void)?

    private let launchAtLogin = LaunchAtLogin()

    init() {
        reload()
    }

    func reload() {
        guard let config = Config.loadConfig() else { return }
        let entries = config.resolvedProviders
        providerNames = entries.keys.sorted()
        activeProvider = config.resolvedActiveProvider ?? ""
        apiKey = entries[activeProvider]?.apiKey ?? ""
        hotkey = config.resolvedHotkey
        templateNames = (config.promptTemplates ?? [:]).keys.sorted()
        activeTemplate = config.activePromptTemplate ?? Config.defaultPromptTemplateName
        voiceCommands = config.resolvedVoiceCommands
        silenceThreshold = config.silenceThreshold ?? 0
        prefix = config.prefix ?? ""
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }

    func selectProvider(_ name: String) {
        activeProvider = name
        apiKey = Config.loadConfig()?.resolvedProviders[name]?.apiKey ?? ""
        Config.saveActiveProvider(name)
        onChange?()
    }

    func saveAPIKey() {
        _ = Config.saveAPIKey(providerName: activeProvider, apiKey: apiKey)
        onChange?()
    }

    func selectHotkey(_ key: HotkeyKey) {
        hotkey = key
        Config.saveHotkey(key)
        onChange?()
    }

    func selectTemplate(_ name: String) {
        activeTemplate = name
        Config.saveActivePromptTemplate(name)
        onChange?()
    }

    func saveGeneral() {
        Config.saveVoiceCommands(voiceCommands)
        Config.saveSilenceThreshold(silenceThreshold)
        Config.savePrefix(prefix)
        onChange?()
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.handleClick()
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }
}
```

全部走 `Config` 既有的寫回函式（`saveAPIKey(providerName:apiKey:)`、`saveActiveProvider(_:)`、`saveHotkey(_:)`、`saveActivePromptTemplate(_:)`）加上 Step 5a 新增的三個。不要新增第二套儲存機制。`Config.defaultPromptTemplateName` 與 `LaunchAtLogin.state` / `refresh()` 皆為既有 API。

- [ ] **Step 6: 實作設定視圖**

建立 `Sources/PhemeMurmur/UI/SettingsView.swift`：

```swift
import SwiftUI

struct SettingsView: View {

    @ObservedObject var store: SettingsStore
    @State private var selection: SettingsTab = .transcription

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(DeepSpace.color(DeepSpace.starDust, opacity: 0.12))
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(22)
        }
        .frame(width: 640, height: 420)
        .background(
            RadialGradient(
                colors: [DeepSpace.color(DeepSpace.spaceVoidTop),
                         DeepSpace.color(DeepSpace.spaceVoidBottom)],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 10, endRadius: 620
            )
        )
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.symbolName).frame(width: 16)
                        Text(tab.title)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selectionBackground(for: tab))
                    .foregroundStyle(selection == tab
                                     ? Color.white
                                     : DeepSpace.color(DeepSpace.starDust))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 152)
        .background(DeepSpace.color(DeepSpace.spaceVoidBottom, opacity: 0.5))
    }

    @ViewBuilder
    private func selectionBackground(for tab: SettingsTab) -> some View {
        if selection == tab {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [DeepSpace.color(DeepSpace.auroraCyan, opacity: 0.16),
                             DeepSpace.color(DeepSpace.auroraViolet, opacity: 0.14)],
                    startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(DeepSpace.color(DeepSpace.auroraCyan, opacity: 0.26), lineWidth: 1))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .transcription: transcriptionPane
        case .hotkey: hotkeyPane
        case .promptTemplate: templatePane
        case .general: generalPane
        case .diagnostics: diagnosticsPane
        }
    }

    private var transcriptionPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle("轉錄服務", "選擇語音轉文字的供應商，並設定金鑰。")
            ForEach(store.providerNames, id: \.self) { name in
                Button { store.selectProvider(name) } label: {
                    HStack {
                        Text(name)
                        Spacer()
                        if name == store.activeProvider {
                            Text("使用中")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Capsule().fill(LinearGradient(
                                    colors: [DeepSpace.color(DeepSpace.auroraCyan),
                                             DeepSpace.color(DeepSpace.auroraViolet)],
                                    startPoint: .leading, endPoint: .trailing)))
                                .foregroundStyle(Color.black)
                        }
                    }
                    .padding(11)
                    .background(rowBackground)
                }
                .buttonStyle(.plain)
            }
            Text("API KEY").font(.system(size: 10, weight: .semibold)).kerning(1.2)
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust, opacity: 0.8))
            SecureField("", text: $store.apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .background(rowBackground)
                .onSubmit { store.saveAPIKey() }
            Button("儲存金鑰") { store.saveAPIKey() }
            Spacer()
        }
    }

    private var hotkeyPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneTitle("快捷鍵", "按一次開始錄音，再按一次結束；Esc 取消。")
            ForEach(HotkeyKey.allCases, id: \.self) { key in
                Button { store.selectHotkey(key) } label: {
                    HStack {
                        Text(key.displayName)
                        Spacer()
                        if key == store.hotkey {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))
                        }
                    }
                    .padding(11)
                    .background(rowBackground)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var templatePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneTitle("提示模板", "轉錄後套用的後處理指令。")
            ForEach(store.templateNames, id: \.self) { name in
                Button { store.selectTemplate(name) } label: {
                    HStack {
                        Text(name)
                        Spacer()
                        if name == store.activeTemplate {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))
                        }
                    }
                    .padding(11)
                    .background(rowBackground)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneTitle("一般", "這些設定會寫回 config.jsonc。")
            Toggle("登入時啟動", isOn: Binding(
                get: { store.launchAtLoginEnabled },
                set: { _ in store.toggleLaunchAtLogin() }
            ))
            Toggle("啟用語音指令", isOn: $store.voiceCommands)
                .onChange(of: store.voiceCommands) { _ in store.saveGeneral() }
            HStack {
                Text("靜音門檻")
                Slider(value: $store.silenceThreshold, in: 0...0.1) { editing in
                    if !editing { store.saveGeneral() }
                }
                Text(String(format: "%.3f", store.silenceThreshold))
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Text("前綴詞")
                TextField("", text: $store.prefix)
                    .textFieldStyle(.plain)
                    .padding(7)
                    .background(rowBackground)
                    .onSubmit { store.saveGeneral() }
            }
            Spacer()
        }
        .tint(DeepSpace.color(DeepSpace.auroraCyan))
    }

    private var diagnosticsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneTitle("診斷", "設定檔與錯誤記錄。")
            Button("開啟設定檔資料夾") {
                NSWorkspace.shared.open(URL(fileURLWithPath:
                    (Config.configPath as NSString).deletingLastPathComponent))
            }
            Button("顯示錯誤記錄") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: ErrorLog.logPath)
                ])
            }
            Spacer()
        }
    }

    private func paneTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 11))
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
        }
        .padding(.bottom, 4)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(DeepSpace.color(DeepSpace.starDust, opacity: 0.1), lineWidth: 1))
    }
}
```

`HotkeyKey` 已符合 `CaseIterable`（`HotkeyManager.swift:6`），`ErrorLog.logPath` 亦為既有的 static 屬性（`ErrorLog.swift:12`），兩者直接使用即可。

- [ ] **Step 7: 實作視窗控制器**

建立 `Sources/PhemeMurmur/UI/SettingsWindowController.swift`：

```swift
import AppKit
import SwiftUI

/// Hosts SettingsView in a borderless-looking window: transparent titlebar, full
/// size content, so the Deep Space panel reads as one surface.
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    let store = SettingsStore()
    private var window: NSWindow?

    func show() {
        if let window {
            store.reload()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        store.reload()
        let hosting = NSHostingView(rootView: SettingsView(store: store))
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.backgroundColor = DeepSpace.nsColor(DeepSpace.spaceVoidBottom)
        created.isReleasedWhenClosed = false
        created.contentView = hosting
        created.center()
        window = created

        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 8: 選單瘦身**

在 `main.swift` 的 `setupApp()` 中，把選單重建為：

```swift
        statusMenu = NSMenu()
        statusMenu.delegate = self

        statusMenuItem = NSMenuItem(title: "Status: idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)

        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(Self.makeMenuItem(title: "設定…",
                                             action: #selector(openSettings),
                                             target: self,
                                             keyEquivalent: ","))
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(Self.makeMenuItem(title: "關於 PhemeMurmur",
                                             action: #selector(showAboutPanel),
                                             target: self))
        statusMenu.addItem(Self.makeMenuItem(title: "結束",
                                             action: #selector(quitApp),
                                             target: self,
                                             keyEquivalent: "q"))
        statusItem.menu = statusMenu
```

新增 action：

```swift
    @objc private func openSettings() {
        SettingsWindowController.shared.store.onChange = { [weak self] in
            self?.reloadProvidersFromConfig()
            self?.applyHotkeyFromConfig()
        }
        SettingsWindowController.shared.show()
    }
```

其中 `applyHotkeyFromConfig()` 把現行 `selectHotkey(_:)` 中「讀 config → 更新 `currentHotkey` → 重啟 hotkey monitor」的邏輯抽出來重用。

刪除：`promptMenuItem`、`promptSubmenu`、`providerMenuItem`、`providerSubmenu`、`hotkeyMenuItem`、`hotkeySubmenu`、`configLogsMenuItem`、`configLogsSubmenu`、`showErrorLogMenuItem`、`launchAtLoginItem` 及其建構程式碼，以及 `rebuildProviderSubmenu()`、`rebuildPromptSubmenu()`、`rebuildHotkeySubmenu()`、`selectProvider(_:)`、`selectPromptTemplate(_:)`、`selectHotkey(_:)`、`setAPIKeyForActive()`、`runAPIKeyPrompt(...)`、`refreshProviderLabel()`、`toggleLaunchAtLogin()`、`setLaunchAtLogin(state:)`、`enabledImage()`、`infoImage()`、`openConfigFolder()`、`revealErrorLog()`。`menuWillOpen(_:)` 中針對這些子選單的刷新呼叫一併移除，只留狀態文字更新。

- [ ] **Step 9: 建置、測試、實機驗收**

Run: `swift build && swift test && make install`
Expected: build 與測試通過。menu bar 選單只剩四項（狀態、設定…、關於、結束）。開啟設定視窗：無標題文字、深空底、側邊欄五項可切換；切換 provider 與 hotkey 後關閉視窗，錄音行為即時反映新設定；填入 API Key 後按儲存，`~/.config/pheme-murmur/config.jsonc` 內容正確更新。

- [ ] **Step 10: Commit**

```bash
git add Sources/PhemeMurmur/UI/SettingsTab.swift \
        Sources/PhemeMurmur/UI/SettingsStore.swift \
        Sources/PhemeMurmur/UI/SettingsView.swift \
        Sources/PhemeMurmur/UI/SettingsWindowController.swift \
        Sources/PhemeMurmur/main.swift \
        Sources/PhemeMurmur/Config.swift \
        Sources/PhemeMurmur/HotkeyManager.swift \
        Tests/PhemeMurmurTests/SettingsTabTests.swift
git commit -m "feat(ui): replace menu submenus with Deep Space settings window"
```

---

### Task 7: Onboarding 沉浸式四頁

**Files:**
- Create: `Sources/PhemeMurmur/UI/OnboardingFlow.swift`
- Create: `Sources/PhemeMurmur/UI/OnboardingView.swift`
- Modify: `Sources/PhemeMurmur/OnboardingWindow.swift`
- Test: `Tests/PhemeMurmurTests/OnboardingFlowTests.swift`

**Interfaces:**
- Consumes: `PermissionStatus`、`SettingsStore`、`DeepSpace`
- Produces:
  - `enum OnboardingPage: Int, CaseIterable { case welcome, permissions, provider, tryIt }`（含 `var kicker: String`、`var title: String`、`var body: String`）
  - `enum OnboardingFlow { static func canAdvance(from page: OnboardingPage, permissions: [PermissionItem], hasAPIKey: Bool, didRecordOnce: Bool) -> Bool; static func next(after page: OnboardingPage) -> OnboardingPage? }`

- [ ] **Step 1: 寫失敗的測試**

建立 `Tests/PhemeMurmurTests/OnboardingFlowTests.swift`：

```swift
import XCTest
@testable import PhemeMurmur

final class OnboardingFlowTests: XCTestCase {

    private let granted = [
        PermissionItem(kind: .accessibility, granted: true),
        PermissionItem(kind: .microphone, granted: true),
    ]
    private let missingMic = [
        PermissionItem(kind: .accessibility, granted: true),
        PermissionItem(kind: .microphone, granted: false),
    ]

    func testPageOrder() {
        XCTAssertEqual(OnboardingPage.allCases, [.welcome, .permissions, .provider, .tryIt])
    }

    func testWelcomeAlwaysAdvances() {
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .welcome, permissions: missingMic,
                                                hasAPIKey: false, didRecordOnce: false))
    }

    func testPermissionsBlockUntilAllGranted() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .permissions, permissions: missingMic,
                                                 hasAPIKey: false, didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .permissions, permissions: granted,
                                                hasAPIKey: false, didRecordOnce: false))
    }

    func testProviderBlocksUntilAPIKeyPresent() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                 hasAPIKey: false, didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                               hasAPIKey: true, didRecordOnce: false))
    }

    func testTryItBlocksUntilOneSuccessfulRecording() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .tryIt, permissions: granted,
                                                 hasAPIKey: true, didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .tryIt, permissions: granted,
                                               hasAPIKey: true, didRecordOnce: true))
    }

    func testNextWalksForwardAndStopsAtEnd() {
        XCTAssertEqual(OnboardingFlow.next(after: .welcome), .permissions)
        XCTAssertEqual(OnboardingFlow.next(after: .permissions), .provider)
        XCTAssertEqual(OnboardingFlow.next(after: .provider), .tryIt)
        XCTAssertNil(OnboardingFlow.next(after: .tryIt))
    }

    func testEveryPageHasChineseCopy() {
        for page in OnboardingPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.body.isEmpty)
        }
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter OnboardingFlowTests`
Expected: 編譯失敗，`cannot find 'OnboardingPage' in scope`

- [ ] **Step 3: 實作流程邏輯**

建立 `Sources/PhemeMurmur/UI/OnboardingFlow.swift`：

```swift
import Foundation

enum OnboardingPage: Int, CaseIterable {
    case welcome
    case permissions
    case provider
    case tryIt

    var kicker: String {
        switch self {
        case .welcome: return "WELCOME ABOARD"
        case .permissions: return "STEP 02 / 04"
        case .provider: return "STEP 03 / 04"
        case .tryIt: return "STEP 04 / 04"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "PhemeMurmur"
        case .permissions: return "授予兩項權限"
        case .provider: return "設定轉錄服務"
        case .tryIt: return "試錄一次"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "按下快捷鍵說話，再按一次就把文字送進你正在打字的地方。\n先花 30 秒完成三個設定。"
        case .permissions:
            return "PhemeMurmur 需要這兩項才能聽見你的聲音、並把文字送進輸入框。"
        case .provider:
            return "選一個語音轉文字的供應商，並填入 API Key。"
        case .tryIt:
            return "按一次快捷鍵，說一句話，再按一次結束。\n看到文字出現就完成了。"
        }
    }
}

enum OnboardingFlow {

    static func canAdvance(from page: OnboardingPage,
                           permissions: [PermissionItem],
                           hasAPIKey: Bool,
                           didRecordOnce: Bool) -> Bool {
        switch page {
        case .welcome:
            return true
        case .permissions:
            return permissions.allSatisfy(\.granted)
        case .provider:
            return hasAPIKey
        case .tryIt:
            return didRecordOnce
        }
    }

    static func next(after page: OnboardingPage) -> OnboardingPage? {
        OnboardingPage(rawValue: page.rawValue + 1)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter OnboardingFlowTests`
Expected: 7 個測試全部 PASS

- [ ] **Step 5: 實作 Onboarding 視圖**

建立 `Sources/PhemeMurmur/UI/OnboardingView.swift`：

```swift
import SwiftUI

/// Immersive single-column onboarding: generous whitespace, star dust, a mini
/// nebula core, progress dots and one primary button.
struct OnboardingView: View {

    let onFinish: () -> Void

    @ObservedObject var store: SettingsStore
    @State private var page: OnboardingPage = .welcome
    @State private var permissions: [PermissionItem] = PermissionStatus.current()
    @State private var didRecordOnce = false

    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var canAdvance: Bool {
        OnboardingFlow.canAdvance(from: page,
                                  permissions: permissions,
                                  hasAPIKey: !store.apiKey.isEmpty,
                                  didRecordOnce: didRecordOnce)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            NebulaHUDView(phase: .transcribing(provider: ""),
                          levels: Array(repeating: 0, count: 15),
                          showsCapsule: false)
                .scaleEffect(0.45)
                .frame(height: 80)

            Text(page.kicker)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))

            Text(page.title)
                .font(.system(size: page == .welcome ? 20 : 17, weight: .semibold))
                .foregroundStyle(.white)

            Text(page.body)
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                .frame(maxWidth: 320)

            pageContent

            Spacer()

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(OnboardingPage.allCases, id: \.self) { p in
                        Circle()
                            .fill(p == page
                                  ? DeepSpace.color(DeepSpace.auroraCyan)
                                  : DeepSpace.color(DeepSpace.starDust, opacity: 0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                Button(page == .tryIt ? "完成" : "繼續") { advance() }
                    .disabled(!canAdvance)
                    .buttonStyle(.borderedProminent)
                    .tint(DeepSpace.color(DeepSpace.auroraCyan))
            }
            .padding(.bottom, 6)
        }
        .padding(26)
        .frame(width: 480, height: 400)
        .background(
            RadialGradient(
                colors: [DeepSpace.color(DeepSpace.spaceVoidTop),
                         DeepSpace.color(DeepSpace.spaceVoidBottom)],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 10, endRadius: 520
            )
        )
        .preferredColorScheme(.dark)
        .onReceive(pollTimer) { _ in
            permissions = PermissionStatus.current()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome, .tryIt:
            EmptyView()
        case .permissions:
            VStack(spacing: 8) {
                ForEach(permissions, id: \.kind) { item in
                    Button {
                        if !item.granted { PermissionStatus.openSettings(for: item.kind) }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.granted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.granted
                                                 ? DeepSpace.color(DeepSpace.auroraCyan)
                                                 : DeepSpace.color(DeepSpace.starDust, opacity: 0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.kind.title).font(.system(size: 11.5))
                                Text(item.granted ? "已授權" : item.kind.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                            }
                            Spacer()
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 320)
        case .provider:
            VStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { store.activeProvider },
                    set: { store.selectProvider($0) }
                )) {
                    ForEach(store.providerNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                SecureField("API Key", text: $store.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06)))
                    .onSubmit { store.saveAPIKey() }
            }
            .frame(maxWidth: 320)
        }
    }

    private func advance() {
        if page == .provider { store.saveAPIKey() }
        if let next = OnboardingFlow.next(after: page) {
            page = next
        } else {
            onFinish()
        }
    }
}
```

`tryIt` 頁的 `didRecordOnce` 由 `AppDelegate` 在 onboarding 期間完成第一次成功轉錄時設為 true——以 `NotificationCenter` 送出 `.phemeDidTranscribeOnce`，`OnboardingView` 加上：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .phemeDidTranscribeOnce)) { _ in
            didRecordOnce = true
        }
```

並在 `OnboardingFlow.swift` 末端宣告：

```swift
extension Notification.Name {
    static let phemeDidTranscribeOnce = Notification.Name("phemeDidTranscribeOnce")
}
```

在 `main.swift` 轉錄成功的分支（`hud.show(.done)` 旁）加上：

```swift
        NotificationCenter.default.post(name: .phemeDidTranscribeOnce, object: nil)
```

- [ ] **Step 6: 把 `OnboardingWindow` 改為承載 SwiftUI**

`Sources/PhemeMurmur/OnboardingWindow.swift` 保留 `markerPath`、`needsOnboarding`、`markOnboardingComplete`、`showIfNeeded(onDismiss:)` 與 `windowWillClose`，把 `showWindow()` 與 `renderPage()` / `goNext()` / `goBack()` / `pages` 全部刪掉，`showWindow()` 改為：

```swift
    private func showWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = DeepSpace.nsColor(DeepSpace.spaceVoidBottom)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        w.contentView = NSHostingView(rootView: OnboardingView(
            onFinish: { [weak self] in self?.dismiss() },
            store: SettingsWindowController.shared.store
        ))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

同時把檔案頂端的 `import AppKit` 補上 `import SwiftUI`，並刪除已無用的 `currentPage`、`pageContainer`、`nextButton`、`backButton`、`pageIndicator` 屬性。

- [ ] **Step 7: 建置、測試、實機驗收**

Run:
```bash
rm -f ~/.config/pheme-murmur/.onboarding-done
swift build && swift test && make install
```
Expected: build 與測試通過。App 啟動後出現深空 Onboarding：四頁可前進，權限頁在系統設定授權後 1 秒內自動打勾並解鎖「繼續」，provider 頁未填 API Key 時「繼續」為停用，最後一頁完成一次錄音後按「完成」關閉且不再出現。

- [ ] **Step 8: Commit**

```bash
git add Sources/PhemeMurmur/UI/OnboardingFlow.swift \
        Sources/PhemeMurmur/UI/OnboardingView.swift \
        Sources/PhemeMurmur/OnboardingWindow.swift \
        Sources/PhemeMurmur/main.swift \
        Tests/PhemeMurmurTests/OnboardingFlowTests.swift
git commit -m "feat(ui): rebuild onboarding as immersive Deep Space flow"
```

---

### Task 8: 文件更新

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 前七個 task 的成果
- Produces: 無程式介面

- [ ] **Step 1: 更新 README 的功能與設定說明**

改動三處：

1. Features 區塊，把「Menu bar only」下方補上兩行：

```markdown
- **Deep Space 介面** — 深空配色的浮動設定視窗、錄音時的星雲監聽面板
- **錄音回饋** — 螢幕底部浮現星雲球與日冕光束，隨音量即時反應
```

2. Setup 區塊，把三步驟改寫為：

```markdown
On first launch, a guided onboarding walks you through four steps:

1. Welcome
2. Grant **Accessibility** and **Microphone** access — the panel detects both live and unlocks itself once granted
3. Pick a transcription provider and enter its API key
4. Record once to confirm everything works
```

3. 新增一段說明設定入口：

```markdown
## Settings

Open **設定…** from the menu bar (or press `Cmd+,` while the menu is open). The
window has five panes: 轉錄服務 (provider and API key), 快捷鍵, 提示模板, 一般
(launch at login, voice commands, silence threshold, prefix) and 診斷 (config
folder, error log). Everything is written back to `~/.config/pheme-murmur/config.jsonc`.
```

Launch at Login 段落中「Toggle **Launch at Login** from the menu bar」改為「Toggle **登入時啟動** in the 一般 pane of the settings window」，其餘說明維持不變。

- [ ] **Step 2: 確認 README 描述與實際行為一致**

Run: `make install`
Expected: 逐條對照 README 新增的敘述與實際 app 行為（選單項名稱、五個分頁名稱、onboarding 四步驟）皆相符。

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: describe Deep Space UI and settings window"
```

---

## 完成後驗收清單

全部 task 完成後，人工逐項確認：

- [ ] Finder 中 `/Applications/PhemeMurmur.app` 的 icon 為深空波形，圖示清晰
- [ ] menu bar 待命時顯示五條波形，淺色／深色 menu bar 皆正常
- [ ] 錄音 HUD 出現在螢幕底部、光束隨音量變化、不搶焦點、點擊穿透
- [ ] Esc 取消時 HUD 立即消失
- [ ] 設定視窗五個分頁皆可讀寫，關閉後設定生效
- [ ] 刪除 `.onboarding-done` 後重新啟動，四頁 onboarding 走得完
- [ ] `swift test` 全綠
