import Foundation

/// Installs a newer PhemeMurmur by running the very same `install.sh` that the
/// README's `curl … | bash` one-liner uses. That script already knows how to
/// pick the right architecture's release zip, quit the running app, replace
/// `/Applications/PhemeMurmur.app`, strip the quarantine flag and relaunch.
/// Reimplementing any of that in Swift would be a second copy of the tricky
/// part. `make app` copies the script into the bundle, so the app runs the
/// version it shipped with rather than one fetched at update time.
///
/// Worth knowing: the script targets `/Applications/PhemeMurmur.app` no matter
/// where the running copy lives. `canSelfUpdate` is what keeps that honest.
enum AppUpdater {

    enum Failure: Error, LocalizedError, Equatable {
        case scriptMissing
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing:
                return "這個版本沒有內建安裝程式，請改從 GitHub 下載更新。"
            case .launchFailed(let message):
                return "無法啟動安裝程式：\(message)"
            }
        }
    }

    static let logPath = "/tmp/pheme-murmur-update.log"

    /// The installer shipped inside this bundle, or nil for a build assembled
    /// before the Makefile started copying it in.
    static var bundledScript: URL? {
        Bundle.main.url(forResource: "install", withExtension: "sh")
    }

    /// Whether this copy is the one `install.sh` would replace. The script
    /// targets `/Applications/PhemeMurmur.app` specifically, so a build running
    /// from anywhere else — the repo's own bundle, a copy on the Desktop — must
    /// not offer to self-update: it would replace and relaunch a *different*
    /// app than the one in front of the user.
    static var canSelfUpdate: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
    }

    /// Single-quotes `value` for `/bin/bash`, escaping embedded apostrophes: an
    /// app bundle can sit under a path with spaces or quotes in it.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The one-liner that runs `script` detached from this process. `nohup … &`
    /// is load-bearing: the script's first act is to quit PhemeMurmur, so it has
    /// to outlive the app that spawned it. Pure and static so the quoting is
    /// testable without spawning anything.
    static func detachedCommand(script: String, log: String = logPath) -> String {
        "nohup /bin/bash \(shellQuoted(script)) > \(shellQuoted(log)) 2>&1 &"
    }

    /// Spawns the installer and returns immediately. There is nothing to await:
    /// the app keeps running until the script's quit reaches it a second later,
    /// and from then on the installer owns the outcome, logging to `logPath`.
    static func run(script: URL? = bundledScript) throws {
        guard let script else { throw Failure.scriptMissing }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", detachedCommand(script: script.path)]
        do {
            try process.run()
        } catch {
            throw Failure.launchFailed(error.localizedDescription)
        }
    }
}
