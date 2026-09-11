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

    // MARK: - Unsaved edits

    func testReloadAdoptsDiskValueWhenTheFieldWasUntouched() {
        var field = EditableField()
        field.adopt(fromDisk: "old")
        field.adopt(fromDisk: "new")
        XCTAssertEqual(field.value, "new")
    }

    /// The case IMPORTANT 5 protects: the settings window reloading the store
    /// while onboarding is still open must not wipe a half-typed key.
    func testReloadKeepsAHalfTypedValue() {
        var field = EditableField()
        field.adopt(fromDisk: "")
        field.value = "sk-typ"
        field.adopt(fromDisk: "")
        XCTAssertEqual(field.value, "sk-typ")

        var edited = EditableField()
        edited.adopt(fromDisk: "old")
        edited.value = "sk-typ"
        edited.adopt(fromDisk: "old")
        XCTAssertEqual(edited.value, "sk-typ")
    }

    func testAbandonedEditIsDiscardedOnClose() {
        var field = EditableField()
        field.adopt(fromDisk: "on-disk")
        field.value = "sk-abc"
        XCTAssertTrue(field.isDirty)

        field.discard()
        XCTAssertEqual(field.value, "on-disk")
        XCTAssertFalse(field.isDirty)
    }

    func testDiscardingAnAbandonedEditLetsLaterDiskChangesThrough() {
        var field = EditableField()
        field.adopt(fromDisk: "")
        field.value = "sk-abc"
        field.discard()
        field.adopt(fromDisk: "edited-externally")
        XCTAssertEqual(field.value, "edited-externally")
    }

    func testSavedEditSurvivesClose() {
        var field = EditableField()
        field.adopt(fromDisk: "on-disk")
        field.value = "sk-abc"
        field.commit("sk-abc")

        field.discard()
        XCTAssertEqual(field.value, "sk-abc")
        XCTAssertFalse(field.isDirty)
    }

    func testDiscardOnAnUntouchedFieldChangesNothing() {
        var field = EditableField()
        field.adopt(fromDisk: "on-disk")
        field.discard()
        XCTAssertEqual(field.value, "on-disk")
    }
    // MARK: - Who owns the edit when two windows share one store

    func testSettingsCloseKeepsTheEditWhileOnboardingIsStillOpen() {
        let store = SettingsStore()
        store.isEditingElsewhere = { true }
        store.apiKey = "sk-half-typed"

        store.discardUnsavedEditsIfIdle()
        XCTAssertEqual(store.apiKey, "sk-half-typed",
                       "the settings window must not discard onboarding's in-progress edit")
    }

    func testSettingsCloseDiscardsTheEditWhenOnboardingIsNotOpen() {
        let store = SettingsStore()
        store.isEditingElsewhere = { false }
        store.apiKey = "sk-half-typed"

        store.discardUnsavedEditsIfIdle()
        XCTAssertNotEqual(store.apiKey, "sk-half-typed")
    }

    func testOnboardingCloseDiscardsItsOwnEditUnconditionally() {
        let store = SettingsStore()
        store.isEditingElsewhere = { true }
        store.apiKey = "sk-half-typed"

        store.discardUnsavedEdits()
        XCTAssertNotEqual(store.apiKey, "sk-half-typed")
    }
}
