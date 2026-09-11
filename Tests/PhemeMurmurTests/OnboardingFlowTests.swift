import XCTest
@testable import PhemeMurmur

final class OnboardingFlowTests: XCTestCase {

    private let granted = [
        PermissionItem(kind: .accessibility, granted: true),
        PermissionItem(kind: .microphone, granted: true),
    ]
    private let missingMic = [
        PermissionItem(kind: .accessibility, granted: true),
        PermissionItem(kind: .microphone, granted: false),
    ]

    func testPageOrder() {
        XCTAssertEqual(OnboardingPage.allCases, [.welcome, .permissions, .provider, .tryIt])
    }

    func testWelcomeAlwaysAdvances() {
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .welcome, permissions: missingMic,
                                                providerType: nil, apiKey: "", didRecordOnce: false))
    }

    func testPermissionsBlockUntilAllGranted() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .permissions, permissions: missingMic,
                                                 providerType: nil, apiKey: "", didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .permissions, permissions: granted,
                                                providerType: nil, apiKey: "", didRecordOnce: false))
    }

    func testProviderBlocksUntilAPIKeyPresentForKeyedProviders() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                 providerType: .openai, apiKey: "", didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                providerType: .openai, apiKey: "sk-real", didRecordOnce: false))
    }

    func testProviderAdvancesWithoutKeyForOnDeviceProvider() {
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                providerType: .apple, apiKey: "", didRecordOnce: false))
    }

    func testProviderRejectsTheDefaultConfigPlaceholders() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                 providerType: .openai, apiKey: "sk-proj-xxx", didRecordOnce: false))
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                 providerType: .gemini, apiKey: " AIzaxxx ", didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                providerType: .gemini, apiKey: "AIzaReal", didRecordOnce: false))
    }

    func testProviderBlocksWhenNoProviderIsSelected() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                 providerType: nil, apiKey: "sk-real", didRecordOnce: false))
    }

    /// The default config ships the placeholders this asserts on; if they ever
    /// change, `ProviderType.placeholderAPIKey` must change with them.
    func testDefaultConfigPlaceholdersAreTheOnesWeTreatAsUnset() {
        XCTAssertTrue(Config.defaultConfigContent.contains(ProviderType.openai.placeholderAPIKey ?? ""))
        XCTAssertTrue(Config.defaultConfigContent.contains(ProviderType.gemini.placeholderAPIKey ?? ""))
    }

    func testKickersAreASequentialFourStepRun() {
        XCTAssertEqual(OnboardingPage.allCases.map(\.kicker),
                       ["STEP 01 / 04", "STEP 02 / 04", "STEP 03 / 04", "STEP 04 / 04"])
        XCTAssertEqual(OnboardingPage.allCases.count, 4)
    }

    func testWelcomeCopyMatchesTheNumberOfSteps() {
        XCTAssertTrue(OnboardingPage.welcome.body.contains("四"),
                      "welcome copy must not promise a different number of steps than there are dots")
    }

    func testTryItBlocksUntilOneSuccessfulRecording() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .tryIt, permissions: granted,
                                                 providerType: .openai, apiKey: "sk-real", didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .tryIt, permissions: granted,
                                               providerType: .openai, apiKey: "sk-real", didRecordOnce: true))
    }

    func testNextWalksForwardAndStopsAtEnd() {
        XCTAssertEqual(OnboardingFlow.next(after: .welcome), .permissions)
        XCTAssertEqual(OnboardingFlow.next(after: .permissions), .provider)
        XCTAssertEqual(OnboardingFlow.next(after: .provider), .tryIt)
        XCTAssertNil(OnboardingFlow.next(after: .tryIt))
    }

    func testEveryPageHasChineseCopy() {
        for page in OnboardingPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.body.isEmpty)
        }
    }

    func testHotkeyBlockedOnlyWhileOnboardingActiveAndBeforeTryIt() {
        XCTAssertFalse(OnboardingFlow.hotkeyBlocked(onboardingActive: false, reachedTryIt: false))
        XCTAssertFalse(OnboardingFlow.hotkeyBlocked(onboardingActive: false, reachedTryIt: true))
        XCTAssertTrue(OnboardingFlow.hotkeyBlocked(onboardingActive: true, reachedTryIt: false))
        XCTAssertFalse(OnboardingFlow.hotkeyBlocked(onboardingActive: true, reachedTryIt: true))
    }
    // MARK: - Provider page copy

    func testProviderPromptAsksForAKeyOnlyWhenTheProviderNeedsOne() {
        XCTAssertEqual(OnboardingFlow.providerPrompt(providerType: .openai), .apiKeyField)
        XCTAssertEqual(OnboardingFlow.providerPrompt(providerType: .gemini), .apiKeyField)
        XCTAssertEqual(OnboardingFlow.providerPrompt(providerType: .apple), .noKeyNeeded)
    }

    /// The dead end: with no usable provider the page used to say "just continue"
    /// while canAdvance kept 繼續 disabled.
    func testProviderPromptReportsTheDeadEndWhenNothingIsUsable() {
        XCTAssertEqual(OnboardingFlow.providerPrompt(providerType: nil), .noUsableProvider)
    }

    func testNoUsableProviderPromptAgreesWithTheDisabledButton() {
        for type in [ProviderType?.none, .some(.openai), .some(.apple)] {
            let prompt = OnboardingFlow.providerPrompt(providerType: type)
            let canAdvance = OnboardingFlow.canAdvance(from: .provider,
                                                       permissions: [],
                                                       providerType: type,
                                                       apiKey: "sk-real-key",
                                                       didRecordOnce: false)
            XCTAssertEqual(prompt == .noUsableProvider, !canAdvance,
                           "the copy must never invite the user to continue while 繼續 is disabled")
        }
    }
}
