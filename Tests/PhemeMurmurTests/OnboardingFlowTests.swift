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
                                                hasAPIKey: false, didRecordOnce: false))
    }

    func testPermissionsBlockUntilAllGranted() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .permissions, permissions: missingMic,
                                                 hasAPIKey: false, didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .permissions, permissions: granted,
                                                hasAPIKey: false, didRecordOnce: false))
    }

    func testProviderBlocksUntilAPIKeyPresent() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                                 hasAPIKey: false, didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .provider, permissions: granted,
                                               hasAPIKey: true, didRecordOnce: false))
    }

    func testTryItBlocksUntilOneSuccessfulRecording() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .tryIt, permissions: granted,
                                                 hasAPIKey: true, didRecordOnce: false))
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .tryIt, permissions: granted,
                                               hasAPIKey: true, didRecordOnce: true))
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
}
