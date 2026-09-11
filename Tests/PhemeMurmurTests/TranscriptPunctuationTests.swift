import XCTest
@testable import PhemeMurmur

final class TranscriptPunctuationTests: XCTestCase {

    func testDropsTheFullStopTheRecogniserInserts() {
        XCTAssertEqual(TranscriptPunctuation.strip("今天天氣很好。"), "今天天氣很好")
    }

    func testDropsEveryFullWidthMark() {
        XCTAssertEqual(TranscriptPunctuation.strip("你好，世界、再見；真的：對嗎？好！"),
                       "你好世界再見真的對嗎好")
    }

    func testLeavesAsciiPunctuationAlone() {
        // Losing these would turn versions, URLs and code into nonsense.
        XCTAssertEqual(TranscriptPunctuation.strip("升級到 v1.2.3"), "升級到 v1.2.3")
        XCTAssertEqual(TranscriptPunctuation.strip("see example.com/a?b=1"),
                       "see example.com/a?b=1")
    }

    func testClosesTheGapAMarkLeavesBetweenLatinWords() {
        XCTAssertEqual(TranscriptPunctuation.strip("hello ， world"), "hello world")
    }

    func testKeepsEdgeSpacingSoChunksStillJoinCorrectly() {
        // The live preview concatenates chunks; a trimmed leading space would
        // glue the previous chunk's last word to this one's first.
        XCTAssertEqual(TranscriptPunctuation.strip(" and then。"), " and then")
    }

    func testTextWithoutMarksIsReturnedUnchanged() {
        XCTAssertEqual(TranscriptPunctuation.strip("沒有標點"), "沒有標點")
        XCTAssertEqual(TranscriptPunctuation.strip(""), "")
    }

    func testAnUtteranceThatIsOnlyAFullStopBecomesEmpty() {
        // Which is what makes the provider report silence rather than paste ".".
        XCTAssertEqual(TranscriptPunctuation.strip("。"), "")
    }
}
