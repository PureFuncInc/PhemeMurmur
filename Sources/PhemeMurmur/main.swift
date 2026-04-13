import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var cancelMenuItem: NSMenuItem!
    private var escMonitor: Any?

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private var apiKey: String?
    private var prefix: String?

    private enum State {
        case idle
        case recording
        case transcribing
    }
    private var state: State = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.createDefaultConfigIfNeeded()

        // Load API key
        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        statusMenu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)
        cancelMenuItem = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecordingFromMenu), keyEquivalent: "")
        cancelMenuItem.isHidden = true
        statusMenu.addItem(cancelMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r"))
        statusItem.menu = statusMenu

        // Load config
        if let config = Config.loadConfig() {
            apiKey = config.apiKey
            prefix = config.prefix
        } else {
            print("Error: Failed to parse \(Config.configPath)")
            updateStatus("Error: Invalid config syntax")
            showErrorIcon(persistent: true)
        }

        // Setup hotkey
        hotkeyManager.onToggle = { [weak self] in
            self?.handleToggle()
        }

        if !HotkeyManager.checkAccessibility() {
            print("Accessibility permission required. Prompting...")
            HotkeyManager.promptAccessibility()
        }

        // Global Esc key monitor for cancelling recording
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 0x35 { // Escape
                self?.handleCancel()
            }
        }

        if !hotkeyManager.start() {
            print("Failed to create event tap. Grant Accessibility permission and restart.")
            updateStatus("Error: Need Accessibility permission")
            showErrorIcon(persistent: true)
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
        if let fileURL = audioRecorder.stopRecording() {
            try? FileManager.default.removeItem(at: fileURL)
        }

        state = .idle
        updateStatus("Idle")
        print("⛔ Recording cancelled.")
    }

    @objc private func cancelRecordingFromMenu() {
        handleCancel()
    }

    private func startRecording() {
        do {
            try audioRecorder.startRecording()
            state = .recording
            updateStatus("Recording...")
            print("🎙 Recording... Press Right Shift to stop, Esc to cancel.")
        } catch {
            print("Failed to start recording: \(error)")
            updateStatus("Error: \(error.localizedDescription)")
            showErrorIcon()
        }
    }

    private func stopRecordingAndTranscribe() {
        guard let fileURL = audioRecorder.stopRecording() else {
            state = .idle
            updateStatus("Idle")
            print("No audio captured or too short.")
            return
        }

        guard let apiKey = apiKey else {
            state = .idle
            updateStatus("Error: No API key")
            showErrorIcon(persistent: true)
            print("Cannot transcribe: API key not configured.")
            return
        }

        state = .transcribing
        updateStatus("Transcribing...")
        print("⏹ Stopped. Transcribing...")

        Task {
            do {
                let text = try await TranscriptionService.transcribe(fileURL: fileURL, apiKey: apiKey)
                await MainActor.run {
                    let output = (self.prefix ?? "") + text
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                }
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(error.localizedDescription)")
                    self.showErrorIcon()
                }
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func updateStatus(_ text: String) {
        statusMenuItem?.title = "Status: \(text)"
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
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
