import Foundation

struct HUDPresentation {
    let coreTint: DeepSpace.RGB
    let capsuleText: String
    /// Seconds per full rotation of the orbital ring.
    let ringSpeed: Double
    /// Nil means the HUD stays until the next phase arrives.
    let autoDismissAfter: TimeInterval?

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
                coreTint: DeepSpace.auroraViolet,
                capsuleText: "LISTENING · \(Self.clock(elapsed)) · ESC",
                ringSpeed: 4.0,
                autoDismissAfter: nil
            )
        case .transcribing(let provider):
            return HUDPresentation(
                coreTint: DeepSpace.auroraCyan,
                capsuleText: "TRANSCRIBING · \(provider.uppercased()) · ESC",
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
