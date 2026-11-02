import AppKit
import PhemeMurmurCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var promptMenuItem: NSMenuItem!
    private var promptSubmenu: NSMenu!
    private var providerMenuItem: NSMenuItem!
    private var providerSubmenu: NSMenu!
    private var hotkeyMenuItem: NSMenuItem!
    private var hotkeySubmenu: NSMenu!
    private var launchAtLoginItem: NSMenuItem!
    private var currentHotkey: HotkeyKey = .rightShift

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let launchAtLogin = LaunchAtLogin()
    private var providers: [String: TranscriptionProvider] = [:]
    private var activeProviderName: String = ""
    private var prefix: String?
    private var voiceCommandsEnabled: Bool = false
    private var promptTemplates: [String: PromptTemplate] = [:]
    private var activeTemplateName: String = Config.defaultPromptTemplateName
    /// Contents of the config.json last applied, so an unchanged file isn't applied again.
    private var appliedConfigData: Data?
    private var accessibilityPollTimer: Timer?

    private var activeProvider: TranscriptionProvider? {
        providers[activeProviderName]
    }

    private enum State {
        case idle
        case recording
        case transcribing
    }
    private var state: State = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        setupApp()
    }

    /// Installs a minimal main menu containing an Edit submenu with standard Cut/Copy/Paste/Select All
    /// shortcuts. This app is LSUIElement, so the menu is not visible, but the key equivalents are
    /// required for Cmd+X/C/V/A to work inside NSAlert accessory text fields and other dialogs.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    private func setupApp() {
        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        statusMenu = NSMenu()
        statusMenu.autoenablesItems = false

        statusMenu.addItem(Self.makeMenuItem(
            title: "About PhemeMurmur",
            systemImage: "info.circle",
            action: #selector(showAboutPanel)
        ))
        statusMenu.addItem(NSMenuItem.separator())

        statusMenuItem = Self.makeMenuItem(title: "Status: Idle", systemImage: "waveform")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        providerSubmenu = NSMenu()
        providerSubmenu.autoenablesItems = false
        providerMenuItem = Self.makeMenuItem(title: "Provider", systemImage: "cloud")
        statusMenu.addItem(providerMenuItem)
        statusMenu.setSubmenu(providerSubmenu, for: providerMenuItem)

        promptSubmenu = NSMenu()
        promptSubmenu.autoenablesItems = false
        promptMenuItem = Self.makeMenuItem(title: "Prompt", systemImage: "text.bubble")
        statusMenu.addItem(promptMenuItem)
        statusMenu.setSubmenu(promptSubmenu, for: promptMenuItem)

        hotkeySubmenu = NSMenu()
        hotkeyMenuItem = Self.makeMenuItem(title: "Hotkey", systemImage: "keyboard")
        statusMenu.addItem(hotkeyMenuItem)
        statusMenu.setSubmenu(hotkeySubmenu, for: hotkeyMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        statusMenu.addItem(Self.makeMenuItem(
            title: "Open Configs & Logs Folder",
            systemImage: "folder",
            action: #selector(openConfigFolder)
        ))

        statusMenu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        statusMenu.addItem(launchAtLoginItem)

        statusMenu.addItem(NSMenuItem.separator())

        statusMenu.addItem(Self.makeMenuItem(
            title: "Quit",
            systemImage: "power",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        launchAtLogin.onStateChange = { [weak self] state in
            self?.setLaunchAtLogin(state: state)
        }
        setLaunchAtLogin(state: launchAtLogin.state)

        if !reloadConfig() {
            // Fill the submenus from defaults so they aren't empty while config.json is broken.
            rebuildSubmenus()
        }

        // Setup hotkey
        hotkeyManager.onToggle = { [weak self] in
            self?.handleToggle()
        }
        hotkeyManager.onCancel = { [weak self] in
            self?.handleCancel()
        }

        if HotkeyManager.checkAccessibility() {
            startHotkeyMonitor()
        } else {
            print("Accessibility permission required. Prompting...")
            HotkeyManager.promptAccessibility()
            if !providers.isEmpty {
                updateStatus("Waiting: Accessibility permission...")
            }
            pollForAccessibility()
        }

        print("PhemeMurmur ready. Press Right Shift to start/stop recording. Press Esc to cancel.")
    }

    /// Re-reads config.json and applies it if it changed since the last successful load.
    /// When the file can't be used, reports why and keeps the settings already applied.
    @discardableResult
    private func reloadConfig() -> Bool {
        Config.createDefaultConfigIfNeeded()
        guard let data = FileManager.default.contents(atPath: Config.configPath) else {
            reportConfigError("Cannot read \(Config.configPath)")
            return false
        }
        guard data != appliedConfigData else { return true }
        do {
            try apply(Config.parse(data))
        } catch {
            reportConfigError(error.localizedDescription)
            return false
        }
        appliedConfigData = data
        if state == .idle {
            updateStatus("Idle")
        }
        return true
    }

    /// Applies a parsed config. Throws, changing nothing, if the active prompt template has a
    /// `prompt` the active provider can't run: the menu greys that pairing out, but a hand edit can still make it.
    private func apply(_ config: ConfigFile) throws {
        var newProviders: [String: TranscriptionProvider] = [:]
        for name in config.providers.keys {
            newProviders[name] = Self.makeProvider(named: name)
        }
        let providerName = config.resolvedActiveProvider ?? ""
        let templateName = config.resolvedActivePromptTemplate ?? Config.defaultPromptTemplateName
        if config.promptTemplates?[templateName]?.prompt != nil, newProviders[providerName]?.supportsPrompt == false {
            throw ConfigError(message: "prompt-templates.\(templateName): has a \"prompt\", which the active provider \(providerName) can't run (only OpenAI providers can). Mark an OpenAI provider or a template without a \"prompt\" as \"active\".")
        }

        providers = newProviders
        activeProviderName = providerName
        print("Providers: \(providers.keys.sorted().joined(separator: ", "))")
        print("Active provider: \(activeProviderName)")
        prefix = config.prefix
        voiceCommandsEnabled = config.resolvedVoiceCommands
        currentHotkey = config.resolvedHotkey
        hotkeyManager.key = currentHotkey
        promptTemplates = config.promptTemplates ?? [:]
        activeTemplateName = templateName
        rebuildSubmenus()
    }

    /// Shows why config.json can't be used. The status line only fits the start of the message,
    /// so the full text goes in an alert.
    private func reportConfigError(_ message: String) {
        print("Error: Invalid config: \(message)")
        ErrorLog.append(context: "config-invalid", message: message)
        updateStatus("Error: \(Self.truncate("Invalid config: \(message)"))")
        showErrorIcon(persistent: true)

        // A hotkey press while the alert is open would otherwise stack another one on top.
        guard NSApp.modalWindow == nil else { return }
        let alert = NSAlert()
        alert.messageText = "config.json can't be used"
        alert.informativeText = "\(message)\n\nFix \(Config.configPath). PhemeMurmur reads it again the next time you press the hotkey."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Config.configPath)])
        }
    }

    private func handleToggle() {
        switch state {
        case .idle:
            // Pick up edits to config.json, and don't record against one that's broken.
            guard reloadConfig() else { return }
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            break // Ignore while transcribing
        }
    }

    private func handleCancel() {
        guard state == .recording else { return }

        // Stop recording and discard the audio
        if case .success(let fileURL) = audioRecorder.stopRecording() {
            try? FileManager.default.removeItem(at: fileURL)
        }

        state = .idle
        updateStatus("Idle")
        NSSound(named: "Funk")?.play()
        print("⛔ Recording cancelled.")
    }

    private func startHotkeyMonitor() {
        if hotkeyManager.start() {
            print("Hotkey monitor active.")
        } else {
            print("Failed to create event tap. Grant Accessibility permission and restart.")
            ErrorLog.append(context: "accessibility", message: "Failed to create event tap. Grant Accessibility permission and restart.")
            updateStatus("Error: \(Self.truncate("Need Accessibility permission"))")
            showErrorIcon(persistent: true)
        }
    }

    private func pollForAccessibility() {
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            guard HotkeyManager.checkAccessibility() else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                guard let self else { return }
                self.accessibilityPollTimer = nil
                self.startHotkeyMonitor()
                if !self.providers.isEmpty {
                    self.updateStatus("Idle")
                }
                print("Accessibility granted. Hotkey monitor started automatically.")
            }
        }
    }

    private func startRecording() {
        do {
            try audioRecorder.startRecording()
            state = .recording
            updateStatus("Recording...")
            NSSound(named: "Glass")?.play()
            print("🎙 Recording... Press Right Shift to stop, Esc to cancel.")
        } catch {
            print("Failed to start recording: \(error)")
            ErrorLog.append(context: "recording-start", message: "\(error)")
            updateStatus("Error: \(Self.truncate(error.localizedDescription))")
            showErrorIcon()
        }
    }

    private func stopRecordingAndTranscribe() {
        let result = audioRecorder.stopRecording()
        let fileURL: URL
        switch result {
        case .success(let url):
            fileURL = url
        case .noAudio:
            state = .idle
            updateStatus("Idle")
            print("No audio captured.")
            return
        case .tooShort(let duration):
            state = .idle
            updateStatus("Too short (\(String(format: "%.1f", duration))s)")
            showErrorIcon()
            print("Recording too short (\(String(format: "%.1f", duration))s).")
            return
        }

        NSSound(named: "Bottle")?.play()

        guard let provider = activeProvider else {
            state = .idle
            ErrorLog.append(context: "transcribe-no-provider", message: "No active provider configured")
            updateStatus("Error: \(Self.truncate("No API key"))")
            showErrorIcon(persistent: true)
            print("Cannot transcribe: No active provider configured.")
            return
        }

        state = .transcribing
        updateStatus("Transcribing...")
        print("⏹ Stopped. Transcribing via \(self.activeProviderName)...")

        Task {
            do {
                let template = self.promptTemplates[self.activeTemplateName]
                print("Using template: \(self.activeTemplateName) (language: \(template?.language ?? "auto"), prompt: \(template?.prompt ?? "none"))")
                let finalText = try await provider.transcribe(fileURL: fileURL, language: template?.language, prompt: template?.prompt)
                if finalText == "__SILENCE__" {
                    print("Silence detected by model, skipping paste.")
                    self.state = .idle
                    self.updateStatus("Idle")
                    self.refreshProviderLabel()
                } else {
                    let processed: String
                    if self.voiceCommandsEnabled, template?.prompt == nil {
                        processed = VoiceCommandProcessor.process(finalText)
                    } else {
                        processed = finalText
                    }
                    let output = (self.prefix ?? "") + processed
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                    self.refreshProviderLabel()
                }
            } catch {
                print("Transcription failed: \(error)")
                ErrorLog.append(context: "transcribe", message: "\(error)")
                self.state = .idle
                self.updateStatus("Error: \(Self.truncate(error.localizedDescription))")
                self.showErrorIcon()
                self.refreshProviderLabel()
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func rebuildSubmenus() {
        rebuildProviderSubmenu()
        rebuildPromptSubmenu()
        rebuildHotkeySubmenu()
    }

    private func rebuildProviderSubmenu() {
        providerSubmenu.removeAllItems()
        let templateHasPrompt = promptTemplates[activeTemplateName]?.prompt != nil
        for name in providers.keys.sorted() {
            let item = NSMenuItem(title: name, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.representedObject = name
            item.image = (name == activeProviderName) ? Self.enabledImage() : nil
            if templateHasPrompt, providers[name]?.supportsPrompt == false {
                item.isEnabled = false
                item.toolTip = "\(activeTemplateName) is OpenAI only"
            }
            providerSubmenu.addItem(item)
        }
        if activeProvider?.requiresAPIKey == true {
            providerSubmenu.addItem(NSMenuItem.separator())
            let setKeyItem = NSMenuItem(
                title: "Set API Key for \(activeProviderName)…",
                action: #selector(setAPIKeyForActive),
                keyEquivalent: ""
            )
            providerSubmenu.addItem(setKeyItem)
        }
        refreshProviderLabel()
    }

    private func refreshProviderLabel() {
        if let provider = activeProvider {
            providerMenuItem?.title = "Provider: \(activeProviderName) (\(provider.modelName))"
        } else {
            providerMenuItem?.title = "Provider"
        }
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        if let provider = providers[name], !provider.isKeyConfigured {
            // Warn the user and offer to enter a key. Only switch if the key is saved.
            let saved = runAPIKeyPrompt(
                for: name,
                messageText: "API key not set for \(name)",
                informativeText: "Enter an API key to start using \(name).",
                style: .warning
            )
            guard saved else {
                // Restore the green check on the current active provider.
                rebuildProviderSubmenu()
                return
            }
        }
        activateProvider(name)
    }

    private func activateProvider(_ name: String) {
        activeProviderName = name
        Config.saveActiveProvider(name)
        rebuildProviderSubmenu()
        rebuildPromptSubmenu()
        if state == .idle {
            updateStatus("Idle")
        }
        print("Switched provider to: \(name)")
    }

    @objc private func setAPIKeyForActive() {
        let name = activeProviderName
        guard !name.isEmpty else { return }
        _ = runAPIKeyPrompt(
            for: name,
            messageText: "Set API Key for \(name)",
            informativeText: "The key will be saved to the Keychain.",
            style: .informational
        )
    }

    /// Shows an API-key input alert for `name`, writes the key to the Keychain on Save, and reloads
    /// the provider instance so the new key takes effect immediately. Returns true iff a key was saved.
    @discardableResult
    private func runAPIKeyPrompt(
        for name: String,
        messageText: String,
        informativeText: String,
        style: NSAlert.Style
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = style
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.placeholderString = "API key"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        let newKey = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return false }

        let status = Keychain.saveAPIKey(newKey, for: name)
        if status != errSecSuccess {
            ErrorLog.append(context: "keychain-save", message: "\(name): \(Keychain.message(for: status))")
            let err = NSAlert()
            err.messageText = "Failed to save API key"
            err.informativeText = "Could not save the key to the Keychain: \(Keychain.message(for: status))"
            err.alertStyle = .warning
            err.runModal()
            return false
        }

        // Providers read their key when they're created, so rebuild them even though config.json is unchanged.
        appliedConfigData = nil
        reloadConfig()
        print("Updated API key for \(name)")
        return true
    }

    private func rebuildPromptSubmenu() {
        promptSubmenu.removeAllItems()
        let providerSupportsPrompt = activeProvider?.supportsPrompt ?? true
        for (name, template) in promptTemplates.sorted(by: { $0.key < $1.key }) {
            // Post-processing prompts run through OpenAI chat completions; Apple can't apply them.
            let hasPrompt = template.prompt != nil
            let title = hasPrompt ? "\(name) (OpenAI only)" : name
            let item = NSMenuItem(title: title, action: #selector(selectPromptTemplate(_:)), keyEquivalent: "")
            item.representedObject = name
            item.image = (name == activeTemplateName) ? Self.enabledImage() : nil
            item.isEnabled = !hasPrompt || providerSupportsPrompt
            promptSubmenu.addItem(item)
        }
        promptMenuItem?.title = "Prompt: \(activeTemplateName)"
    }

    @objc private func selectPromptTemplate(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        activeTemplateName = name
        Config.saveActivePromptTemplate(name)
        rebuildPromptSubmenu()
        rebuildProviderSubmenu()
        print("Switched prompt template to: \(name)")
    }

    private func rebuildHotkeySubmenu() {
        hotkeySubmenu.removeAllItems()
        for key in HotkeyKey.allCases {
            let item = NSMenuItem(title: key.displayName, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.representedObject = key.rawValue
            item.image = (key == currentHotkey) ? Self.enabledImage() : nil
            hotkeySubmenu.addItem(item)
        }
        hotkeyMenuItem.title = "Hotkey: \(currentHotkey.shortName)"
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = HotkeyKey(rawValue: raw) else { return }
        currentHotkey = key
        hotkeyManager.key = key
        Config.saveHotkey(key.rawValue)
        rebuildHotkeySubmenu()
        print("Hotkey changed to: \(key.displayName)")
    }

    @objc private func showAboutPanel() {
        let hash = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? ""
        let date = Bundle.main.object(forInfoDictionaryKey: "GitCommitDate") as? String ?? ""

        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        let detail = [hash, date].filter { !$0.isEmpty }.joined(separator: ",")
        if !detail.isEmpty {
            options[.applicationVersion] = detail
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    private static func makeProvider(named name: String) -> TranscriptionProvider {
        let type = ProviderType(providerName: name)
        let chain = type.fallbackChain
        switch type {
        case .openai:
            let apiKey = Keychain.apiKey(for: name) ?? ""
            return FallbackProvider(chain: chain) { model in
                OpenAIProvider(apiKey: apiKey, model: model)
            }
        case .apple:
            return FallbackProvider(chain: chain) { model in
                AppleSpeechProvider(model: model)
            }
        }
    }

    private static func makeMenuItem(
        title: String,
        systemImage: String,
        action: Selector? = nil,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        return item
    }

    private static func enabledImage() -> NSImage? {
        let palette = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
        let size = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Enabled")?
            .withSymbolConfiguration(size.applying(palette))
    }

    private static func infoImage() -> NSImage? {
        let palette = NSImage.SymbolConfiguration(paletteColors: [.systemGray])
        let size = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Needs attention")?
            .withSymbolConfiguration(size.applying(palette))
    }

    private func setLaunchAtLogin(state: LaunchAtLoginState) {
        // Always render via image; never use NSMenuItem.state to avoid stacking the
        // macOS-native checkmark on top of our green check.
        launchAtLoginItem.state = .off
        switch state {
        case .enabled:
            launchAtLoginItem.image = Self.enabledImage()
            launchAtLoginItem.toolTip = nil
        case .disabled:
            launchAtLoginItem.image = nil
            launchAtLoginItem.toolTip = nil
        case .requiresApproval:
            launchAtLoginItem.image = Self.infoImage()
            launchAtLoginItem.toolTip = "Approve in System Settings → General → Login Items"
        case .failed(let msg):
            launchAtLoginItem.image = Self.infoImage()
            launchAtLoginItem.toolTip = msg
        }
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.handleClick()
    }

    private func updateStatus(_ text: String) {
        statusMenuItem?.title = "Status: \(text)"
        updateIcon()
    }

    private static func truncate(_ message: String, limit: Int = 60) -> String {
        let flattened = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard flattened.count > limit else { return flattened }
        let idx = flattened.index(flattened.startIndex, offsetBy: limit - 1)
        return flattened[..<idx] + "…"
    }

    private func updateIcon() {
        switch state {
        case .idle:
            setIcon(symbolName: "waveform", color: nil)
        case .recording:
            setIcon(symbolName: "record.circle", color: .systemRed)
        case .transcribing:
            setIcon(symbolName: "text.bubble", color: .systemBlue)
        }
    }

    private func showErrorIcon(persistent: Bool = false) {
        setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)
        if !persistent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.state == .idle else { return }
                self.updateIcon()
            }
        }
    }

    private func setIcon(symbolName: String, color: NSColor?) {
        guard let button = statusItem?.button else { return }
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular, scale: .medium)
        let config: NSImage.SymbolConfiguration
        if let color {
            config = sizeConfig.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        } else {
            config = sizeConfig
        }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = (color == nil)
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "🗣️"
        }
    }

    @objc private func openConfigFolder() {
        let url = URL(fileURLWithPath: (Config.configPath as NSString).deletingLastPathComponent)
        NSWorkspace.shared.open(url)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        launchAtLogin.refresh()
    }

    @objc private func quitApp() {
        accessibilityPollTimer?.invalidate()
        if audioRecorder.isRecording {
            _ = audioRecorder.stopRecording()
        }
        hotkeyManager.stop()
        NSApplication.shared.terminate(nil)
    }
}

// --- Entry point ---
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
