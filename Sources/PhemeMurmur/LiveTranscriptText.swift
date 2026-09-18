import Foundation

/// Accumulated live-preview text: everything the recogniser has finalised so far,
/// plus the volatile (still changing) tail it is currently guessing at.
///
/// Pure value type with no Speech dependency so it can be unit tested and so it
/// compiles on macOS 13 — only the code that feeds it is gated to macOS 26.
struct LiveTranscriptText: Equatable {

    /// Longest preview the HUD will show. Older text scrolls off the front.
    static let maxCharacters = 140

    private(set) var finalized: String = ""
    private(set) var volatile: String = ""

    /// A finalised chunk arrived: it supersedes whatever volatile guess preceded it.
    mutating func appendFinalized(_ text: String) {
        finalized += text
        volatile = ""
    }

    /// The recogniser's current guess for the part it has not committed yet.
    mutating func setVolatile(_ text: String) {
        volatile = text
    }

    mutating func reset() {
        finalized = ""
        volatile = ""
    }

    var isEmpty: Bool { display.isEmpty }

    /// What the HUD renders: finalised text followed by the volatile tail,
    /// clipped to the most recent `maxCharacters`.
    var display: String {
        Self.tail(finalized + volatile, limit: Self.maxCharacters)
    }

    /// Everything recognised, uncut. `display` exists to fit a three-line box;
    /// this is the text that gets pasted, so it must never be clipped.
    var full: String {
        (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps the last `limit` characters, marking the cut with a leading ellipsis.
    /// Leading/trailing whitespace is trimmed so the text area never renders a
    /// blank first line.
    static func tail(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.suffix(limit)
        return "…" + cut.drop(while: { $0 == " " })
    }
}

/// Whether the recording HUD should run a live text preview.
///
/// Only Apple's on-device recogniser produces partial results; OpenAI and Gemini
/// are batch HTTP APIs that return nothing until the recording is over, so the
/// HUD keeps its text-free layout for them.
enum LivePreviewPolicy {

    static func shouldPreview(activeProviderType: ProviderType?, osSupportsLiveTranscription: Bool) -> Bool {
        activeProviderType == .apple && osSupportsLiveTranscription
    }

    /// True on the phases where the preview text is still meaningful. After the
    /// paste (or a failure) the partial text is stale and must not linger.
    static func keepsLiveText(_ phase: HUDPhase) -> Bool {
        switch phase {
        case .recording, .transcribing:
            return true
        case .done, .failed:
            return false
        }
    }
}
