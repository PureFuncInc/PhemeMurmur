import Foundation

/// Carries the fact that an update was started across the restart the installer
/// performs.
///
/// The installer quits PhemeMurmur and launches the new copy, so the process
/// that asked for the update is never the one that can report how it went. A
/// note is left on disk before spawning the installer and read back on the next
/// launch, which is the only way to tell the user whether the thing they asked
/// for actually happened.
enum UpdateHandoff {

    /// What the launch that follows an update should tell the user.
    enum Outcome: Equatable {
        /// The running version changed, so the install took.
        case updated(from: String, to: String)
        /// An update was started but the version did not move. The installer
        /// failed somewhere after being spawned — it logs to
        /// `AppUpdater.logPath`, which is worth pointing the user at.
        case unchanged(version: String)
    }

    private static let key = "PhemeMurmurPendingUpdateFromVersion"

    static var runningVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Records the version being replaced. Called immediately before the
    /// installer is spawned.
    static func markInstallStarted(version: String = runningVersion,
                                   defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: key)
    }

    /// Drops the note without reporting, for when the installer could not even
    /// be launched and the failure is shown right away instead.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Reads and clears the note. Returns nil for an ordinary launch, so the
    /// vast majority of launches say nothing at all.
    static func consumeOutcome(currentVersion: String = runningVersion,
                               defaults: UserDefaults = .standard) -> Outcome? {
        guard let previous = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return previous == currentVersion
            ? .unchanged(version: currentVersion)
            : .updated(from: previous, to: currentVersion)
    }
}

extension Notification.Name {
    /// Posted the moment the installer is spawned, so the menu bar can show
    /// that something is happening during the seconds before the app is quit
    /// out from under the user.
    static let phemeDidStartUpdate = Notification.Name("phemeDidStartUpdate")
}
