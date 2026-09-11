import SwiftUI

// MARK: - Armour plate

/// The chamfered plate every Mark III surface is built on: a 1px gradient edge
/// wrapped around a dark fill, with a heavy drop shadow.
struct ArmourPlate<Content: View>: View {
    var cut: CGFloat = 20
    var edge: LinearGradient = MarkIII.plateEdge
    var fill: AnyShapeStyle = AnyShapeStyle(MarkIII.plateFill)
    var shadowRadius: CGFloat = 45
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(fill)
            .clipShape(Chamfer(cut: cut))
            .overlay(
                // The edge is a stroke rather than a padded parent so the inner
                // silhouette cannot drift out of register with the outer one.
                Chamfer(cut: cut).strokeBorder(edge, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.7), radius: shadowRadius, y: shadowRadius / 3)
    }
}

/// Hairline-bordered row used for provider/hotkey/template/setting entries.
struct ChamferRow<Content: View>: View {
    var cut: CGFloat = 10
    var isActive: Bool = false
    var isDimmed: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                isActive
                ? AnyShapeStyle(LinearGradient(
                    colors: [MarkIII.color(MarkIII.crimson, opacity: 0.42),
                             MarkIII.color((0.078, 0.055, 0.055), opacity: 0.95)],
                    startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(Color.white.opacity(0.035))
            )
            .clipShape(Chamfer(cut: cut))
            .overlay(
                Chamfer(cut: cut).strokeBorder(
                    isActive
                    ? AnyShapeStyle(LinearGradient(
                        colors: [MarkIII.color(MarkIII.goldBright),
                                 MarkIII.color(MarkIII.crimson)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(MarkIII.color(MarkIII.gold, opacity: 0.3)),
                    lineWidth: 1)
            )
            .shadow(color: MarkIII.color(MarkIII.crimson, opacity: isActive ? 0.28 : 0),
                    radius: 12)
            .opacity(isDimmed ? 0.45 : 1)
    }
}

// MARK: - Scanlines

/// The CRT texture over every plate: a fixed 1-in-3 line grid plus a slow bright
/// band travelling down the surface.
struct ScanlineOverlay: View {
    var showsSweep: Bool = true
    var lineOpacity: Double = 0.028

    @State private var sweepOffset: CGFloat = -120

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Canvas { context, size in
                    let line = Color.white.opacity(lineOpacity)
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                     with: .color(line))
                        y += 3
                    }
                }
                if showsSweep {
                    LinearGradient(
                        colors: [.clear, MarkIII.color(MarkIII.gold, opacity: 0.07), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 90)
                    .offset(y: sweepOffset)
                    .onAppear {
                        sweepOffset = -90
                        withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                            sweepOffset = geo.size.height + 90
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reactor

/// The voice core: a glowing sphere, a gold containment ring, a counter-rotating
/// segmented halo and a white-hot centre.
struct ReactorCore: View {
    var tint: MarkIII.RGB
    var diameter: CGFloat = 76
    var pulses: Bool = true

    @State private var haloAngle: Double = 0
    @State private var breathing = false

    var body: some View {
        ZStack {
            // Outer sphere: white-hot pinhole, arc cyan shell, then a cold rim
            // that picks up the phase tint.
            Circle()
                .fill(RadialGradient(
                    colors: [.white,
                             MarkIII.color(MarkIII.arc),
                             MarkIII.color((0.118, 0.471, 0.627), opacity: 0.55),
                             MarkIII.color((0.039, 0.078, 0.110), opacity: 0.9),
                             MarkIII.color(tint, opacity: 0.2)],
                    center: UnitPoint(x: 0.5, y: 0.46),
                    startRadius: diameter * 0.03,
                    endRadius: diameter * 0.5))
                .overlay(
                    // Stands in for the spec's inset glow, which SwiftUI has no
                    // direct equivalent for.
                    Circle().strokeBorder(
                        RadialGradient(colors: [MarkIII.color(MarkIII.arc, opacity: 0.5), .clear],
                                       center: .center,
                                       startRadius: diameter * 0.3,
                                       endRadius: diameter * 0.5),
                        lineWidth: diameter * 0.12)
                )
                .shadow(color: MarkIII.color(tint, opacity: 0.4), radius: diameter * 0.34)

            Circle()
                .strokeBorder(MarkIII.color(MarkIII.gold, opacity: 0.85), lineWidth: 2)
                .frame(width: diameter * 0.64, height: diameter * 0.64)
                .shadow(color: MarkIII.color(MarkIII.gold, opacity: 0.6), radius: 5)

            Circle()
                .fill(AngularGradient(
                    stops: Self.haloStops,
                    center: .center))
                .frame(width: diameter * 0.38, height: diameter * 0.38)
                .opacity(0.55)
                .rotationEffect(.degrees(haloAngle))

            Circle()
                .fill(RadialGradient(colors: [.white, MarkIII.color(MarkIII.arc)],
                                     center: .center,
                                     startRadius: diameter * 0.04,
                                     endRadius: diameter * 0.1))
                .frame(width: diameter * 0.2, height: diameter * 0.2)
                .shadow(color: MarkIII.color(MarkIII.arc), radius: 10)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pulses && breathing ? 1.07 : 0.93)
        .opacity(pulses && breathing ? 1.0 : 0.85)
        .onAppear {
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
                haloAngle = -360
            }
            guard pulses else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    /// Four lit arcs with gaps between them, matching the spec's repeating
    /// gold/transparent conic stops.
    private static let haloStops: [Gradient.Stop] = {
        let lit = MarkIII.color(MarkIII.goldBright)
        return [
            .init(color: lit, location: 0), .init(color: .clear, location: 0.12),
            .init(color: lit, location: 0.25), .init(color: .clear, location: 0.37),
            .init(color: lit, location: 0.50), .init(color: .clear, location: 0.62),
            .init(color: lit, location: 0.75), .init(color: .clear, location: 0.87),
            .init(color: lit, location: 1),
        ]
    }()
}

/// A single audio beam: a bar with a chiselled tip pointing away from the core.
struct BeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = rect.height * 0.22
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tip))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tip))
        p.closeSubpath()
        return p
    }
}

