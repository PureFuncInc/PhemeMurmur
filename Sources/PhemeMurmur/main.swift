import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var statusLabel: NSTextField!
    private var modelMenuItem: NSMenuItem!
    private var modelLabel: NSTextField!
    private var cancelMenuItem: NSMenuItem!
    private var promptMenuItem: NSMenuItem!
    private var promptSubmenu: NSMenu!
    private var providerMenuItem: NSMenuItem!
    private var providerSubmenu: NSMenu!
    private var hotkeyMenuItem: NSMenuItem!
    private var hotkeySubmenu: NSMenu!
    private var currentHotkey: HotkeyKey = .rightShift

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let onboarding = OnboardingWindow()
    private var providers: [String: TranscriptionProvider] = [:]
    private var activeProviderName: String = ""
    private var prefix: String?
    private var promptTemplates: [String: PromptTemplate] = [:]
    private var activeTemplateName: String = Config.defaultPromptTemplateName
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
        Config.createDefaultConfigIfNeeded()
        installEditMenu()

        onboarding.showIfNeeded { [weak self] in
            self?.setupApp()
        }
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

        statusMenu.addItem(Self.makeHeaderMenuItem())
        statusMenu.addItem(NSMenuItem.separator())

        let (sItem, sLabel) = Self.makeLabelMenuItem(text: "Status: Idle")
        statusMenuItem = sItem
        statusLabel = sLabel
        statusMenu.addItem(statusMenuItem)
        let (mItem, mLabel) = Self.makeLabelMenuItem(text: "Model: —")
        modelMenuItem = mItem
        modelLabel = mLabel
        statusMenu.addItem(modelMenuItem)
        cancelMenuItem = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecordingFromMenu), keyEquivalent: "")
        cancelMenuItem.isHidden = true
        statusMenu.addItem(cancelMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        providerSubmenu = NSMenu()
        providerMenuItem = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
        statusMenu.addItem(providerMenuItem)
        statusMenu.setSubmenu(providerSubmenu, for: providerMenuItem)
        promptSubmenu = NSMenu()
        promptMenuItem = NSMenuItem(title: "Prompt", action: nil, keyEquivalent: "")
        statusMenu.addItem(promptMenuItem)
        statusMenu.setSubmenu(promptSubmenu, for: promptMenuItem)
        hotkeySubmenu = NSMenu()
        hotkeyMenuItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        statusMenu.addItem(hotkeyMenuItem)
        statusMenu.setSubmenu(hotkeySubmenu, for: hotkeyMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r"))
        statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = statusMenu

        // Load config
        if let config = Config.loadConfig() {
            let entries = config.resolvedProviders
            for (name, entry) in entries {
                providers[name] = Self.makeProvider(for: entry)
            }
            if let active = config.resolvedActiveProvider, providers[active] != nil {
                activeProviderName = active
            }
            if providers.isEmpty {
                print("Error: No API key configured in \(Config.configPath)")
                updateStatus("Error: No API key")
                showErrorIcon(persistent: true)
            } else {
                print("Providers: \(providers.keys.sorted().joined(separator: ", "))")
                print("Active provider: \(activeProviderName)")
            }
            prefix = config.prefix
            if let threshold = config.silenceThreshold {
                Config.silenceThreshold = threshold
            }
            currentHotkey = config.resolvedHotkey
            hotkeyManager.key = currentHotkey
            promptTemplates = config.promptTemplates ?? [:]
            if let saved = config.activePromptTemplate, promptTemplates[saved] != nil {
                activeTemplateName = saved
            }
        } else {
            print("Error: Failed to parse \(Config.configPath)")
            updateStatus("Error: Invalid config syntax")
            showErrorIcon(persistent: true)
        }
        rebuildProviderSubmenu()
        rebuildPromptSubmenu()
        rebuildHotkeySubmenu()

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

    private func handleToggle() {
        switch state {
        case .idle:
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

    @objc private func cancelRecordingFromMenu() {
        handleCancel()
    }

    private func startHotkeyMonitor() {
        if hotkeyManager.start() {
            print("Hotkey monitor active.")
        } else {
            print("Failed to create event tap. Grant Accessibility permission and restart.")
            updateStatus("Error: Need Accessibility permission")
            showErrorIcon(persistent: true)
        }
    }

    private func pollForAccessibility() {
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard HotkeyManager.checkAccessibility() else { return }
            timer.invalidate()
            self.accessibilityPollTimer = nil
            self.startHotkeyMonitor()
            // Only restore Idle status if there is no pre-existing provider error
            if !self.providers.isEmpty {
                self.updateStatus("Idle")
            }
            print("Accessibility granted. Hotkey monitor started automatically.")
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
            updateStatus("Error: \(error.localizedDescription)")
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
        case .tooQuiet(let rms):
            state = .idle
            updateStatus("Too quiet (RMS \(String(format: "%.3f", rms)))")
            showErrorIcon()
            print("Recording too quiet (RMS \(String(format: "%.4f", rms))).")
            return
        }

        NSSound(named: "Bottle")?.play()

        guard let provider = activeProvider else {
            state = .idle
            updateStatus("Error: No API key")
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
                await MainActor.run {
                    if finalText == "__SILENCE__" {
                        print("Silence detected by model, skipping paste.")
                        self.state = .idle
                        self.updateStatus("Idle")
                        self.refreshModelLabel()
                        return
                    }
                    let output = (self.prefix ?? "") + finalText
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                    self.refreshModelLabel()
                }
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(error.localizedDescription)")
                    self.showErrorIcon()
                    self.refreshModelLabel()
                }
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func rebuildProviderSubmenu() {
        providerSubmenu.removeAllItems()
        for name in providers.keys.sorted() {
            let item = NSMenuItem(title: name, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.representedObject = name
            item.state = (name == activeProviderName) ? .on : .off
            providerSubmenu.addItem(item)
        }
        if !activeProviderName.isEmpty {
            providerSubmenu.addItem(NSMenuItem.separator())
            let setKeyItem = NSMenuItem(
                title: "Set API Key for \(activeProviderName)…",
                action: #selector(setAPIKeyForActive),
                keyEquivalent: ""
            )
            providerSubmenu.addItem(setKeyItem)
        }
        providerMenuItem?.title = "Provider: \(activeProviderName)"
        refreshModelLabel()
    }

    private func refreshModelLabel() {
        modelLabel?.stringValue = activeProvider.map { "Model: \($0.modelName)" } ?? "Model: —"
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
                // Restore the checkmark on the current active provider.
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
            informativeText: "The key will be saved to config.jsonc.",
            style: .informational
        )
    }

    /// Shows an API-key input alert for `name`, writes the key to config.jsonc on Save, and reloads
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

        if !Config.saveAPIKey(providerName: name, apiKey: newKey) {
            let err = NSAlert()
            err.messageText = "Failed to save API key"
            err.informativeText = "Could not locate provider \"\(name)\" in config.jsonc. Please edit the file manually."
            err.alertStyle = .warning
            err.runModal()
            return false
        }

        reloadProvidersFromConfig()
        rebuildProviderSubmenu()
        print("Updated API key for \(name)")
        return true
    }

    private func reloadProvidersFromConfig() {
        guard let config = Config.loadConfig() else { return }
        providers.removeAll()
        for (n, entry) in config.resolvedProviders {
            providers[n] = Self.makeProvider(for: entry)
        }
        if providers[activeProviderName] == nil {
            activeProviderName = providers.keys.sorted().first ?? ""
        }
    }

    private func rebuildPromptSubmenu() {
        promptSubmenu.removeAllItems()
        for name in promptTemplates.keys.sorted() {
            let item = NSMenuItem(title: name, action: #selector(selectPromptTemplate(_:)), keyEquivalent: "")
            item.representedObject = name
            item.state = (name == activeTemplateName) ? .on : .off
            promptSubmenu.addItem(item)
        }
        promptMenuItem?.title = "Prompt: \(activeTemplateName)"
    }

    @objc private func selectPromptTemplate(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        activeTemplateName = name
        Config.saveActivePromptTemplate(name)
        rebuildPromptSubmenu()
        print("Switched prompt template to: \(name)")
    }

    private func rebuildHotkeySubmenu() {
        hotkeySubmenu.removeAllItems()
        for key in HotkeyKey.allCases {
            let item = NSMenuItem(title: key.displayName, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.representedObject = key.rawValue
            item.state = (key == currentHotkey) ? .on : .off
            hotkeySubmenu.addItem(item)
        }
        hotkeyMenuItem.title = "Hotkey: \(currentHotkey.shortName)"
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = HotkeyKey(rawValue: raw) else { return }
        currentHotkey = key
        hotkeyManager.key = key
        Config.saveHotkey(key)
        rebuildHotkeySubmenu()
        print("Hotkey changed to: \(key.displayName)")
    }

    private static func makeHeaderMenuItem() -> NSMenuItem {
        let headerFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(
            string: "PhemeMurmur",
            attributes: [
                .foregroundColor: NSColor.controlAccentColor,
                .font: headerFont,
            ]
        ))
        if let hash = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String, !hash.isEmpty {
            attr.append(NSAttributedString(
                string: " (\(hash))",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: headerFont,
                ]
            ))
        }

        let label = NSTextField(labelWithAttributedString: attr)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        if let appIcon = NSApp.applicationIconImage.copy() as? NSImage {
            appIcon.size = NSSize(width: 16, height: 16)
            imageView.image = appIcon
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 22),
        ])

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private static func makeProvider(for entry: ProviderEntry) -> TranscriptionProvider {
        let chain = entry.type.fallbackChain
        switch entry.type {
        case .openai:
            return FallbackProvider(chain: chain) { model in
                OpenAIProvider(apiKey: entry.apiKey, model: model)
            }
        case .gemini:
            return FallbackProvider(chain: chain) { model in
                GeminiProvider(apiKey: entry.apiKey, model: model)
            }
        }
    }

    private static func makeLabelMenuItem(text: String) -> (NSMenuItem, NSTextField) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = NSColor.labelColor
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.translatesAutoresizingMaskIntoConstraints = false

        // Match standard menu item horizontal insets (left ~20pt after the
        // leading area, right ~12pt).
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 20))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 20),
        ])

        let item = NSMenuItem()
        item.view = container
        return (item, label)
    }

    private func updateStatus(_ text: String) {
        statusLabel?.stringValue = "Status: \(text)"
        cancelMenuItem?.isHidden = state != .recording
        updateIcon()
    }

    private func updateIcon() {
        let symbolName: String
        let color: NSColor
        switch state {
        case .idle:
            symbolName = "waveform"
            color = .white
        case .recording:
            symbolName = "record.circle"
            color = .systemRed
        case .transcribing:
            symbolName = "text.bubble"
            color = .systemBlue
        }
        setIcon(symbolName: symbolName, color: color)
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

    private func setIcon(symbolName: String, color: NSColor) {
        guard let button = statusItem?.button else { return }
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular, scale: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let config = sizeConfig.applying(colorConfig)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
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

    @objc private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 2 && open \"\(bundlePath)\""]
        try? process.run()
        quitApp()
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
