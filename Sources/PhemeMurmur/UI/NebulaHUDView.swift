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
    private let systemSize: CGFloat = 180

    @State private var ringAngle: Double = 0
    @State private var breathe = false

    private var presentation: HUDPresentation { phase.presentation }

    var body: some View {
        VStack(spacing: 17) {
            ZStack {
                corona
                ring
                core
            }
            .frame(width: systemSize, height: systemSize)

            if showsCapsule { capsule }
        }
        .padding(24)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
            spinRing(duration: presentation.ringSpeed)
        }
        .onChange(of: presentation.ringSpeed) { newSpeed in
            spinRing(duration: newSpeed)
        }
    }

    /// Advances the ring's target angle by a full turn rather than resetting to a
    /// fixed value, so a phase change (and its new ringSpeed) blends into the
    /// current rotation instead of snapping the ring back to its start position.
    private func spinRing(duration: Double) {
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            ringAngle += 360
        }
    }

    private var corona: some View {
        ZStack {
            ForEach(0..<beamCount, id: \.self) { index in
                let level = CGFloat(index < levels.count ? levels[index] : 0)
                let length = 17 + level * 53
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
                    .frame(width: 8, height: length)
                    .blur(radius: 3)
                    .offset(y: -(34 + length / 2))
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
            .frame(width: 126, height: 126)
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
            .frame(width: 68, height: 68)
            .overlay(Circle().strokeBorder(DeepSpace.color(DeepSpace.starDust, opacity: 0.28), lineWidth: 1))
            .shadow(color: DeepSpace.color(presentation.coreTint, opacity: 0.55), radius: 22)
            .scaleEffect(breathe ? 1.06 : 0.94)
    }

    private var capsule: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(DeepSpace.color(DeepSpace.auroraCyan))
                .frame(width: 6, height: 6)
                .shadow(color: DeepSpace.color(DeepSpace.auroraCyan), radius: 4)
            Text(presentation.capsuleText)
                .font(.system(size: 13, weight: .medium,
                              design: presentation.usesTelegraphicStyle ? .monospaced : .default))
                .kerning(presentation.usesTelegraphicStyle ? 1.1 : 0)
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(DeepSpace.color(DeepSpace.spaceVoidBottom, opacity: 0.6)))
                .overlay(Capsule().strokeBorder(DeepSpace.color(DeepSpace.starDust, opacity: 0.22), lineWidth: 1))
        )
    }
}
