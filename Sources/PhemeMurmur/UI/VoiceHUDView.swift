import SwiftUI

/// The Mark III voice HUD: an arc reactor inside a chamfered armour card, framed
/// by targeting brackets, with a status chip and an optional live transcript.
///
/// The card is a fixed size. Every phase occupies exactly the same rectangle so
/// the panel never resizes or re-centres as the state changes — only the colours
/// and the instrument inside it move.
struct VoiceHUDView: View {

    let phase: HUDPhase
    /// One value per beam, 0...1. All zeros renders a calm idle instrument.
    let levels: [Float]
    /// The onboarding core is rendered separately, so the HUD always shows its
    /// chip; this stays as an escape hatch for decorative reuse.
    var showsCapsule: Bool = true
    /// Text shown in the transcript area. While recording this is the live
    /// on-device preview (including the Bopomofo the recogniser emits before it
    /// settles on characters); afterwards it is the text actually pasted.
    var transcript: String = ""
    /// Whether `transcript` is still being guessed at. Drives the caret and the
    /// area's label, so a finished readout cannot be mistaken for a live one.
    var transcriptIsLive: Bool = true
    /// Whether to keep room for the transcript area at all. Batch providers
    /// (OpenAI, Gemini) never produce live text, so their card stays compact;
    /// once on-device recognition has shown any text, the slot stays reserved
    /// for the rest of the session so later phases cannot shrink the panel.
    var reservesTranscript: Bool = false

    private var presentation: HUDPresentation { phase.presentation }
    private var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    private let cut: CGFloat = 16

    /// The area stays lit while text is expected and while there is text to
    /// read; it only fades out on a failure, which has nothing to show.
    private var showsTranscript: Bool {
        LivePreviewPolicy.keepsLiveText(phase) || !transcript.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ReactorCluster(tint: presentation.coreTint,
                               ring: presentation.ringTint,
                               levels: levels,
                               speed: presentation.ringSpeed)
                Brackets(color: presentation.ringTint)
            }
            .frame(width: ReactorCluster.systemSize, height: ReactorCluster.systemSize)

