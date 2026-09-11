import XCTest
@testable import PhemeMurmur

final class SettingsTabTests: XCTestCase {

    func testTabOrderMatchesSpec() {
        XCTAssertEqual(SettingsTab.allCases,
                       [.transcription, .hotkey, .promptTemplate, .general, .diagnostics])
    }

    func testTitlesAreTraditionalChinese() {
        XCTAssertEqual(SettingsTab.transcription.title, "轉錄服務")
        XCTAssertEqual(SettingsTab.hotkey.title, "快捷鍵")
        XCTAssertEqual(SettingsTab.promptTemplate.title, "提示模板")
        XCTAssertEqual(SettingsTab.general.title, "一般")
        XCTAssertEqual(SettingsTab.diagnostics.title, "診斷")
    }

    func testEverySymbolNameResolvesToASystemSymbol() {
        for tab in SettingsTab.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil),
                            "\(tab) has an invalid SF Symbol: \(tab.symbolName)")
        }
    }
}
