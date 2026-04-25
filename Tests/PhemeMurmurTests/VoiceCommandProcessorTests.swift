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

    func testFirstPointProducesOneDotSpace() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("第一點，要先處理 A"),
            "\n1. 要先處理 A"
        )
    }

    func testTenthPointProducesTwoDigitOutput() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("第十點，是 J"),
            "\n10. 是 J"
        )
    }

    func testNumberedPointsSequence() {
        XCTAssertEqual(
            VoiceCommandProcessor.process(
                "重點，第一點，A，第二點，B，第三點，C"
            ),
            "重點\n1. A\n2. B\n3. C"
        )
    }

    func testAllNumberedPointsCovered() {
        let triggers = [
            ("第一點", "\n1. "), ("第二點", "\n2. "), ("第三點", "\n3. "),
            ("第四點", "\n4. "), ("第五點", "\n5. "), ("第六點", "\n6. "),
            ("第七點", "\n7. "), ("第八點", "\n8. "), ("第九點", "\n9. "),
            ("第十點", "\n10. "),
        ]
        for (trigger, expected) in triggers {
            XCTAssertEqual(
                VoiceCommandProcessor.process(trigger),
                expected,
                "Trigger \(trigger) should produce \(expected.debugDescription)"
            )
        }
    }

    func testConsecutiveNewlineTriggersStack() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("A 換行 換行 B"),
            "A\n\nB"
        )
    }

    func testMixedTriggersInOneInput() {
        XCTAssertEqual(
            VoiceCommandProcessor.process(
                "標題，分隔線，第一點，A，空行，結尾"
            ),
            "標題\n\n---\n\n\n1. A\n\n結尾"
        )
    }

    func testTriggerWithoutBoundaryCharsStillMatches() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("a換行b"),
            "a\nb"
        )
    }

    func testHalfWidthPeriodAbsorbed() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("結束.換行.繼續"),
            "結束\n繼續"
        )
    }

    func testFullWidthIdeographicSpaceAbsorbed() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("前面\u{3000}換行\u{3000}後面"),
            "前面\n後面"
        )
    }
}