            if showsCapsule {
                statusChip
                if reservesTranscript {
                    // Kept in the layout and only faded, so the card never
                    // changes size as the readout appears or clears.
                    transcriptArea
                        .opacity(showsTranscript ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        // A fixed width, not a minimum: a long error message compresses its chip
        // rather than widening and re-centring the whole panel.
        .frame(width: showsCapsule ? Self.cardWidth : nil)
        .background(cardFill)
        .clipShape(Chamfer(cut: cut))
        .overlay(ScanlineOverlay(showsSweep: false, lineOpacity: 0.03)
            .clipShape(Chamfer(cut: cut)))
        .overlay(Chamfer(cut: cut).strokeBorder(cardEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 25, y: 10)
        .shadow(color: MarkIII.color(presentation.ringTint, opacity: 0.13), radius: 20)
        .padding(24)
    }

    // MARK: - Card surfaces

    /// Frosted glass in every phase, so the HUD always sits over whatever the
    /// user is looking at rather than blanking it out. The recording state gets
    /// the thinnest, coolest tint; the others warm up slightly toward the
    /// armour colour without becoming opaque.
    private var cardFill: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            // Kept deliberately light. At the design's ~0.6 the near-black tint
            // swallows the blur and the card just looks solid, so the colour is
            // only strong enough to warm the glass, not to hide it.
            LinearGradient(colors: isRecording
                           ? [MarkIII.color((0.024, 0.024, 0.031), opacity: 0.30),
                              MarkIII.color((0.012, 0.012, 0.020), opacity: 0.24)]
                           : [MarkIII.color((0.094, 0.055, 0.055), opacity: 0.34),
                              MarkIII.color((0.035, 0.035, 0.043), opacity: 0.26)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var cardEdge: LinearGradient {
        if isRecording {
            return LinearGradient(colors: [MarkIII.color(MarkIII.hot, opacity: 0.8),
                                           MarkIII.color(MarkIII.gold, opacity: 0.6),
                                           MarkIII.color(MarkIII.crimson, opacity: 0.5)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [MarkIII.color(presentation.ringTint, opacity: 0.6),
                                       MarkIII.color(MarkIII.gold, opacity: 0.35),
                                       MarkIII.color(MarkIII.crimson, opacity: 0.25)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Status chip

    private var statusChip: some View {
        StatusChip(border: presentation.ringTint, borderOpacity: 0.4) {
            HStack(spacing: 10) {
                Diamond(color: presentation.coreTint, side: 6)
                Text(presentation.capsuleText)
                    .font(presentation.usesTelegraphicStyle
                          ? MarkIII.mono(13, .semibold)
                          : MarkIII.font(13, .semibold))
                    .kerning(presentation.usesTelegraphicStyle ? 1.6 : 0.4)
                    .foregroundStyle(MarkIII.color(MarkIII.goldBright))
                    // Error messages vary wildly in length; shrinking the label
                    // keeps the card the same size instead of stretching it.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .modifier(FlickerModifier(active: presentation.flickers))
            }
            // Chakra Petch and JetBrains Mono have different line heights, so a
            // Chinese error message would otherwise make the chip — and with it
            // the whole card — a couple of points taller than an English one.
            .frame(height: Self.chipContentHeight)
        }
    }

    // MARK: - Live transcript

    /// The transcript readout. Truncates at the *head*, so the words just spoken
    /// — or the tail of what was pasted — stay visible.
    private var transcriptArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoText(transcriptIsLive ? "LIVE TRANSCRIPT" : "PASTED",
                     size: 9, weight: .bold, tracking: 2,
                     color: MarkIII.gold, opacity: 0.75)
            HStack(alignment: .bottom, spacing: 3) {
                Text(transcript)
                    .font(MarkIII.font(12.5))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(MarkIII.color(MarkIII.ink))
                // The caret means "still being written"; a finished readout has
                // no more words coming.
                if transcriptIsLive, !transcript.isEmpty { Caret() }
                Spacer(minLength: 0)
            }
            // Always three lines tall, so the card does not grow line by line as
            // the recogniser catches up with the speaker.
            .frame(width: Self.transcriptWidth, height: Self.transcriptHeight,
                   alignment: .topLeading)
        }
        .padding(.horizontal, Self.transcriptHorizontalPadding)
        .padding(.vertical, 11)
        .background(MarkIII.color(MarkIII.gold, opacity: 0.07).clipShape(Chamfer(cut: 9)))
        .overlay(Chamfer(cut: 9)
            .strokeBorder(MarkIII.color(MarkIII.gold, opacity: 0.3), lineWidth: 1))
    }

    private static let transcriptWidth: CGFloat = 258
    private static let transcriptHorizontalPadding: CGFloat = 14
    /// Three lines of 12.5pt type at 4pt leading.
    private static let transcriptHeight: CGFloat = 56
    /// Fixed so the chip measures the same in every font and language.
    private static let chipContentHeight: CGFloat = 18
    /// Width the card always occupies, in every phase. Sized so the transcript
    /// area is the widest element and the reactor sits comfortably inside it.
    static let cardWidth = transcriptWidth + transcriptHorizontalPadding * 2 + 48
}

/// The blinking block cursor at the end of the live transcript.
private struct Caret: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(MarkIII.color(MarkIII.goldBright))
            .frame(width: 7, height: 13)
            .opacity(visible ? 1 : 0)
            .onAppear {
                // A step-end repeat, so the caret snaps rather than fades.
                withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

/// Fault-light flicker for the failed phase: mostly lit, with a brief dropout.
private struct FlickerModifier: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.55 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.12)
                    .repeatForever(autoreverses: true)
                    .delay(1.1)) {
                    dimmed = true
                }
            }
    }
}