/// Reactor plus instrumentation: radial level beams, a ticked bezel that sweeps
/// slowly, and a bright arc that laps it faster.
struct ReactorCluster: View {
    var tint: MarkIII.RGB
    var ring: MarkIII.RGB
    /// One value per beam, 0...1.
    var levels: [Float]
    /// Seconds per revolution of the bright arc; the tick bezel takes 4×.
    var speed: Double
    var pulses: Bool = true

    static let systemSize: CGFloat = 190
    private let beamCount = 15

    @State private var tickAngle: Double = 0
    @State private var arcAngle: Double = 0

    var body: some View {
        ZStack {
            beams
            tickRing
            arcRing
            ReactorCore(tint: tint, diameter: 76, pulses: pulses)
        }
        .frame(width: Self.systemSize, height: Self.systemSize)
        .onAppear { spin() }
        .onChange(of: speed) { _ in spin() }
    }

    /// Advances by whole turns rather than resetting, so a phase change blends
    /// into the current rotation instead of snapping back to zero.
    private func spin() {
        withAnimation(.linear(duration: speed * 4).repeatForever(autoreverses: false)) {
            tickAngle += 360
        }
        withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
            arcAngle += 360
        }
    }

    private var beams: some View {
        ZStack {
            ForEach(0..<beamCount, id: \.self) { index in
                let level = CGFloat(index < levels.count ? levels[index] : 0)
                let length = 16 + max(0, min(1, level)) * 54
                BeamShape()
                    .fill(LinearGradient(
                        colors: [MarkIII.color(tint),
                                 MarkIII.color(MarkIII.gold, opacity: 0.53),
                                 .clear],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: length)
                    .blur(radius: 0.4)
                    .offset(y: -(44 + length / 2))
                    .rotationEffect(.degrees(Double(index) / Double(beamCount) * 360))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
    }

    private var tickRing: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { i in
                let major = i % 3 == 0
                Rectangle()
                    .fill(MarkIII.color(ring, opacity: major ? 1 : 0.47))
                    .frame(width: major ? 2 : 1, height: major ? 9 : 5)
                    .offset(y: -42)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
        }
        .rotationEffect(.degrees(tickAngle))
    }

    private var arcRing: some View {
        Circle()
            .trim(from: 0, to: 0.62)
            .stroke(AngularGradient(
                colors: [MarkIII.color(ring),
                         MarkIII.color(ring, opacity: 0.33),
                         .clear],
                center: .center),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
            .frame(width: 124, height: 124)
            .rotationEffect(.degrees(arcAngle))
    }
}

/// Four right-angle ticks framing the HUD instrument, like a targeting reticle.
struct Brackets: View {
    var color: MarkIII.RGB
    var length: CGFloat = 16
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height, l = length
                p.move(to: CGPoint(x: 0, y: l));       p.addLine(to: .zero)
                p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0));   p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l));   p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h));       p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(MarkIII.color(color, opacity: 0.8), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

/// Chamfered button: a gold slab with near-black text, or a hairline outline.
struct MarkIIIButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    var cut: CGFloat = 9
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MarkIII.font(13, .semibold))
            .kerning(1)
            .foregroundStyle(isPrimary
                             ? MarkIII.color(MarkIII.onGold)
                             : MarkIII.color(MarkIII.ink))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background {
                if isPrimary {
                    MarkIII.goldSlab.clipShape(Chamfer(cut: cut))
                } else {
                    MarkIII.color(MarkIII.gold, opacity: 0.1).clipShape(Chamfer(cut: cut))
                }
            }
            .overlay {
                if !isPrimary {
                    Chamfer(cut: cut)
                        .strokeBorder(MarkIII.color(MarkIII.gold, opacity: 0.35), lineWidth: 1)
                }
            }
            .shadow(color: MarkIII.color(MarkIII.gold, opacity: isPrimary ? 0.3 : 0), radius: 10)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

