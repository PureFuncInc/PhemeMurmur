import AppKit

final class OnboardingWindow: NSObject, NSWindowDelegate {
    private static let markerPath: String = {
        let dir = (Config.configPath as NSString).deletingLastPathComponent
        return "\(dir)/.onboarding-done"
    }()

    static var needsOnboarding: Bool {
        !FileManager.default.fileExists(atPath: markerPath)
    }

    static func markOnboardingComplete() {
        FileManager.default.createFile(atPath: markerPath, contents: nil)
    }

    private var window: NSWindow?
    private var currentPage = 0
    private var pageContainer: NSView!
    private var nextButton: NSButton!
    private var backButton: NSButton!
    private var pageIndicator: NSTextField!
    private var onDismiss: (() -> Void)?

    private struct Page {
        let emoji: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(
            emoji: "🎙️",
            title: "歡迎使用 PhemeMurmur",
            body: "PhemeMurmur 是一款 macOS 語音轉文字的選單列應用程式。\n按下快捷鍵即可錄音，自動將語音轉為繁體中文文字，\n然後傳送到您正在使用的應用程式輸入框。"
        ),
        Page(
            emoji: "⌨️",
            title: "使用方式",
            body: "按下快捷鍵開始錄音，完成錄音後後再次按下快捷鍵會結束錄製並開始轉錄。\n按 Esc 鍵可以取消錄音。\n\n預設快捷鍵為右側 Shift 鍵，\n可在選單列的「Hotkey」選單中更改。\n\n轉錄完成後，文字會自動貼到游標所在位置並複製到剪貼簿。"
        ),
        Page(
            emoji: "🔑",
            title: "設定 API Key",
            body: "PhemeMurmur 支援 OpenAI 與 Gemini 兩種語音轉文字服務。\n\n請點擊選單列中的「Provider」選單，\n選擇要使用的服務後開啟設定視窗並填入 API Key。\n\n設定完成後，您也能隨時在選單列的「Provider」選單中切換服務。"
        )
    ]

    func showIfNeeded(onDismiss: @escaping () -> Void) {
        guard OnboardingWindow.needsOnboarding else {
            onDismiss()
            return
        }
        self.onDismiss = onDismiss
        showWindow()
    }

    private func showWindow() {
        let width: CGFloat = 520
        let height: CGFloat = 420
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let w = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "PhemeMurmur"
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating

        let contentView = NSView(frame: rect)

        // Page container
        pageContainer = NSView(frame: NSRect(x: 0, y: 60, width: width, height: height - 60))
        contentView.addSubview(pageContainer)

        // Bottom bar
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 60))

        backButton = NSButton(title: "上一步", target: self, action: #selector(goBack))
        backButton.bezelStyle = .rounded
        backButton.frame = NSRect(x: 20, y: 15, width: 80, height: 30)
        bottomBar.addSubview(backButton)

        pageIndicator = NSTextField(labelWithString: "")
        pageIndicator.frame = NSRect(x: width / 2 - 60, y: 20, width: 120, height: 20)
        pageIndicator.alignment = .center
        pageIndicator.textColor = .secondaryLabelColor
        pageIndicator.font = .systemFont(ofSize: 12)
        bottomBar.addSubview(pageIndicator)

        nextButton = NSButton(title: "下一步", target: self, action: #selector(goNext))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.frame = NSRect(x: width - 100, y: 15, width: 80, height: 30)
        bottomBar.addSubview(nextButton)

        contentView.addSubview(bottomBar)
        w.contentView = contentView
        window = w

        renderPage()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func renderPage() {
        pageContainer.subviews.forEach { $0.removeFromSuperview() }

        let page = pages[currentPage]
        let containerWidth = pageContainer.bounds.width
        let containerHeight = pageContainer.bounds.height

        // Emoji icon
        let emojiSize: CGFloat = 64
        let emojiLabel = NSTextField(labelWithString: page.emoji)
        emojiLabel.font = .systemFont(ofSize: emojiSize)
        emojiLabel.alignment = .center
        emojiLabel.frame = NSRect(
            x: (containerWidth - emojiSize * 1.5) / 2,
            y: containerHeight - emojiSize * 1.5 - 20,
            width: emojiSize * 1.5,
            height: emojiSize * 1.5
        )
        pageContainer.addSubview(emojiLabel)

        // Title
        let titleLabel = NSTextField(labelWithString: page.title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(
            x: 30,
            y: containerHeight - emojiSize * 1.5 - 60,
            width: containerWidth - 60,
            height: 30
        )
        pageContainer.addSubview(titleLabel)

        // Body
        let bodyLabel = NSTextField(labelWithString: page.body)
        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.alignment = .center
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.frame = NSRect(
            x: 40,
            y: 10,
            width: containerWidth - 80,
            height: containerHeight - emojiSize * 1.5 - 75
        )
        pageContainer.addSubview(bodyLabel)

        // Update buttons
        backButton.isHidden = currentPage == 0
        let isLast = currentPage == pages.count - 1
        nextButton.title = isLast ? "開始使用" : "下一步"

        // Page indicator dots
        let dots = (0..<pages.count).map { i in
            i == currentPage ? "●" : "○"
        }.joined(separator: "  ")
        pageIndicator.stringValue = dots
    }

    @objc private func goNext() {
        if currentPage < pages.count - 1 {
            currentPage += 1
            renderPage()
        } else {
            dismiss()
        }
    }

    @objc private func goBack() {
        if currentPage > 0 {
            currentPage -= 1
            renderPage()
        }
    }

    private func dismiss() {
        OnboardingWindow.markOnboardingComplete()
        window?.close()
        window = nil
        onDismiss?()
    }

    func windowWillClose(_ notification: Notification) {
        OnboardingWindow.markOnboardingComplete()
        onDismiss?()
        onDismiss = nil
    }
}
