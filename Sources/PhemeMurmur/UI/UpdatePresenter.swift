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
        do {
            try AppUpdater.run()
        } catch {
            let alert = NSAlert()
            alert.messageText = "更新失敗"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}
