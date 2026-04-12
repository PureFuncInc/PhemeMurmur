import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private var apiKey: String?

    private enum State {
        case idle
        case recording
        case transcribing
    }
    private var state: State = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load API key
        apiKey = Config.loadAPIKey()
        if apiKey == nil {
            print("Warning: API key not found at \(Config.apiKeyPath)")
            print("Create the file with your OpenAI API key:")
            print("  mkdir -p ~/.config/phememurmur")
            print("  echo 'sk-...' > ~/.config/phememurmur/api_key")
        }

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        statusMenu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit PhemeMurmur", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = statusMenu

        // Setup hotkey
        if !HotkeyManager.checkAccessibility() {
            print("Accessibility permission required. Prompting...")
            HotkeyManager.promptAccessibility()
        }

        hotkeyManager.onToggle = { [weak self] in
            self?.handleToggle()
        }

        if !hotkeyManager.start() {
            print("Failed to create event tap. Grant Accessibility permission and restart.")
            statusMenuItem.title = "Error: Need Accessibility permission"
        }

        print("PhemeMurmur ready. Press Right Shift to start/stop recording.")
    }

    private func handleToggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            // Ignore while transcribing
            break
        }
    }

    private func startRecording() {
        do {
            try audioRecorder.startRecording()
            state = .recording
            updateStatus("Recording...")
            print("🎙 Recording... Press Right Shift to stop.")
        } catch {
            print("Failed to start recording: \(error)")
            updateStatus("Error: \(error.localizedDescription)")
            setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.state == .idle else { return }
                self.updateIcon()
            }
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
                    print(">>> \(text)")
                    PasteService.pasteText(text)
                    self.state = .idle
                    self.updateStatus("Idle")
                }
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(error.localizedDescription)")
                    self.setIcon(symbolName: "exclamationmark.triangle", color: .systemOrange)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        guard let self, self.state == .idle else { return }
                        self.updateIcon()
                    }
                }
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func updateStatus(_ text: String) {
        statusMenuItem?.title = "Status: \(text)"
        updateIcon()
    }

    private func updateIcon() {
        let symbolName: String
        let color: NSColor
        switch state {
        case .idle:
            symbolName = "waveform"
            color = .secondaryLabelColor
        case .recording:
            symbolName = "record.circle"
            color = .systemRed
        case .transcribing:
            symbolName = "text.bubble"
            color = .systemBlue
        }
        setIcon(symbolName: symbolName, color: color)
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

    @objc private func quitApp() {
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
