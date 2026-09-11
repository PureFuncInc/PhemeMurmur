import Foundation

enum OnboardingPage: Int, CaseIterable {
    case welcome
    case permissions
    case provider
    case tryIt

    var kicker: String {
        switch self {
        case .welcome: return "STEP 01 / 04"
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
            return "按下快捷鍵說話，再按一次就把文字送進你正在打字的地方。\n先花 30 秒走完四個步驟。"
        case .permissions:
            return "PhemeMurmur 需要這兩項才能聽見你的聲音、並把文字送進輸入框。"
        case .provider:
            return "選一個語音轉文字的供應商。雲端服務需要 API Key，Apple 在裝置上辨識則不用。"
        case .tryIt:
            return "按一次快捷鍵，說一句話，再按一次結束。\n看到文字出現就完成了。"
        }
    }
}

/// What the provider page shows under the picker. Derived from the same nil
/// check `canAdvance` makes, so the copy can never tell the user to continue
/// while the 繼續 button is disabled.
enum ProviderPrompt: Equatable {
    /// The selected provider needs a key: show the SecureField.
    case apiKeyField
    /// The selected provider runs on-device: nothing to fill in.
    case noKeyNeeded
    /// Nothing on this Mac can transcribe at all — the user cannot continue.
    case noUsableProvider
}

enum OnboardingFlow {

    static func providerPrompt(providerType: ProviderType?) -> ProviderPrompt {
        guard let providerType else { return .noUsableProvider }
        return providerType.requiresAPIKey ? .apiKeyField : .noKeyNeeded
    }

    /// `providerType` is the type of the currently selected provider (nil when no
    /// provider is selected at all). Whether a key is required — and whether the
    /// value typed in is a real key rather than the placeholder the default config
    /// ships — is derived from the type, so user-defined providers behave correctly.
    static func canAdvance(from page: OnboardingPage,
                           permissions: [PermissionItem],
                           providerType: ProviderType?,
                           apiKey: String,
                           didRecordOnce: Bool) -> Bool {
        switch page {
        case .welcome:
            return true
        case .permissions:
            return permissions.allSatisfy(\.granted)
        case .provider:
            guard let providerType else { return false }
            return providerType.hasUsableAPIKey(apiKey)
        case .tryIt:
            return didRecordOnce
        }
    }

    static func next(after page: OnboardingPage) -> OnboardingPage? {
        OnboardingPage(rawValue: page.rawValue + 1)
    }

    /// Whether the hotkey should be ignored because onboarding is still on
    /// screen. The `tryIt` page deliberately wants the hotkey to work, so the
    /// block lifts as soon as the user reaches it, even though the window is
    /// still open.
    static func hotkeyBlocked(onboardingActive: Bool, reachedTryIt: Bool) -> Bool {
        onboardingActive && !reachedTryIt
    }
}

extension Notification.Name {
    static let phemeDidTranscribeOnce = Notification.Name("phemeDidTranscribeOnce")
    static let phemeOnboardingReachedTryIt = Notification.Name("phemeOnboardingReachedTryIt")
}
