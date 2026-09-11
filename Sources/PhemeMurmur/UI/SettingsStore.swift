import SwiftUI

/// One free-text settings field that can hold an edit the user has not saved
/// yet. Pure value type, so the reload / save / discard rules are testable
/// without touching the config file.
struct EditableField: Equatable {

    /// What the UI shows and the user types into.
    var value: String = ""

    /// What was last read from (or written to) the config file.
    private(set) var loaded: String = ""

    /// True while the field holds an edit that is not on disk.
    var isDirty: Bool { value != loaded }

    /// `reload()`: adopt the value on disk, unless the user has an unsaved edit —
    /// opening the settings window must not wipe a half-typed API key in the
    /// onboarding window (both share one store).
    mutating func adopt(fromDisk: String) {
        if !isDirty { value = fromDisk }
        loaded = fromDisk
    }

    /// The value was just written to disk, or the field was replaced wholesale
    /// (switching provider): `newValue` becomes the new baseline.
    mutating func commit(_ newValue: String) {
        value = newValue
        loaded = newValue
    }

    /// The window closed without saving: throw the edit away, so it can neither
    /// be shown as if it were in effect nor be written out by a later save of a
    /// neighbouring field.
    mutating func discard() {
        value = loaded
    }
}

/// Bridges the SwiftUI settings UI to the existing jsonc-backed Config. Reads on
/// init, writes through the same Config helpers the menu used to call.
final class SettingsStore: ObservableObject {

    /// Every provider the running app can use, including built-ins that are not
    /// in the config file, each flagged with whether this macOS version supports it.
    @Published var providerOptions: [ProviderOption] = []
    @Published var activeProvider: String = ""
    @Published private var apiKeyEdit = EditableField()
    @Published var hotkey: HotkeyKey = .rightShift
    @Published var templateNames: [String] = []
    @Published var activeTemplate: String = Config.defaultPromptTemplateName
    @Published var launchAtLoginEnabled: Bool = false
    @Published var voiceCommands: Bool = false
    @Published var silenceThreshold: Double = 0
    @Published private var prefixEdit = EditableField()

    /// Free-text fields, backed by `EditableField` so an unsaved edit survives a
    /// `reload()` but is discarded when the window closes.
    var apiKey: String {
        get { apiKeyEdit.value }
        set { apiKeyEdit.value = newValue }
    }

    var prefix: String {
        get { prefixEdit.value }
        set { prefixEdit.value = newValue }
    }

    /// Called after any change that the AppDelegate must react to (provider swap,
    /// hotkey change, template change). Set by AppDelegate when it creates the store.
    var onChange: (() -> Void)?

    /// Answers "is another window still editing these shared fields?". Set once by
    /// AppDelegate, the same wiring shape as `onChange`, and backed by the
    /// `onboardingActive` flag it already keeps for the hotkey gate. Onboarding and
    /// settings share one store, so closing settings must not throw away a key the
    /// user is still typing in onboarding.
    var isEditingElsewhere: (() -> Bool)?

    private let launchAtLogin = LaunchAtLogin()

    /// The type of the selected provider, or nil when nothing usable is selected.
    var activeProviderType: ProviderType? {
        providerOptions.first { $0.name == activeProvider }?.type
    }

    /// Whether the selected provider needs an API key at all.
    var activeProviderNeedsAPIKey: Bool {
        activeProviderType?.requiresAPIKey ?? false
    }

    init() {
        reload()
    }

    func reload() {
        guard let config = Config.loadConfig() else { return }
        let entries = config.resolvedProviders
        providerOptions = ProviderCatalog.options(
            entries: entries,
            appleAvailable: ProviderCatalog.appleAvailableOnThisSystem
        )
        activeProvider = ProviderCatalog.resolveActive(config.resolvedActiveProvider, in: providerOptions)
        apiKeyEdit.adopt(fromDisk: entries[activeProvider]?.apiKey ?? "")
        hotkey = config.resolvedHotkey
        templateNames = (config.promptTemplates ?? [:]).keys.sorted()
        activeTemplate = config.activePromptTemplate ?? Config.defaultPromptTemplateName
        voiceCommands = config.resolvedVoiceCommands
        silenceThreshold = config.silenceThreshold ?? 0
        prefixEdit.adopt(fromDisk: config.prefix ?? "")
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }

    /// Ignores providers this macOS version cannot run, so the config file can
    /// never name an active provider the app will silently refuse to use.
    func selectProvider(_ name: String) {
        guard providerOptions.contains(where: { $0.name == name && $0.isAvailable }) else { return }
        activeProvider = name
        apiKeyEdit.commit(Config.loadConfig()?.resolvedProviders[name]?.apiKey ?? "")
        Config.saveActiveProvider(name)
        onChange?()
    }

    func saveAPIKey() {
        _ = Config.saveAPIKey(providerName: activeProvider, apiKey: apiKey)
        apiKeyEdit.commit(apiKey)
        onChange?()
    }

    func selectHotkey(_ key: HotkeyKey) {
        hotkey = key
        Config.saveHotkey(key)
        onChange?()
    }

    func selectTemplate(_ name: String) {
        activeTemplate = name
        Config.saveActivePromptTemplate(name)
        onChange?()
    }

    func saveGeneral() {
        Config.saveVoiceCommands(voiceCommands)
        Config.saveSilenceThreshold(silenceThreshold)
        Config.savePrefix(prefix)
        prefixEdit.commit(prefix)
        onChange?()
    }

    /// Drops edits the user typed but never saved, so an abandoned value neither
    /// lingers on screen as if it were in effect nor gets written out later by a
    /// save of a neighbouring field (`saveGeneral` writes prefix alongside the
    /// voice-commands toggle). Unconditional: this is the onboarding window's close,
    /// which owns the edit it is discarding.
    func discardUnsavedEdits() {
        apiKeyEdit.discard()
        prefixEdit.discard()
    }

    /// The settings window's close. Same discard, but skipped while another window
    /// is still editing — the edit is then not this window's to throw away.
    func discardUnsavedEditsIfIdle() {
        guard isEditingElsewhere?() != true else { return }
        discardUnsavedEdits()
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.handleClick()
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }
}