/// The boot sequence's CTA: wider tracking and a crimson-tipped gold gradient.
struct BootCTAStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MarkIII.font(14, .bold))
            .kerning(2)
            .foregroundStyle(MarkIII.color(MarkIII.onGold))
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .background(
                LinearGradient(stops: [
                    .init(color: MarkIII.color(MarkIII.goldBright), location: 0),
                    .init(color: MarkIII.color(MarkIII.gold), location: 0.45),
                    .init(color: MarkIII.color(MarkIII.crimson), location: 1.3),
                ], startPoint: .leading, endPoint: .trailing)
                .clipShape(Chamfer(cut: 10))
            )
            .shadow(color: MarkIII.color(MarkIII.gold, opacity: 0.35), radius: 13)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// Chamfered toggle: a gold slab when on, a dim track when off.
struct MarkIIIToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Chamfer(cut: 6)
                    .fill(configuration.isOn
                          ? AnyShapeStyle(MarkIII.goldSlab)
                          : AnyShapeStyle(MarkIII.color(MarkIII.gold, opacity: 0.18)))
                Chamfer(cut: 5)
                    .fill(configuration.isOn
                          ? MarkIII.color(MarkIII.onGold)
                          : MarkIII.color(MarkIII.ink, opacity: 0.6))
                    .frame(width: 20, height: 18)
                    .padding(.horizontal, 2)
            }
            .frame(width: 46, height: 22)
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal level slider with the design's skewed gold thumb.
struct SkewSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onCommit: () -> Void = {}

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(MarkIII.color(MarkIII.gold, opacity: 0.18))
                    .frame(height: 4)
                Rectangle()
                    .fill(LinearGradient(colors: [MarkIII.color(MarkIII.crimson),
                                                  MarkIII.color(MarkIII.goldBright)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * fraction, height: 4)
                SkewThumb()
                    .fill(MarkIII.color(MarkIII.goldBright))
                    .frame(width: 10, height: 16)
                    .shadow(color: MarkIII.color(MarkIII.gold), radius: 6)
                    .offset(x: geo.size.width * fraction - 5)
            }
            .frame(height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = max(0, min(1, g.location.x / max(geo.size.width, 1)))
                        value = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: 18)
    }

    private struct SkewThumb: Shape {
        func path(in rect: CGRect) -> Path {
            let skew = rect.width * 0.5
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX + skew, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX - skew, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - Small instruments

/// A rotated square used throughout as a state indicator.
struct Diamond: View {
    var color: MarkIII.RGB
    var side: CGFloat = 8
    var filled: Bool = true
    var glows: Bool = true

    var body: some View {
        Rectangle()
            .fill(filled ? MarkIII.color(color) : Color.clear)
            .overlay {
                if !filled {
                    Rectangle().strokeBorder(MarkIII.color(MarkIII.dim), lineWidth: 1)
                }
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(45))
            .shadow(color: MarkIII.color(color, opacity: glows && filled ? 0.9 : 0), radius: 5)
            .frame(width: side * 1.5, height: side * 1.5)
    }
}

/// The rail's "ARC OUTPUT" meter: eight crimson-to-gold bars.
struct OutputBars: View {
    private let heights: [CGFloat] = [0.5, 0.8, 0.35, 0.95, 0.62, 0.78, 0.45, 0.88]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, v in
                Rectangle()
                    .fill(LinearGradient(colors: [MarkIII.color(MarkIII.crimson),
                                                  MarkIII.color(MarkIII.goldBright)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(width: 4, height: 6 + v * 18)
                    .opacity(0.55 + v * 0.45)
            }
        }
        .frame(height: 24, alignment: .bottom)
    }
}

/// Progress pips for the boot sequence: skewed bars lit up to the current page.
struct BootPips: View {
    var total: Int
    var current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Pip()
                    .fill(i <= current
                          ? AnyShapeStyle(LinearGradient(
                              colors: [MarkIII.color(MarkIII.goldBright),
                                       MarkIII.color(MarkIII.gold)],
                              startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(MarkIII.color(MarkIII.gold, opacity: 0.18)))
                    .frame(width: 26, height: 3)
                    .shadow(color: MarkIII.color(MarkIII.gold, opacity: i <= current ? 0.6 : 0),
                            radius: 5)
            }
        }
    }

    private struct Pip: Shape {
        func path(in rect: CGRect) -> Path {
            let skew = rect.height * 0.5
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX + skew, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX - skew, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// A wide-tracked mono label — the design's telemetry voice.
struct MonoText: View {
    let text: String
    var size: CGFloat = 10
    var weight: MarkIII.Weight = .medium
    var tracking: CGFloat = 1.8
    var color: MarkIII.RGB = MarkIII.dim
    var opacity: Double = 1

    init(_ text: String,
         size: CGFloat = 10,
         weight: MarkIII.Weight = .medium,
         tracking: CGFloat = 1.8,
         color: MarkIII.RGB = MarkIII.dim,
         opacity: Double = 1) {
        self.text = text
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.color = color
        self.opacity = opacity
    }

    var body: some View {
        Text(text)
            .font(MarkIII.mono(size, weight))
            .kerning(tracking)
            .foregroundStyle(MarkIII.color(color, opacity: opacity))
    }
}

/// The gold-on-crimson chip that labels a HUD phase or a hotkey.
struct StatusChip<Content: View>: View {
    var border: MarkIII.RGB
    var borderOpacity: Double = 0.4
    var fill: MarkIII.RGB = MarkIII.gold
    var fillOpacity: Double = 0.10
    var cut: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(MarkIII.color(fill, opacity: fillOpacity).clipShape(Chamfer(cut: cut)))
            .overlay(Chamfer(cut: cut)
                .strokeBorder(MarkIII.color(border, opacity: borderOpacity), lineWidth: 1))
    }
}
