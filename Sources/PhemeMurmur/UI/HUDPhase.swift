import Foundation

struct HUDPresentation {
    /// Tint of the reactor core and its beams.
    let coreTint: MarkIII.RGB
    /// Tint of the ticked bezel, the sweeping arc and the framing brackets.
    let ringTint: MarkIII.RGB
    let capsuleText: String
    /// Seconds per full rotation of the sweeping arc. Larger is slower; the
    /// ticked bezel takes four times as long again.
    let ringSpeed: Double
    /// Nil means the HUD stays until the next phase arrives.
    let autoDismissAfter: TimeInterval?
    /// Failure flickers its label like a fault light; the other phases hold steady.
    var flickers: Bool = false

    /// Shortest time this phase stays on screen before the next one may replace
    /// it. On-device recognition can finish in well under a tenth of a second,
    /// which would otherwise flash TRANSCRIBING for a few frames and read as a
    /// glitch rather than a state. Only delays the HUD — the transcribed text is
    /// pasted as soon as it arrives either way.
    var minimumDwell: TimeInterval = 0

    /// The monospaced + letter-spaced capsule treatment is designed for the
    /// English telegraphic states (LISTENING / TRANSCRIBING / DONE). Chinese
    /// text — error messages such as "尚未設定轉錄服務" — must render in the
    /// normal face without kerning, or the letter-spacing looks broken.
    var usesTelegraphicStyle: Bool {
        !HUDPresentation.containsHanCharacters(capsuleText)
    }

    static func containsHanCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)   // CJK ext A
                || (0x4E00...0x9FFF).contains(scalar.value)   // CJK unified
                || (0xF900...0xFAFF).contains(scalar.value)   // compatibility
        }
    }
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
                coreTint: MarkIII.hot,
                ringTint: MarkIII.hot,
                capsuleText: "LISTENING · \(Self.clock(elapsed)) · ESC",
                ringSpeed: 7.0,
                autoDismissAfter: nil
            )
        case .transcribing(let provider):
            return HUDPresentation(
                coreTint: MarkIII.gold,
                ringTint: MarkIII.gold,
                capsuleText: "TRANSCRIBING · \(provider.uppercased()) · ESC",
                ringSpeed: 3.0,
                autoDismissAfter: nil,
                minimumDwell: 0.45
            )
        case .done:
            return HUDPresentation(
                coreTint: MarkIII.arc,
                ringTint: MarkIII.arc,
                capsuleText: "DONE",
                // Done is the calmest state: the instrument is winding down, so
                // it turns slower than anything else.
                ringSpeed: 14.0,
                // The text is already in the document by now, so this is a
                // glance of confirmation, not something to read. Anything longer
                // just sits in front of what the user is looking at.
                autoDismissAfter: 0.7
            )
        case .failed(let message):
            return HUDPresentation(
                coreTint: MarkIII.crimson,
                ringTint: MarkIII.crimson,
                capsuleText: message,
                ringSpeed: 10.0,
                autoDismissAfter: 3.0,
                flickers: true
            )
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
