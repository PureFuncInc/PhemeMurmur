import XCTest
@testable import PhemeMurmur

final class ProviderCatalogTests: XCTestCase {

    private func entry(_ type: ProviderType, key: String? = nil) -> ProviderEntry {
        ProviderEntry(type: type, apiKey: key, postProcess: nil)
    }

    func testAppleIsMarkedUnavailableOnOlderSystems() {
        let options = ProviderCatalog.options(
            entries: ["Apple": entry(.apple), "OpenAI": entry(.openai, key: "sk")],
            appleAvailable: false
        )
        XCTAssertEqual(options.map(\.name), ["Apple", "OpenAI"])
        XCTAssertFalse(try XCTUnwrap(options.first { $0.name == "Apple" }).isAvailable)
        XCTAssertNotNil(try XCTUnwrap(options.first { $0.name == "Apple" }).unavailableReason)
        XCTAssertTrue(try XCTUnwrap(options.first { $0.name == "OpenAI" }).isAvailable)
    }

    func testBuiltInAppleIsListedEvenWhenTheConfigOmitsIt() {
        let options = ProviderCatalog.options(entries: ["OpenAI": entry(.openai, key: "sk")],
                                              appleAvailable: true)
        XCTAssertEqual(options.map(\.name), ["Apple", "OpenAI"])
        XCTAssertTrue(try XCTUnwrap(options.first { $0.name == "Apple" }).isAvailable)
    }

    func testBuiltInAppleIsNotInjectedWhenUnavailable() {
        let options = ProviderCatalog.options(entries: ["OpenAI": entry(.openai, key: "sk")],
                                              appleAvailable: false)
        XCTAssertEqual(options.map(\.name), ["OpenAI"])
    }

    func testConfigEntryForAppleIsNotDuplicatedByTheInjection() {
        let options = ProviderCatalog.options(entries: ["Apple": entry(.apple)], appleAvailable: true)
        XCTAssertEqual(options.map(\.name), ["Apple"])
    }

    func testResolveActiveFallsBackWhenConfiguredProviderIsUnusable() {
        let options = ProviderCatalog.options(
            entries: ["Apple": entry(.apple), "Gemini": entry(.gemini, key: "k")],
            appleAvailable: false
        )
        XCTAssertEqual(ProviderCatalog.resolveActive("Apple", in: options), "Gemini")
        XCTAssertEqual(ProviderCatalog.resolveActive("Gemini", in: options), "Gemini")
        XCTAssertEqual(ProviderCatalog.resolveActive(nil, in: options), "Gemini")
    }

    func testResolveActiveKeepsUsableConfiguredProvider() {
        let options = ProviderCatalog.options(
            entries: ["Apple": entry(.apple), "Gemini": entry(.gemini, key: "k")],
            appleAvailable: true
        )
        XCTAssertEqual(ProviderCatalog.resolveActive("Apple", in: options), "Apple")
    }

    func testResolveActiveReturnsEmptyWhenNothingIsUsable() {
        let options = ProviderCatalog.options(entries: ["Apple": entry(.apple)], appleAvailable: false)
        XCTAssertEqual(ProviderCatalog.resolveActive("Apple", in: options), "")
    }

    // MARK: - Unsaved edits survive a reload

    func testReloadAdoptsDiskValueWhenTheFieldWasUntouched() {
        XCTAssertEqual(SettingsStore.mergeEditable(current: "old", lastLoaded: "old", fromDisk: "new"),
                       "new")
    }

    func testReloadKeepsAHalfTypedValue() {
        XCTAssertEqual(SettingsStore.mergeEditable(current: "sk-typ", lastLoaded: "", fromDisk: ""),
                       "sk-typ")
        XCTAssertEqual(SettingsStore.mergeEditable(current: "sk-typ", lastLoaded: "old", fromDisk: "old"),
                       "sk-typ")
    }
}
