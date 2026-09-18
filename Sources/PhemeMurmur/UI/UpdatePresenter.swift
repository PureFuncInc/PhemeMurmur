import AppKit

/// Pure mapping from an `UpdateOutcome` to the strings and buttons an `NSAlert`
/// needs. Kept apart from the presenter so the copy is unit testable without
/// touching AppKit.
struct UpdateAlertContent: Equatable {
    let title: String
    let informative: String
    /// Button titles; the first is the default. For an available update that
    /// this copy can install itself, choosing it starts the installer.
    let buttons: [String]
    /// Set when the first button should open the release page instead of
    /// installing — the escape hatch for a build that cannot self-update.
    let downloadURL: URL?
    /// Whether the first button installs in place.
    let installs: Bool

    init(outcome: UpdateOutcome, canSelfUpdate: Bool) {
        switch outcome {
        case .upToDate(let current):
            title = "已是最新版本"
            informative = "PhemeMurmur \(current) 就是目前最新的版本。"
            buttons = ["好"]
            downloadURL = nil
            installs = false
        case .updateAvailable(let current, let latest, let url):
            title = "有新版本可以更新"
            if canSelfUpdate {
                informative = """
                PhemeMurmur \(latest) 已經發布，你目前是 \(current)。

                更新時 PhemeMurmur 會結束、安裝新版，然後自己重新啟動。
                """
                buttons = ["更新並重新啟動", "稍後再說"]
                downloadURL = nil
                installs = true
            } else {
                // Not running from /Applications, so the installer would replace
                // a different copy than the one the user is looking at.
                informative = """
                PhemeMurmur \(latest) 已經發布，你目前是 \(current)。

                這份不是安裝在「應用程式」資料夾的版本，無法直接更新，請到 GitHub 下載。
                """
                buttons = ["前往下載", "稍後再說"]
                downloadURL = url
                installs = false
            }
        case .failed(let message):
            title = "無法檢查更新"
            informative = message
            buttons = ["好"]
            downloadURL = nil
            installs = false
        }
    }
}

/// Thin main-actor driver: run the check, show the alert, then either start the
/// installer or open the release page. This is the AppKit boundary and is not
/// unit tested; the mapping it relies on, `UpdateAlertContent`, is.
@MainActor
enum UpdatePresenter {

    /// The menu's "檢查更新…". Reports whatever the check found, including
    /// failures — the user asked, so they get an answer either way.
    static func checkAndPresent(checker: UpdateChecker = UpdateChecker()) {
        Task { @MainActor in
            let outcome = await checker.check()
            present(UpdateAlertContent(outcome: outcome,
                                       canSelfUpdate: AppUpdater.canSelfUpdate))
        }
    }

    static func present(_ content: UpdateAlertContent) {
        // An accessory app has no windows to attach a sheet to, and the alert
        // has to come forward over whatever the user is working in.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = content.title
        alert.informativeText = content.informative
        for title in content.buttons { alert.addButton(withTitle: title) }

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let url = content.downloadURL {
            NSWorkspace.shared.open(url)
        } else if content.installs {
            startInstall()
        }
    }

    private static func startInstall() {
        // Noted before spawning: the installer quits this process, so the note
        // on disk is the only way the next launch can report what happened.
        UpdateHandoff.markInstallStarted()
        // The installer downloads before it quits the app, which is several
        // silent seconds. Tell the menu bar to look busy for them.
        NotificationCenter.default.post(name: .phemeDidStartUpdate, object: nil)
        do {
            try AppUpdater.run()
        } catch {
            UpdateHandoff.clear()
            let alert = NSAlert()
            alert.messageText = "更新失敗"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    /// Reports how the previous launch's update went, if there was one. Called
    /// once at startup; an ordinary launch says nothing.
    static func reportOutcomeOfPreviousRun() {
        guard let outcome = UpdateHandoff.consumeOutcome() else { return }
        let alert = NSAlert()
        switch outcome {
        case .updated(let from, let to):
            alert.messageText = "已更新到 \(to)"
            alert.informativeText = "PhemeMurmur 已經從 \(from) 更新完成並重新啟動。"
            alert.addButton(withTitle: "好")
        case .unchanged(let version):
            // Spawned but the version never moved, so the install failed after
            // this app lost control of it. Its log is the only record.
            alert.messageText = "更新沒有完成"
            alert.informativeText = """
            PhemeMurmur 仍然是 \(version)。安裝程式的記錄在 \(AppUpdater.logPath)。
            """
            alert.addButton(withTitle: "好")
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
