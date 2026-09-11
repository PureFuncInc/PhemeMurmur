import SwiftUI

/// Bridges the SwiftUI settings UI to the existing jsonc-backed Config. Reads on
/// init, writes through the same Config helpers the menu used to call.
final class SettingsStore: ObservableObject {

    @Published var providerNames: [String] = []
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

    init() {
        reload()
    }

    func reload() {
        guard let config = Config.loadConfig() else { return }
        let entries = config.resolvedProviders
        providerNames = entries.keys.sorted()
        activeProvider = config.resolvedActiveProvider ?? ""
        apiKey = entries[activeProvider]?.apiKey ?? ""
        hotkey = config.resolvedHotkey
        templateNames = (config.promptTemplates ?? [:]).keys.sorted()
        activeTemplate = config.activePromptTemplate ?? Config.defaultPromptTemplateName
        voiceCommands = config.resolvedVoiceCommands
        silenceThreshold = config.silenceThreshold ?? 0
        prefix = config.prefix ?? ""
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }

    func selectProvider(_ name: String) {
        activeProvider = name
        apiKey = Config.loadConfig()?.resolvedProviders[name]?.apiKey ?? ""
        Config.saveActiveProvider(name)
        onChange?()
    }

    func saveAPIKey() {
        _ = Config.saveAPIKey(providerName: activeProvider, apiKey: apiKey)
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
        onChange?()
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.handleClick()
        launchAtLogin.refresh()
        launchAtLoginEnabled = launchAtLogin.state == .enabled
    }
}
