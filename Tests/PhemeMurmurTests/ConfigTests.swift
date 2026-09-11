import XCTest
@testable import PhemeMurmur

final class ConfigTests: XCTestCase {
    func testVoiceCommandsDefaultsToFalseWhenAbsent() throws {
        let json = """
        {"providers": {}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertFalse(cfg.resolvedVoiceCommands)
    }

    func testVoiceCommandsTrueIsDecoded() throws {
        let json = """
        {"providers": {}, "voice-commands": true}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertTrue(cfg.resolvedVoiceCommands)
    }

    func testVoiceCommandsFalseIsDecoded() throws {
        let json = """
        {"providers": {}, "voice-commands": false}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertFalse(cfg.resolvedVoiceCommands)
    }

    func testSavedBooleanFieldDecodesBack() throws {
        let json = """
        {"providers": {}, "voice-commands": true, "silence-threshold": 0.0250}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertTrue(cfg.resolvedVoiceCommands)
        XCTAssertEqual(try XCTUnwrap(cfg.silenceThreshold), 0.025, accuracy: 0.0001)
    }

    func testRawFieldInsideBlockCommentIsNotOverwritten() throws {
        let content = """
        {
            "providers": {},
            /*
            "silence-threshold": 0.5,
            */
            "voice-commands": false
        }
        """
        let updated = Config.upsertRawField("silence-threshold", rawValue: "0.0250", in: content)

        // The commented-out line must survive untouched...
        XCTAssertTrue(updated.contains("\"silence-threshold\": 0.5,"),
                       "value inside the block comment should not be rewritten")
        // ...and a new, live entry must be inserted instead.
        XCTAssertTrue(updated.contains("\"silence-threshold\": 0.0250,"),
                      "a live entry should be inserted since the only existing one is commented out")
    }

    func testStringFieldInsideBlockCommentIsNotOverwritten() throws {
        let content = """
        {
            "providers": {},
            /* "prefix": "old-prefix", */
            "active-provider": "OpenAI"
        }
        """
        let updated = Config.upsertStringField("prefix", value: "new-prefix", in: content)

        XCTAssertTrue(updated.contains("\"prefix\": \"old-prefix\","),
                       "value inside the block comment should not be rewritten")
        XCTAssertTrue(updated.contains("\"prefix\": \"new-prefix\","),
                       "a live entry should be inserted since the only existing one is commented out")
    }

    /// Guards against a regression to the old hand-rolled `stripComments` loop, which
    /// never advanced past an unterminated `/*` and hung forever. Runs off the main
    /// thread with a bounded wait so a regression fails the test (timeout) instead of
    /// hanging the whole suite/CI.
    func testStripCommentsDoesNotHangOnUnterminatedBlockComment() {
        let source = #"{"a": 1, /* unterminated"#
        let expectation = expectation(description: "stripComments returns")
        var result: String?
        DispatchQueue.global().async {
            result = Config.stripComments(from: source)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(result, #"{"a": 1, "#,
                       "everything from the unterminated /* onward should be dropped")
    }

    func testStripCommentsPreservesSlashesInsideStringValues() {
        let source = #"{"post-process": {"base-url": "https://example.com/v1"}}"#
        XCTAssertEqual(Config.stripComments(from: source), source,
                       "// inside a quoted string value must not be treated as a comment")
    }
}
