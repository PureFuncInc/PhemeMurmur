import XCTest
@testable import PhemeMurmur

/// These tests pin behaviour that `OpenAIProvider` relies on but cannot
/// exercise directly without hitting the network. They cover the platform
/// primitive (`String.applyingTransform`) used to coerce Whisper output
/// into Traditional Chinese when `language == "zh"`.
final class OpenAIProviderTests: XCTestCase {

    private func toTraditional(_ s: String) -> String? {
        s.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false)
    }

    func testHansHantTransformConvertsBasicSimplified() {
        XCTAssertEqual(toTraditional("汉语简体"), "漢語簡體")
    }

    func testHansHantTransformIsNoopOnTraditionalText() {
        let input = "繁體中文沒變化"
        XCTAssertEqual(toTraditional(input), input)
    }

    func testHansHantTransformPreservesAsciiAndPunctuation() {
        XCTAssertEqual(
            toTraditional("Hello 简体 World, 123."),
            "Hello 簡體 World, 123."
        )
    }

    func testHansHantTransformIsAvailableOnThisRuntime() {
        // Sanity check that StringTransform("Hans-Hant") is recognised.
        // Returns nil if the ICU identifier is not registered.
        XCTAssertNotNil(toTraditional("简"))
    }
}
