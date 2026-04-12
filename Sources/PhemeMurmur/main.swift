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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
            updateStatus("Recording...", icon: "mic.fill")
            print("🎙 Recording... Press Right Shift to stop.")
        } catch {
            print("Failed to start recording: \(error)")
            updateStatus("Error: \(error.localizedDescription)", icon: "mic.slash")
        }
    }

    private func stopRecordingAndTranscribe() {
        guard let fileURL = audioRecorder.stopRecording() else {
            state = .idle
            updateStatus("Idle", icon: "mic.slash")
            print("No audio captured or too short.")
            return
        }

        guard let apiKey = apiKey else {
            state = .idle
            updateStatus("Error: No API key", icon: "exclamationmark.triangle")
            print("Cannot transcribe: API key not configured.")
            return
        }

        state = .transcribing
        updateStatus("Transcribing...", icon: "ellipsis.circle")
        print("⏹ Stopped. Transcribing...")

        Task {
            do {
                let text = try await TranscriptionService.transcribe(fileURL: fileURL, apiKey: apiKey)
                await MainActor.run {
                    print(">>> \(text)")
                    PasteService.pasteText(text)
                    self.state = .idle
                    self.updateStatus("Idle", icon: "mic.slash")
                }
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(error.localizedDescription)", icon: "exclamationmark.triangle")
                }
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func updateStatus(_ text: String, icon: String) {
        statusMenuItem?.title = "Status: \(text)"
        updateIcon(name: icon)
    }

    private func updateIcon(name: String = "mic.slash") {
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "PhemeMurmur")
            image?.isTemplate = true
            button.image = image
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
