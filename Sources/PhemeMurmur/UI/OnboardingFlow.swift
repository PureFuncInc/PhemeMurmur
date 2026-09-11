import CoreGraphics
import Foundation

enum OnboardingPage: Int, CaseIterable {
    case welcome
    case permissions
    case provider
    case tryIt

    var kicker: String {
        switch self {
        case .welcome: return "BOOT SEQ · 1 OF 4"
        case .permissions: return "BOOT SEQ · 2 OF 4"
        case .provider: return "BOOT SEQ · 3 OF 4"
        case .tryIt: return "BOOT SEQ · 4 OF 4"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "系統上線"
        case .permissions: return "解鎖兩道權限"
        case .provider: return "指定轉錄引擎"
        case .tryIt: return "校準一次"
        }
    }

    /// The boot sequence gives the opening page a larger title than the rest.
    var titleSize: CGFloat {
        switch self {
        case .welcome: return 30
        case .permissions, .provider: return 24
        case .tryIt: return 26
        }
    }

    /// Label on the advance button. The last page completes the calibration
    /// rather than continuing to another step.
    var ctaTitle: String {
        self == .tryIt ? "完成校準" : "繼續"
    }

    var body: String {
        switch self {
        case .welcome:
            return "「早安。語音通道已就緒。」\n按下快捷鍵說話，再按一次，文字就會出現在你正在打字的地方。\n先花 30 秒走完這四道程序。"
        case .permissions:
            return "沒有這兩項，我聽不見你，也沒辦法幫你把字送出去。"
        case .provider:
            return "雲端引擎需要 API Key；Apple 在裝置上辨識則不用。"
        case .tryIt:
            return "按一次快捷鍵，說一句話，再按一次結束。\n看到文字出現，校準就完成了。"
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
