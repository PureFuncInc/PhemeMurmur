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
