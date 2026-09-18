import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var updateCheckTimer: Timer?
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
    private var iconAnimationTimer: Timer?
    private var iconAnimationStartedAt: Date?
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

        statusMenuItem = MarkIIIMenu.statusHeader()
        statusMenu.addItem(statusMenuItem)

        statusMenu.addItem(MarkIIIMenu.separator())
        statusMenu.addItem(MarkIIIMenu.item(title: "設定…",
                                            shortcut: "⌘,",
                                            action: #selector(openSettings),
                                            target: self,
                                            keyEquivalent: ","))
        statusMenu.addItem(MarkIIIMenu.separator())
        updateMenuItem = MarkIIIMenu.item(title: Self.checkForUpdatesTitle,
                                          action: #selector(checkForUpdates),
                                          target: self)
        statusMenu.addItem(updateMenuItem)
        statusMenu.addItem(MarkIIIMenu.item(title: "關於 PhemeMurmur",
                                            action: #selector(showAboutPanel),
                                            target: self))
        statusMenu.addItem(MarkIIIMenu.item(title: "結束",
                                            shortcut: "⌘Q",
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

        startBackgroundUpdateChecks()
        // Acknowledged as soon as the new copy comes up. Deferred to the next
        // runloop turn so the modal does not block the rest of setup, and
        // hopped to the main actor for the isolation check on this @objc path.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { UpdatePresenter.reportOutcomeOfPreviousRun() }
        }
        NotificationCenter.default.addObserver(
            forName: .phemeDidStartUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            self?.showUpdateInProgress()
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

    /// Detaches the audio tap and hands the transcriber back so the caller can
    /// await its final text. Discarding paths keep using `stopLiveTranscription`,
    /// which throws the recognised text away instead of waiting for it.
    private func detachLiveTranscriber() -> AnyObject? {
        audioRecorder.onBuffer = nil
        let transcriber = liveTranscriber
        liveTranscriber = nil
        return transcriber
    }

    /// The text the live recogniser heard, or empty when the preview never ran
    /// — an unsupported locale, assets still downloading, a cloud provider.
    ///
    /// Capped by a timeout so a wedged analyzer degrades to transcribing the
    /// recorded file rather than leaving the user with nothing pasted.
    private func liveTranscript(from run: AnyObject?) async -> String {
        guard #available(macOS 26.0, *),
              let transcriber = run as? LiveSpeechTranscriber else { return "" }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { await transcriber.finish() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? ""
        }
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
            // Decided before the first frame so the HUD reserves its transcript
            // slot up front rather than growing when partial text arrives.
            hud.reservesTranscriptArea = shouldRunLivePreview
            hud.pastedText = ""
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
            hud.show(.failed(message: Self.truncate(error.localizedDescription)))
        }
    }

    private func stopRecordingAndTranscribe() {
        hudTickTimer?.invalidate()
        hudTickTimer = nil
        recordingStartedAt = nil
        audioRecorder.onLevel = nil
        // Detach the tap here, before every early return below: the analyzer's
        // input ends the moment the microphone does. The transcriber itself is
        // kept so the task below can await its final text.
        let liveRun = detachLiveTranscriber()

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

                // What the preview showed is what gets pasted. Re-recognising the
                // recorded file would produce a second, different transcript, and
                // watching the text change after the fact is worse than the
                // accuracy that second pass buys.
                let live = await self.liveTranscript(from: liveRun)
                let finalText = live.isEmpty
                    ? try await provider.transcribe(fileURL: fileURL,
                                                    language: template?.language,
                                                    prompt: template?.prompt)
                    : live
                if !live.isEmpty { print("Using live transcript (\(live.count) chars)") }
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
                    // Shown on the done card so the last thing on screen is what
                    // actually landed in the document, not the live guess.
                    self.hud.pastedText = output
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
        // The header is telemetry, so the state goes up in mono caps and the
        // provider plus hotkey sit underneath as the current configuration.
        MarkIIIMenu.updateStatus("STATUS · \(text.uppercased())",
                                 context: menuContextLine())
        statusMenuItem?.view?.needsDisplay = true
        updateIcon()
    }

    /// "OPENAI ▪ RIGHT SHIFT" — what this app would do if you pressed the key
    /// right now.
    private func menuContextLine() -> String {
        let provider = activeProviderName.isEmpty ? "—" : activeProviderName.uppercased()
        return "\(provider) ▪ \(hotkeyManager.key.shortName.uppercased())"
    }

    private static func truncate(_ message: String, limit: Int = 60) -> String {
        let flattened = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard flattened.count > limit else { return flattened }
        let idx = flattened.index(flattened.startIndex, offsetBy: limit - 1)
        return flattened[..<idx] + "…"
    }

    // MARK: - Menu bar icon

    /// Which artwork the menu bar is currently showing. Errors are a transient
    /// overlay on top of the state machine, so they need their own case rather
    /// than another `State`.
    private enum IconState: Equatable {
        case idle, recording, transcribing, error
    }

    private var iconState: IconState = .idle

    private func updateIcon() {
        apply(iconState: {
            switch state {
            case .idle: return .idle
            case .recording: return .recording
            case .transcribing: return .transcribing
            }
        }())
    }

    private func apply(iconState newState: IconState) {
        iconState = newState
        // Only the animated states need a timer; idle and error are still frames.
        switch newState {
        case .recording, .transcribing:
            startIconAnimation()
        case .idle, .error:
            stopIconAnimation()
            renderIcon()
        }
    }

    /// Drives the recording pulse and the transcribing spinner at 20 fps.
    /// Redrawing an 18pt glyph that often is cheap enough that caching frames
    /// is not worth the complexity.
    private func startIconAnimation() {
        if iconAnimationTimer == nil {
            iconAnimationStartedAt = Date()
            iconAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0,
                                                      repeats: true) { [weak self] _ in
                self?.renderIcon()
            }
        }
        renderIcon()
    }

    private func stopIconAnimation() {
        iconAnimationTimer?.invalidate()
        iconAnimationTimer = nil
        iconAnimationStartedAt = nil
    }

    private func renderIcon() {
        guard let button = statusItem?.button else { return }
        let elapsed = iconAnimationStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        switch iconState {
        case .idle:
            button.image = MenuBarIcon.appIcon()
        case .recording:
            button.image = MenuBarIcon.recordingGlyph(
                phase: MenuBarIcon.pulsePhase(at: elapsed))
        case .transcribing:
            button.image = MenuBarIcon.transcribingGlyph(
                angle: MenuBarIcon.spinAngle(at: elapsed))
        case .error:
            button.image = MenuBarIcon.errorGlyph()
        }
        // A missing bundle icon would otherwise leave an invisible status item.
        button.title = button.image == nil ? "🗣️" : ""
    }

    private func showErrorIcon(persistent: Bool = false) {
        apply(iconState: .error)
        if !persistent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.state == .idle else { return }
                self.updateIcon()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        // The provider or hotkey can change while the menu is closed, so the
        // header is refreshed on the way open rather than only on state changes.
        MarkIIIMenu.updateStatus(MarkIIIMenu.currentStatusLine, context: menuContextLine())
        statusMenuItem?.view?.needsDisplay = true
        // Status text is kept current by updateStatus() as state changes; the
        // submenus that used to need refreshing here are gone.
    }

    // MARK: - Updates

    private static let checkForUpdatesTitle = "檢查更新…"

    /// Re-checks in the background this often. The app is a menu bar extra that
    /// can run for weeks, so waiting for a relaunch to notice a release would
    /// mean never noticing one.
    private static let updateCheckInterval: TimeInterval = 6 * 60 * 60

    /// The installer downloads and unpacks before it quits us, which is several
    /// seconds of nothing. The menu bar spins and the row says so, so the user
    /// can see that the click landed.
    private func showUpdateInProgress() {
        MarkIIIMenu.setTitle("更新中…", on: updateMenuItem)
        updateMenuItem?.isEnabled = false
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
        apply(iconState: .transcribing)
    }

    @objc private func checkForUpdates() {
        // Menu actions already arrive on the main thread; the hop just satisfies
        // the compiler's isolation check for this @objc entry point.
        Task { @MainActor in UpdatePresenter.checkAndPresent() }
    }

    /// Quietly looks for a newer release and, if there is one, restates the menu
    /// row so the user sees it without having to go looking. Failures stay
    /// silent: they are nearly always a dev build whose version is not a release
    /// tag, or a flaky network, and neither deserves an interruption.
    private func startBackgroundUpdateChecks() {
        // A build outside /Applications cannot install over itself, so offering
        // would be misleading; it keeps the plain "check" row instead.
        guard AppUpdater.canSelfUpdate else { return }
        refreshUpdateAvailability()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval,
                                                repeats: true) { [weak self] _ in
            self?.refreshUpdateAvailability()
        }
    }

    private func refreshUpdateAvailability() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let title: String
            switch await UpdateChecker().check() {
            case .updateAvailable(_, let latest, _):
                title = "更新到 \(latest)"
            case .upToDate, .failed:
                title = Self.checkForUpdatesTitle
            }
            MarkIIIMenu.setTitle(title, on: self.updateMenuItem)
        }
    }

    @objc private func quitApp() {
        accessibilityPollTimer?.invalidate()
        updateCheckTimer?.invalidate()
        stopIconAnimation()
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
