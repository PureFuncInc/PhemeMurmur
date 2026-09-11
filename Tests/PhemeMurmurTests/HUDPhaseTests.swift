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
        XCTAssertEqual(p.capsuleText, "TRANSCRIBING · OPENAI · ESC")
        // ringSpeed is seconds per rotation, so faster means a smaller value.
        XCTAssertLessThan(p.ringSpeed, recording.ringSpeed)
        XCTAssertNil(p.autoDismissAfter)
    }

    func testDoneDismissesAfterShortDelay() {
        let p = HUDPhase.done.presentation
        XCTAssertEqual(p.capsuleText, "DONE")
        XCTAssertEqual(p.autoDismissAfter, 0.7)
    }

    func testDoneClearsTheScreenWellBeforeTheFailureCardDoes() {
        // The text is already pasted when done appears, so it must be the
        // shortest-lived card; a failure is the one the user has to read.
        let done = HUDPhase.done.presentation.autoDismissAfter ?? .infinity
        let failed = HUDPhase.failed(message: "x").presentation.autoDismissAfter ?? 0
        XCTAssertLessThan(done, failed)
    }

    func testTheHUDIsGoneWithinAboutASecondOfThePaste() {
        // Transcribing may still owe its dwell when the text lands, and the done
        // card follows it, so the two together are what the user waits through.
        let dwell = HUDPhase.transcribing(provider: "x").presentation.minimumDwell
        let done = HUDPhase.done.presentation.autoDismissAfter ?? 0
        XCTAssertLessThanOrEqual(dwell + done, 1.2)
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

    func testEnglishStatesKeepTheTelegraphicStyle() {
        XCTAssertTrue(HUDPhase.recording(elapsed: 3).presentation.usesTelegraphicStyle)
        XCTAssertTrue(HUDPhase.transcribing(provider: "OpenAI").presentation.usesTelegraphicStyle)
        XCTAssertTrue(HUDPhase.done.presentation.usesTelegraphicStyle)
        XCTAssertTrue(HUDPhase.failed(message: "HTTP 429").presentation.usesTelegraphicStyle)
    }

    func testChineseMessagesDropTheMonospacedKernedStyle() {
        XCTAssertFalse(HUDPhase.failed(message: "尚未設定轉錄服務").presentation.usesTelegraphicStyle)
        XCTAssertFalse(HUDPhase.failed(message: "網路錯誤 (HTTP 500)").presentation.usesTelegraphicStyle)
    }
}
