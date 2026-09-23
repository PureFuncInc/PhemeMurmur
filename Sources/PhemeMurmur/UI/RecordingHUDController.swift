import AppKit
import SwiftUI

/// Owns the floating HUD panel: fades it in and out, feeds it audio levels, and
/// hides it after phases that carry an auto-dismiss delay.
final class RecordingHUDController {

    /// How long the panel takes to fade in and out. Short enough not to feel
    /// laggy in front of a recording, long enough to read as a fade.
    private static let fadeInDuration: TimeInterval = 0.16
    /// Deliberately brisk: once the text is in the document the HUD is just in
    /// the way, so it clears out rather than lingering politely.
    private static let fadeOutDuration: TimeInterval = 0.2

    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<VoiceHUDView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var phase: HUDPhase = .done
    private var levels: [Float] = Array(repeating: 0, count: 15)
    private var liveText: String = ""

    /// The text actually inserted into the document. Shown in place of the live
    /// preview once recognition is over, so the last thing on screen is what was
    /// pasted rather than a stale partial guess.
    var pastedText: String = ""

    /// Whether this session's provider produces live partial text. Set before
    /// the recording phase is shown so the transcript slot is reserved from the
    /// first frame — reserving it later would resize the panel mid-sentence.
    var reservesTranscriptArea: Bool = false

    /// When the current phase went on screen, so `minimumDwell` can be honoured.
    private var phaseShownAt: Date?
    /// A phase change held back until the current phase has had its dwell.
    private var deferredShow: DispatchWorkItem?
    /// Invalidates in-flight fade completions when a newer fade supersedes them.
    private var fadeGeneration = 0

    func show(_ phase: HUDPhase) {
        // A phase that has not yet had its minimum time on screen holds the
        // slot; the new phase takes over when the dwell expires.
        if let remaining = remainingDwell() {
            deferredShow?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.deferredShow = nil
                self?.show(phase)
            }
            deferredShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
            return
        }

        deferredShow?.cancel()
        deferredShow = nil
        dismissWorkItem?.cancel()

        self.phase = phase
        self.phaseShownAt = Date()
        // Partial text is only meaningful while the utterance is still in play;
        // once it is over the readout switches to the pasted text instead.
        if !LivePreviewPolicy.keepsLiveText(phase) { liveText = "" }

        let panel = existingPanel()
        attachContent(to: panel)
        render()
        resizeToFitContent()
        panel.positionAtBottomCorner()
        fadeIn(panel)

        if let delay = phase.presentation.autoDismissAfter {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func update(levels: [Float]) {
        self.levels = levels
        render()
    }

    /// Feeds the live on-device recognition preview.
    func update(liveText: String) {
        guard liveText != self.liveText else { return }
        self.liveText = liveText
        // No re-measure: the transcript area is a fixed three lines tall, so the
        // panel keeps its size and position as the recogniser catches up.
        render()
    }

    /// Hides immediately — a dwell must never make Esc feel unresponsive.
    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        deferredShow?.cancel()
        deferredShow = nil
        phaseShownAt = nil

        guard let panel, panel.isVisible else { return }
        fadeOut(panel)
    }

    // MARK: - Dwell

    /// Seconds the current phase still owes, or nil when it may be replaced now.
    private func remainingDwell() -> TimeInterval? {
        guard let panel, panel.isVisible,
              let shownAt = phaseShownAt else { return nil }
        let dwell = phase.presentation.minimumDwell
        guard dwell > 0 else { return nil }
        let remaining = dwell - Date().timeIntervalSince(shownAt)
        return remaining > 0 ? remaining : nil
    }

    // MARK: - Fading

    private func fadeIn(_ panel: FloatingPanel) {
        fadeGeneration += 1
        // Starting from the panel's current alpha means a show() arriving during
        // a fade-out picks up where it left off instead of blinking.
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ panel: FloatingPanel) {
        fadeGeneration += 1
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            // Only tear down if no newer show() took over mid-fade.
            panel.orderOut(nil)
            panel.alphaValue = 1
            // Ordering the panel out is not enough. The SwiftUI view inside keeps
            // its repeatForever animations — reactor spin, breathing, ticks —
            // running on the main thread for as long as it exists, visible or
            // not. Left attached, a HUD shown once kept the app at roughly 60%
            // CPU for the rest of the session. Dropping the hosting view ends
            // them; it is rebuilt on the next show.
            self.detachContent(from: panel)
            self.levels = Array(repeating: 0, count: 15)
            self.liveText = ""
            self.pastedText = ""
        }
    }

    // MARK: - Panel

    private func existingPanel() -> FloatingPanel {
        if let panel { return panel }
        let created = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 210))
        created.alphaValue = 0
        panel = created
        return created
    }

    /// The SwiftUI content only exists while the HUD is on screen — see
    /// `detachContent`. A no-op when a show arrives mid-fade and the content is
    /// still attached.
    private func attachContent(to panel: FloatingPanel) {
        guard hostingView == nil else { return }
        let hosting = NSHostingView(rootView: makeView())
        panel.contentView = hosting
        hostingView = hosting
    }

    private func detachContent(from panel: FloatingPanel) {
        panel.contentView = nil
        hostingView = nil
    }

    private func render() {
        hostingView?.rootView = makeView()
    }

    /// The readout is live while the utterance is still in play, and the pasted
    /// text afterwards.
    private func makeView() -> VoiceHUDView {
        let isLive = LivePreviewPolicy.keepsLiveText(phase)
        return VoiceHUDView(phase: phase,
                            levels: levels,
                            transcript: isLive ? liveText : pastedText,
                            transcriptIsLive: isLive,
                            reservesTranscript: reservesTranscriptArea)
    }

    /// Resizes the panel to the hosting view's SwiftUI-measured fitting size so the
    /// status chip (which varies in length across phases and languages) is never
    /// clipped. Must run before `positionAtBottomCorner()`, which places the
    /// panel using its current size.
    private func resizeToFitContent() {
        guard let hostingView, let panel else { return }
        let fitting = hostingView.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }
        panel.setContentSize(fitting)
    }
}
