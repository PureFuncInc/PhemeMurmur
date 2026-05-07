import AppKit
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case failed(String)
}

enum LaunchAtLoginAction: Equatable {
    case enable
    case disable
    case openSystemSettings
}

enum LaunchAtLoginError: Error, LocalizedError {
    case noExecutablePath
    var errorDescription: String? {
        switch self {
        case .noExecutablePath: return "could not resolve app executable path"
        }
    }
}

/// Wraps `SMAppService.mainApp` with a LaunchAgent plist fallback for self-signed builds
/// (where SMAppService returns `.notFound` because the cert has no Team Identifier).
///
/// State is read plist-first: if `~/Library/LaunchAgents/com.purefuncinc.PhemeMurmur.plist`
/// exists, the LaunchAgent path is in effect and we report `.enabled` regardless of what
/// SMAppService says. Otherwise we read from SMAppService.
final class LaunchAtLogin {
    private let plistURL: URL
    private(set) var state: LaunchAtLoginState

    /// Called every time `state` transitions.
    var onStateChange: ((LaunchAtLoginState) -> Void)?

    static let defaultPlistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.purefuncinc.PhemeMurmur.plist")
    }()

    static let plistLabel = "com.purefuncinc.PhemeMurmur"

    init(plistURL: URL = LaunchAtLogin.defaultPlistURL) {
        self.plistURL = plistURL
        self.state = Self.readState(plistURL: plistURL)
        print("LaunchAtLogin: initial state \(self.state)")
    }

    /// Re-reads state. Plist-first, then SMAppService. Called from `menuWillOpen` so
    /// external changes (System Settings toggle, plist deleted) sync on next menu open.
    func refresh() {
        let next = Self.readState(plistURL: plistURL)
        guard next != state else { return }
        print("LaunchAtLogin: state changed to \(next)")
        state = next
        onStateChange?(next)
    }

    /// State-aware click dispatch with SMAppService → LaunchAgent fallback on enable.
    /// `.requiresApproval` and `.failed` route to System Settings because re-`register()`-ing
    /// before the user approves is a no-op and would leave them stuck.
    func handleClick() {
        switch Self.action(for: state) {
        case .enable:
            var smaSucceeded = false
            do {
                try SMAppService.mainApp.register()
                switch SMAppService.mainApp.status {
                case .enabled, .requiresApproval:
                    smaSucceeded = true
                default:
                    smaSucceeded = false
                }
            } catch {
                print("LaunchAtLogin: SMAppService.register failed (\(error.localizedDescription)); falling back to LaunchAgent plist")
                smaSucceeded = false
            }
            if !smaSucceeded {
                guard let exec = Bundle.main.executableURL?.path else {
                    let msg = LaunchAtLoginError.noExecutablePath.localizedDescription
                    print("LaunchAtLogin: \(msg)")
                    ErrorLog.append(context: "launch-at-login", message: msg)
                    state = .failed(msg)
                    onStateChange?(state)
                    return
                }
                do {
                    try Self.writePlist(at: plistURL, executablePath: exec)
                } catch {
                    let msg = error.localizedDescription
                    print("LaunchAtLogin: plist write failed: \(msg)")
                    ErrorLog.append(context: "launch-at-login", message: "plist write failed: \(msg)")
                    state = .failed(msg)
                    onStateChange?(state)
                    return
                }
            }
            refresh()

        case .disable:
            do {
                try Self.removePlistIfPresent(at: plistURL)
            } catch {
                let msg = error.localizedDescription
                print("LaunchAtLogin: plist remove failed: \(msg)")
                ErrorLog.append(context: "launch-at-login", message: "plist remove failed: \(msg)")
                state = .failed(msg)
                onStateChange?(state)
                return
            }
            try? SMAppService.mainApp.unregister()  // best-effort
            refresh()

        case .openSystemSettings:
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    static func action(for state: LaunchAtLoginState) -> LaunchAtLoginAction {
        switch state {
        case .disabled:                      return .enable
        case .enabled:                       return .disable
        case .requiresApproval, .failed:     return .openSystemSettings
        }
    }

    /// Reads state with plist-first priority. Internal for testability.
    static func readState(plistURL: URL) -> LaunchAtLoginState {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            return .enabled
        }
        switch SMAppService.mainApp.status {
        case .enabled:           return .enabled
        case .notRegistered:     return .disabled
        case .notFound:          return .disabled  // self-signed: fallback handles enable on click
        case .requiresApproval:  return .requiresApproval
        @unknown default:        return .failed("unknown SMAppService status")
        }
    }

    /// Writes the LaunchAgent plist atomically, creating parent directories as needed.
    static func writePlist(at url: URL, executablePath: String) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let content: [String: Any] = [
            "Label": plistLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: content, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    /// Removes the plist if present. No-op when absent (idempotent).
    static func removePlistIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
