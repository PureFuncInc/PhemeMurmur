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
