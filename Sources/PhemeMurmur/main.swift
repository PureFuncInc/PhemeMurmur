import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var currentHotkey: HotkeyKey = .rightShift

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let onboarding = OnboardingWindow()
    private var providers: [String: TranscriptionProvider] = [:]
    /// Provider *types*, kept alongside `providers` because `FallbackProvider`
    /// erases them and the live preview only applies to Apple's on-device engine.
    private var providerTypes: [String: ProviderType] = [:]
    private var activeProviderName: String = ""
    private var prefix: String?
    private var voiceCommandsEnabled: Bool = false
    private var promptTemplates: [String: PromptTemplate] = [:]
    private var activeTemplateName: String = Config.defaultPromptTemplateName
    private var accessibilityPollTimer: Timer?
    private let hud = RecordingHUDController()
    private var recordingStartedAt: Date?
    private var hudTickTimer: Timer?
    /// The in-flight transcription, so Esc can cancel it. Otherwise a stalled
    /// network leaves the click-through HUD on screen until URLSession's 60 s
    /// default timeout.
    private var transcriptionTask: Task<Void, Never>?
    /// Live on-device recognition preview for the HUD. Only ever non-nil while
    /// recording with the Apple provider on macOS 26+. Typed as `AnyObject` so
    /// the stored property itself needs no availability annotation.
    private var liveTranscriber: AnyObject?

    /// True from the moment the onboarding window opens until it closes
    /// (finish button or the red close button — `windowWillClose` fires on
    /// both). Used together with `onboardingReachedTryIt` to gate the hotkey.
    private var onboardingActive = false
    /// True once onboarding reaches its final page, which deliberately wants
    /// the hotkey to work.
    private var onboardingReachedTryIt = false

    private var hotkeyBlockedByOnboarding: Bool {
        OnboardingFlow.hotkeyBlocked(onboardingActive: onboardingActive, reachedTryIt: onboardingReachedTryIt)
    }

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

        // setupApp() must run before the onboarding window shows: its "try it"
        // page asks the user to record once, which only works if the hotkey
        // monitor and providers it wires up are already live.
        wireLaunchObservers()
        setupApp()

        onboardingActive = true
        onboarding.showIfNeeded { [weak self] in
            self?.onboardingActive = false
        }
    }

    private func wireLaunchObservers() {
        SettingsWindowController.shared.store.onChange = { [weak self] in
            self?.reloadProvidersFromConfig()
            self?.applyHotkeyFromConfig()
            self?.applyGeneralSettingsFromConfig()
        }
        SettingsWindowController.shared.store.isEditingElsewhere = { [weak self] in
            self?.onboardingActive ?? false
        }
        NotificationCenter.default.addObserver(
            forName: .phemeOnboardingReachedTryIt, object: nil, queue: .main
        ) { [weak self] _ in
            self?.onboardingReachedTryIt = true
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
        statusMenu.delegate = self

        statusMenuItem = NSMenuItem(title: "Status: idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)

        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(Self.makeMenuItem(title: "設定…",
                                             action: #selector(openSettings),
                                             target: self,
                                             keyEquivalent: ","))
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(Self.makeMenuItem(title: "關於 PhemeMurmur",
                                             action: #selector(showAboutPanel),
                                             target: self))
        statusMenu.addItem(Self.makeMenuItem(title: "結束",
                                             action: #selector(quitApp),
                                             target: self,
                                             keyEquivalent: "q"))
        statusItem.menu = statusMenu

        // Load config
        if let config = Config.loadConfig() {
            let entries = config.resolvedProviders
            for (name, entry) in entries {
                if let provider = Self.makeProvider(for: entry) {
                    providers[name] = provider
                    providerTypes[name] = entry.type
                } else {
                    print("Skipped provider \(name): unavailable on this macOS version")
                }
            }
            Self.injectBuiltInProvidersIfNeeded(into: &providers, types: &providerTypes)
            if let active = config.resolvedActiveProvider, providers[active] != nil {
                activeProviderName = active
            } else if !providers.isEmpty {
                activeProviderName = providers.keys.sorted().first ?? ""
            }
            if providers.isEmpty {
                print("Error: No API key configured in \(Config.configPath)")
                ErrorLog.append(context: "config-missing-api-key", message: "No API key configured in \(Config.configPath)")
                updateStatus("Error: \(Self.truncate("No API key"))")
                showErrorIcon(persistent: true)
            } else {
                print("Providers: \(providers.keys.sorted().joined(separator: ", "))")
                print("Active provider: \(activeProviderName)")
            }
            prefix = config.prefix
            voiceCommandsEnabled = config.resolvedVoiceCommands
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
            ErrorLog.append(context: "config-parse", message: "Failed to parse \(Config.configPath)")
            updateStatus("Error: \(Self.truncate("Invalid config syntax"))")
            showErrorIcon(persistent: true)
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

    /// Whether this recording should run the live text preview: Apple's
    /// on-device provider on an OS that has the streaming Speech API.
    private var shouldRunLivePreview: Bool {
        LivePreviewPolicy.shouldPreview(
            activeProviderType: providerTypes[activeProviderName],
            osSupportsLiveTranscription: ProviderCatalog.appleAvailableOnThisSystem
        )
    }

    private func startLiveTranscriptionIfSupported() {
        guard shouldRunLivePreview, #available(macOS 26.0, *) else { return }
        let transcriber = LiveSpeechTranscriber { [weak self] text in
            self?.hud.update(liveText: text)
        }
        liveTranscriber = transcriber
        transcriber.start(language: promptTemplates[activeTemplateName]?.language)
        audioRecorder.onBuffer = { [weak transcriber] buffer in
            transcriber?.feed(buffer)
        }
    }

    /// Detaches the audio tap consumer and shuts the analyzer down. Idempotent,
    /// so every recording end path can call it unconditionally.
    private func stopLiveTranscription() {
        audioRecorder.onBuffer = nil
        if #available(macOS 26.0, *), let transcriber = liveTranscriber as? LiveSpeechTranscriber {
            transcriber.stop()
        }
        liveTranscriber = nil
    }

    private func handleToggle() {
        guard !hotkeyBlockedByOnboarding else { return }
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
        switch state {
        case .idle:
            return
        case .recording:
            cancelRecording()
        case .transcribing:
            cancelTranscription()
        }
    }

    private func cancelRecording() {
        // Stop recording and discard the audio
        if case .success(let fileURL) = audioRecorder.stopRecording() {
            try? FileManager.default.removeItem(at: fileURL)
        }

        state = .idle
        updateStatus("Idle")
        NSSound(named: "Funk")?.play()
        print("⛔ Recording cancelled.")

        hudTickTimer?.invalidate()
        hudTickTimer = nil
        recordingStartedAt = nil
        audioRecorder.onLevel = nil
        stopLiveTranscription()
        hud.hide()
    }

    /// Esc during transcription: cancels the request (URLSession's async API is
    /// cancellation-aware) and takes the HUD down immediately, so a stalled
    /// network can never strand it on screen.
    private func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        state = .idle
        updateStatus("Idle")
        NSSound(named: "Funk")?.play()
        print("⛔ Transcription cancelled.")
        stopLiveTranscription()
        hud.hide()
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

            recordingStartedAt = Date()
            audioRecorder.onLevel = { [weak self] levels in
                self?.hud.update(levels: levels)
            }
            startLiveTranscriptionIfSupported()
            hud.show(.recording(elapsed: 0))
            hudTickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, let started = self.recordingStartedAt else { return }
                self.hud.show(.recording(elapsed: Date().timeIntervalSince(started)))
            }
        } catch {
            print("Failed to start recording: \(error)")
            ErrorLog.append(context: "recording-start", message: "\(error)")
            updateStatus("Error: \(Self.truncate(error.localizedDescription))")
            showErrorIcon()
        }
    }

    private func stopRecordingAndTranscribe() {
        hudTickTimer?.invalidate()
        hudTickTimer = nil
        recordingStartedAt = nil
        audioRecorder.onLevel = nil
        // Stop feeding the analyzer here, before every early return below: the
        // preview's job ends the moment the microphone does.
        stopLiveTranscription()

        let result = audioRecorder.stopRecording()
        let fileURL: URL
        switch result {
        case .success(let url):
            fileURL = url
        case .noAudio:
            state = .idle
            updateStatus("Idle")
            print("No audio captured.")
            hud.hide()
            return
        case .tooShort(let duration):
            state = .idle
            updateStatus("Too short (\(String(format: "%.1f", duration))s)")
            showErrorIcon()
            print("Recording too short (\(String(format: "%.1f", duration))s).")
            hud.hide()
            return
        case .tooQuiet(let rms):
            state = .idle
            updateStatus("Too quiet (RMS \(String(format: "%.3f", rms)))")
            showErrorIcon()
            print("Recording too quiet (RMS \(String(format: "%.4f", rms))).")
            hud.hide()
            return
        }

        NSSound(named: "Bottle")?.play()

        guard let provider = activeProvider else {
            state = .idle
            ErrorLog.append(context: "transcribe-no-provider", message: "No active provider configured")
            updateStatus("Error: \(Self.truncate("No API key"))")
            showErrorIcon(persistent: true)
            print("Cannot transcribe: No active provider configured.")
            hud.show(.failed(message: "尚未設定轉錄服務"))
            return
        }

        state = .transcribing
        updateStatus("Transcribing...")
        print("⏹ Stopped. Transcribing via \(self.activeProviderName)...")
        hud.show(.transcribing(provider: activeProviderName))

        transcriptionTask = Task {
            do {
                let template = self.promptTemplates[self.activeTemplateName]
                print("Using template: \(self.activeTemplateName) (language: \(template?.language ?? "auto"), prompt: \(template?.prompt ?? "none"))")
                let finalText = try await provider.transcribe(fileURL: fileURL, language: template?.language, prompt: template?.prompt)
                await MainActor.run {
                    // Esc already reset the UI; never paste after a cancel.
                    guard !Task.isCancelled else { return }
                    if finalText == "__SILENCE__" {
                        print("Silence detected by model, skipping paste.")
                        self.state = .idle
                        self.updateStatus("Idle")
                        self.hud.hide()
                        return
                    }
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
                    self.hud.show(.done)
                    NotificationCenter.default.post(name: .phemeDidTranscribeOnce, object: nil)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    print("Transcription failed: \(error)")
                    ErrorLog.append(context: "transcribe", message: "\(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(Self.truncate(error.localizedDescription))")
                    self.showErrorIcon()
                    self.hud.show(.failed(message: Self.truncate(error.localizedDescription)))
                }
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    private func reloadProvidersFromConfig() {
        guard let config = Config.loadConfig() else { return }
        providers.removeAll()
        providerTypes.removeAll()
        for (n, entry) in config.resolvedProviders {
            if let provider = Self.makeProvider(for: entry) {
                providers[n] = provider
                providerTypes[n] = entry.type
            }
        }
        Self.injectBuiltInProvidersIfNeeded(into: &providers, types: &providerTypes)
        if let active = config.resolvedActiveProvider, providers[active] != nil {
            activeProviderName = active
        } else if providers[activeProviderName] == nil {
            activeProviderName = providers.keys.sorted().first ?? ""
        }
    }

    /// Reapplies the hotkey read from config.jsonc to the running hotkey monitor.
    /// Extracted from the old menu's `selectHotkey(_:)` action.
    private func applyHotkeyFromConfig() {
        guard let config = Config.loadConfig() else { return }
        currentHotkey = config.resolvedHotkey
        hotkeyManager.key = currentHotkey
    }

    /// Re-reads prefix / voice-commands / silence-threshold / prompt template settings
    /// so changes made in the settings window take effect immediately, mirroring the
    /// config-loading block in `setupApp()`.
    private func applyGeneralSettingsFromConfig() {
        guard let config = Config.loadConfig() else { return }
        prefix = config.prefix
        voiceCommandsEnabled = config.resolvedVoiceCommands
        if let threshold = config.silenceThreshold {
            Config.silenceThreshold = threshold
        }
        promptTemplates = config.promptTemplates ?? [:]
        if let saved = config.activePromptTemplate, promptTemplates[saved] != nil {
            activeTemplateName = saved
        }
    }

    /// Auto-registers built-in providers that don't require any config (currently
    /// only Apple on-device speech on macOS 26+). Users who upgrade from an older
    /// version get these without editing config.jsonc; `ProviderCatalog.options`
    /// mirrors this rule so the settings window lists them too.
    private static func injectBuiltInProvidersIfNeeded(into providers: inout [String: TranscriptionProvider],
                                                       types: inout [String: ProviderType]) {
        if #available(macOS 26.0, *), providers[ProviderCatalog.builtInAppleName] == nil {
            providers[ProviderCatalog.builtInAppleName] = FallbackProvider(chain: ProviderType.apple.fallbackChain) { model in
                AppleSpeechProvider(model: model)
            }
            types[ProviderCatalog.builtInAppleName] = .apple
        }
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

    private static func makeProvider(for entry: ProviderEntry) -> TranscriptionProvider? {
        let chain = entry.type.fallbackChain
        let apiKey = entry.apiKey ?? ""
        switch entry.type {
        case .openai:
            let postProcessBaseURL = entry.postProcess?.baseURL ?? OpenAIProvider.defaultPostProcessBaseURL
            let postProcessModel = entry.postProcess?.model ?? OpenAIProvider.defaultPostProcessModel
            return FallbackProvider(chain: chain) { model in
                OpenAIProvider(
                    apiKey: apiKey,
                    model: model,
                    postProcessBaseURL: postProcessBaseURL,
                    postProcessModel: postProcessModel
                )
            }
        case .gemini:
            return FallbackProvider(chain: chain) { model in
                GeminiProvider(apiKey: apiKey, model: model)
            }
        case .apple:
            guard #available(macOS 26.0, *) else { return nil }
            return FallbackProvider(chain: chain) { model in
                AppleSpeechProvider(model: model)
            }
        }
    }

    private static func makeMenuItem(
        title: String,
        action: Selector?,
        target: AnyObject?,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
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
            setWaveformIcon()
        case .recording:
            setIcon(symbolName: "record.circle", color: .systemRed)
        case .transcribing:
            setIcon(symbolName: "text.bubble", color: .systemBlue)
        }
    }

    private func setWaveformIcon() {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarIcon.waveformTemplate()
        button.title = ""
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

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        // Status text is kept current by updateStatus() as state changes; the
        // submenus that used to need refreshing here are gone.
    }

    @objc private func quitApp() {
        accessibilityPollTimer?.invalidate()
        stopLiveTranscription()
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
