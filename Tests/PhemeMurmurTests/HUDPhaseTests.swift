import XCTest
@testable import PhemeMurmur

final class HUDPhaseTests: XCTestCase {

    func testRecordingCapsuleShowsElapsedAndEscHint() {
        let p = HUDPhase.recording(elapsed: 7).presentation
        XCTAssertEqual(p.capsuleText, "LISTENING · 0:07 · ESC")
    }

    func testRecordingFormatsMinutes() {
        let p = HUDPhase.recording(elapsed: 75).presentation
        XCTAssertEqual(p.capsuleText, "LISTENING · 1:15 · ESC")
    }

    func testRecordingNeverAutoDismisses() {
        XCTAssertNil(HUDPhase.recording(elapsed: 3).presentation.autoDismissAfter)
    }

    func testTranscribingShowsProviderAndSpinsFaster() {
        let recording = HUDPhase.recording(elapsed: 3).presentation
        let p = HUDPhase.transcribing(provider: "OpenAI").presentation
        XCTAssertEqual(p.capsuleText, "TRANSCRIBING · OPENAI")
        // ringSpeed is seconds per rotation, so faster means a smaller value.
        XCTAssertLessThan(p.ringSpeed, recording.ringSpeed)
        XCTAssertNil(p.autoDismissAfter)
    }

    func testDoneDismissesAfterShortDelay() {
        let p = HUDPhase.done.presentation
        XCTAssertEqual(p.capsuleText, "DONE")
        XCTAssertEqual(p.autoDismissAfter, 1.2)
    }

    func testFailedShowsMessageAndLingersLonger() {
        let p = HUDPhase.failed(message: "沒有網路").presentation
        XCTAssertEqual(p.capsuleText, "沒有網路")
        XCTAssertEqual(p.autoDismissAfter, 3.0)
    }

    func testFailedTintDiffersFromRecordingTint() {
        let failed = HUDPhase.failed(message: "x").presentation.coreTint
        let recording = HUDPhase.recording(elapsed: 1).presentation.coreTint
        XCTAssertNotEqual(failed.r, recording.r, accuracy: 0.0001)
    }
}
