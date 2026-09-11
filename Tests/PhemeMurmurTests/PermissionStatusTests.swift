import XCTest
import AVFoundation
@testable import PhemeMurmur

final class PermissionStatusTests: XCTestCase {

    func testReturnsBothPermissionsInFixedOrder() {
        let items = PermissionStatus.items(accessibility: false, microphone: .notDetermined)
        XCTAssertEqual(items.map(\.kind), [.accessibility, .microphone])
    }

    func testAccessibilityGrantedIsReflected() {
        let items = PermissionStatus.items(accessibility: true, microphone: .notDetermined)
        XCTAssertTrue(items[0].granted)
    }

    func testMicrophoneAuthorizedIsGranted() {
        let items = PermissionStatus.items(accessibility: false, microphone: .authorized)
        XCTAssertTrue(items[1].granted)
    }

    func testMicrophoneDeniedIsNotGranted() {
        let items = PermissionStatus.items(accessibility: false, microphone: .denied)
        XCTAssertFalse(items[1].granted)
    }

    func testMicrophoneRestrictedIsNotGranted() {
        let items = PermissionStatus.items(accessibility: false, microphone: .restricted)
        XCTAssertFalse(items[1].granted)
    }

    func testEachKindHasChineseTitle() {
        XCTAssertEqual(PermissionKind.accessibility.title, "輔助使用")
        XCTAssertEqual(PermissionKind.microphone.title, "麥克風")
    }

    func testSettingsURLsPointAtPrivacyPanes() {
        XCTAssertEqual(PermissionKind.accessibility.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(PermissionKind.microphone.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }
}
