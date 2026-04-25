import XCTest
@testable import PhemeMurmur

final class VoiceCommandProcessorTests: XCTestCase {

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(VoiceCommandProcessor.process(""), "")
    }

    func testNoTriggersReturnsInputUnchanged() {
        let input = "今天天氣很好"
        XCTAssertEqual(VoiceCommandProcessor.process(input), input)
    }

    func testNewlineMidSentenceWithHalfWidthCommas() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("Hello,換行,World"),
            "Hello\nWorld"
        )
    }

    func testNewlineMidSentenceWithFullWidthCommas() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("你好，換行，世界"),
            "你好\n世界"
        )
    }

    func testNewlineSurroundedBySpaces() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("今天 換行 明天"),
            "今天\n明天"
        )
    }

    func testNewlineAtStart() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("換行你好"),
            "\n你好"
        )
    }

    func testNewlineAtEnd() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("你好換行"),
            "你好\n"
        )
    }

    func testBlankLineProducesDoubleNewline() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("段落一，空行，段落二"),
            "段落一\n\n段落二"
        )
    }

    func testSeparatorProducesMarkdownRule() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("標題，分隔線，內容"),
            "標題\n\n---\n\n內容"
        )
    }
}
