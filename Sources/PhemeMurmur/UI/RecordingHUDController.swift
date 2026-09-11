import AppKit
import SwiftUI

/// Owns the floating HUD panel: shows it, feeds it audio levels, and hides it
/// after phases that carry an auto-dismiss delay.
final class RecordingHUDController {

    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<NebulaHUDView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var phase: HUDPhase = .done
    private var levels: [Float] = Array(repeating: 0, count: 15)

    func show(_ phase: HUDPhase) {
        dismissWorkItem?.cancel()
        self.phase = phase

        let panel = existingPanel()
        render()
        panel.positionAtBottomCentre()
        panel.orderFrontRegardless()

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

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        levels = Array(repeating: 0, count: 15)
    }

    private func existingPanel() -> FloatingPanel {
        if let panel { return panel }
        let created = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 210))
        let hosting = NSHostingView(rootView: NebulaHUDView(phase: phase, levels: levels))
        created.contentView = hosting
        panel = created
        hostingView = hosting
        return created
    }

    private func render() {
        hostingView?.rootView = NebulaHUDView(phase: phase, levels: levels)
    }
}
