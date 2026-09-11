import Foundation

/// A provider as the UI should present it: what the running app can actually
/// use, not merely what the config file happens to list.
struct ProviderOption: Equatable {
    let name: String
    let type: ProviderType
    /// False when this macOS version cannot run the provider at all.
    let isAvailable: Bool
    /// Secondary line under the provider name in the settings console: the
    /// model this provider would actually call, or a plain-language note for
    /// the on-device engine.
    var detail: String {
        if type == .apple { return "裝置端辨識" }
        return type.fallbackChain.first ?? type.rawValue
    }

    /// User-facing reason shown next to an unusable provider, so it reads as
    /// disabled rather than silently doing nothing when tapped.
    var unavailableReason: String? {
        isAvailable ? nil : "需要 macOS 26"
    }
}

/// Single source of truth for "which providers exist for this user on this Mac".
/// `AppDelegate` builds its live provider dictionary from the config plus the
/// built-in injection below; the settings window builds its list from the same
/// rules, so the two can no longer disagree.
enum ProviderCatalog {

    /// Name under which Apple's on-device recognition is auto-registered when the
    /// config file does not mention it.
    static let builtInAppleName = "Apple"

    /// Whether Apple's on-device recognition can run on this system.
    static var appleAvailableOnThisSystem: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Merges the configured providers with the built-in ones `AppDelegate`
    /// injects, marking anything this macOS version cannot run as unavailable.
    /// Pure so it can be unit tested for both OS branches.
    static func options(entries: [String: ProviderEntry], appleAvailable: Bool) -> [ProviderOption] {
        var options = entries.map { name, entry in
            ProviderOption(name: name,
                           type: entry.type,
                           isAvailable: entry.type != .apple || appleAvailable)
        }
        // Mirror injectBuiltInProvidersIfNeeded: users who never edited their
        // config still get Apple on macOS 26+, and must see it here too.
        if appleAvailable, !options.contains(where: { $0.name == builtInAppleName }) {
            options.append(ProviderOption(name: builtInAppleName, type: .apple, isAvailable: true))
        }
        return options.sorted { $0.name < $1.name }
    }

    /// The provider the app will actually run with: the configured one if usable,
    /// otherwise the first usable provider. Mirrors `AppDelegate`'s fallback.
    static func resolveActive(_ configured: String?, in options: [ProviderOption]) -> String {
        if let configured, options.contains(where: { $0.name == configured && $0.isAvailable }) {
            return configured
        }
        return options.first(where: \.isAvailable)?.name ?? ""
    }
}
