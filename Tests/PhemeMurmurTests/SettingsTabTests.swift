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

    func testEveryTabHasARailGlyph() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.glyph.isEmpty, "\(tab) has no rail glyph")
        }
        // The glyphs are the rail's only per-tab marker, so a duplicate would
        // make two channels indistinguishable at a glance.
        let glyphs = SettingsTab.allCases.map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "rail glyphs must be unique")
    }

    func testChannelCodesAreNumberedInRailOrder() {
        XCTAssertEqual(SettingsTab.allCases.map(\.channelCode),
                       ["CH-01 / TRANSCRIBE", "CH-02 / TRIGGER", "CH-03 / PROTOCOL",
                        "CH-04 / SYSTEM", "CH-05 / DIAGNOSTIC"])
    }

    func testEveryTabHasASubtitle() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.subtitle.isEmpty, "\(tab) has no pane subtitle")
        }
    }
}
