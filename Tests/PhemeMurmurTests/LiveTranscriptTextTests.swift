import XCTest
@testable import PhemeMurmur

final class LiveTranscriptTextTests: XCTestCase {

    func testStartsEmpty() {
        XCTAssertTrue(LiveTranscriptText().isEmpty)
        XCTAssertEqual(LiveTranscriptText().display, "")
    }

    func testVolatileTextIsShownImmediately() {
        var t = LiveTranscriptText()
        t.setVolatile("hello wor")
        XCTAssertEqual(t.display, "hello wor")
    }

    func testNewVolatileReplacesThePreviousGuess() {
        var t = LiveTranscriptText()
        t.setVolatile("hello wor")
        t.setVolatile("hello world")
        XCTAssertEqual(t.display, "hello world")
    }

    func testFinalizedTextClearsTheVolatileTail() {
        var t = LiveTranscriptText()
        t.setVolatile("hello wor")
        t.appendFinalized("hello world. ")
        XCTAssertEqual(t.display, "hello world.")
    }

    func testFinalizedChunksAccumulateInOrder() {
        var t = LiveTranscriptText()
        t.appendFinalized("one ")
        t.appendFinalized("two ")
        t.setVolatile("thr")
        XCTAssertEqual(t.display, "one two thr")
    }

    func testResetClearsBothHalves() {
        var t = LiveTranscriptText()
        t.appendFinalized("one ")
        t.setVolatile("two")
        t.reset()
        XCTAssertTrue(t.isEmpty)
    }

    func testDisplayKeepsOnlyTheMostRecentCharacters() {
        var t = LiveTranscriptText()
        t.appendFinalized(String(repeating: "a", count: 200))
        t.setVolatile("END")
        let display = t.display
        XCTAssertTrue(display.hasPrefix("…"))
        XCTAssertTrue(display.hasSuffix("END"))
        XCTAssertEqual(display.count, LiveTranscriptText.maxCharacters + 1)
    }

    func testTailReturnsShortTextUntouched() {
        XCTAssertEqual(LiveTranscriptText.tail("短句", limit: 10), "短句")
    }

    func testTailTrimsSurroundingWhitespace() {
        XCTAssertEqual(LiveTranscriptText.tail("  hi \n", limit: 10), "hi")
    }

    func testTailKeepsTheEndNotTheStart() {
        XCTAssertEqual(LiveTranscriptText.tail("abcdefghij", limit: 4), "…ghij")
    }

    func testTailWorksOnChineseText() {
        XCTAssertEqual(LiveTranscriptText.tail("一二三四五六", limit: 3), "…四五六")
    }
}

final class LivePreviewPolicyTests: XCTestCase {

    func testAppleProviderOnASupportedOSPreviews() {
        XCTAssertTrue(LivePreviewPolicy.shouldPreview(activeProviderType: .apple,
                                                     osSupportsLiveTranscription: true))
    }

    func testAppleProviderOnAnOldOSDoesNotPreview() {
        XCTAssertFalse(LivePreviewPolicy.shouldPreview(activeProviderType: .apple,
                                                      osSupportsLiveTranscription: false))
    }

    func testBatchProvidersNeverPreview() {
        XCTAssertFalse(LivePreviewPolicy.shouldPreview(activeProviderType: .openai,
                                                      osSupportsLiveTranscription: true))
        XCTAssertFalse(LivePreviewPolicy.shouldPreview(activeProviderType: .gemini,
                                                      osSupportsLiveTranscription: true))
    }

    func testUnknownProviderDoesNotPreview() {
        XCTAssertFalse(LivePreviewPolicy.shouldPreview(activeProviderType: nil,
                                                      osSupportsLiveTranscription: true))
    }

    func testTextSurvivesRecordingAndTranscribing() {
        XCTAssertTrue(LivePreviewPolicy.keepsLiveText(.recording(elapsed: 2)))
        XCTAssertTrue(LivePreviewPolicy.keepsLiveText(.transcribing(provider: "Apple")))
    }

    func testTextIsDroppedOnceTheRecordingIsOver() {
        XCTAssertFalse(LivePreviewPolicy.keepsLiveText(.done))
        XCTAssertFalse(LivePreviewPolicy.keepsLiveText(.failed(message: "x")))
    }
}

extension LiveTranscriptTextTests {

    func testFullKeepsTextTheDisplayWouldHaveClipped() {
        var t = LiveTranscriptText()
        let long = String(repeating: "字", count: LiveTranscriptText.maxCharacters + 50)
        t.appendFinalized(long)
        // The display is sized for a three-line box; the pasted text is not.
        XCTAssertEqual(t.display.count, LiveTranscriptText.maxCharacters + 1) // + the ellipsis
        XCTAssertEqual(t.full.count, long.count)
        XCTAssertFalse(t.full.hasPrefix("…"))
    }

    func testFullIncludesTheVolatileTail() {
        var t = LiveTranscriptText()
        t.appendFinalized("已經確定的")
        t.setVolatile("還在猜的")
        // The last words spoken are still volatile when recording stops, so
        // dropping them would cut the end off every paste.
        XCTAssertEqual(t.full, "已經確定的還在猜的")
    }
}
