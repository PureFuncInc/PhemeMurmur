import SwiftUI

/// Bridges the SwiftUI settings UI to the existing jsonc-backed Config. Reads on
/// init, writes through the same Config helpers the menu used to call.
final class SettingsStore: ObservableObject {

    /// Every provider the running app can use, including built-ins that are not
    /// in the config file, each flagged with whether this macOS version supports it.
    @Published var providerOptions: [ProviderOption] = []
    @Published var activeProvider: String = ""
    @Published var apiKey: String = ""
    @Published var hotkey: HotkeyKey = .rightShift
    @Published var templateNames: [String] = []
    @Published var activeTemplate: String = Config.defaultPromptTemplateName
    @Published var launchAtLoginEnabled: Bool = false
    @Published var voiceCommands: Bool = false
    @Published var silenceThreshold: Double = 0
    @Published var prefix: String = ""

    /// Called after any change that the AppDelegate must react to (provider swap,
    /// hotkey change, template change). Set by AppDelegate when it creates the store.
    var onChange: (() -> Void)?

    private let launchAtLogin = LaunchAtLogin()

    /// Last values read from disk, used to tell "the user has not touched this
    /// field" from "the user typed something that is not saved yet". `reload()`
    /// refreshes a field only in the former case, so opening the settings window
    /// cannot wipe a half-typed API key in the onboarding window (both share this
    /// store).
    private var loadedAPIKey = ""
    private var loadedPrefix = ""

    /// The type of the selected provider, or nil when nothing usable is selected.
    var activeProviderType: ProviderType? {
        providerOptions.first { $0.name == activeProvider }?.type
    }

    /// Whether the selected provider needs an API key at all.
    var activeProviderNeedsAPIKey: Bool {
        activeProviderType?.requiresAPIKey ?? false
    }

    /// Keeps `current` when it holds an unsaved edit, otherwise adopts `fromDisk`.
    static func mergeEditable(current: String, lastLoaded: String, fromDisk: String) -> String {
        current == lastLoaded ? fromDisk : current
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
        let diskKey = entries[activeProvider]?.apiKey ?? ""
        apiKey = Self.mergeEditable(current: apiKey, lastLoaded: loadedAPIKey, fromDisk: diskKey)
        loadedAPIKey = diskKey
        hotkey = config.resolvedHotkey
        templateNames = (config.promptTemplates ?? [:]).keys.sorted()
        activeTemplate = config.activePromptTemplate ?? Config.defaultPromptTemplateName
        voiceCommands = config.resolvedVoiceCommands
        silenceThreshold = config.silenceThreshold ?? 0
        let diskPrefix = config.prefix ?? ""
        prefix = Self.mergeEditable(current: prefix, lastLoaded: loadedPrefix, fromDisk: diskPrefix)
        loadedPrefix = diskPrefix
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }

    /// Ignores providers this macOS version cannot run, so the config file can
    /// never name an active provider the app will silently refuse to use.
    func selectProvider(_ name: String) {
        guard providerOptions.contains(where: { $0.name == name && $0.isAvailable }) else { return }
        activeProvider = name
        let diskKey = Config.loadConfig()?.resolvedProviders[name]?.apiKey ?? ""
        apiKey = diskKey
        loadedAPIKey = diskKey
        Config.saveActiveProvider(name)
        onChange?()
    }

    func saveAPIKey() {
        _ = Config.saveAPIKey(providerName: activeProvider, apiKey: apiKey)
        loadedAPIKey = apiKey
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
        loadedPrefix = prefix
        onChange?()
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.handleClick()
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }
}
