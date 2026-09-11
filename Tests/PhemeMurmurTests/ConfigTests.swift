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

    // MARK: - String values containing quotes / backslashes

    /// Decodes `content` (comments stripped) to prove the edited file is still valid JSON.
    private func decode(_ content: String) throws -> ConfigFile {
        let stripped = Config.stripComments(from: content)
        let data = try XCTUnwrap(stripped.data(using: .utf8))
        return try JSONDecoder().decode(ConfigFile.self, from: data)
    }

    func testStringFieldRoundTripsValueContainingQuotes() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let updated = Config.upsertStringField("prefix", value: #"say "hi""#, in: content)
        XCTAssertEqual(try decode(updated).prefix, #"say "hi""#)
    }

    func testStringFieldRoundTripsValueContainingBackslash() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let updated = Config.upsertStringField("prefix", value: #"C:\path"#, in: content)
        XCTAssertEqual(try decode(updated).prefix, #"C:\path"#)
    }

    func testStringFieldRoundTripsValueContainingBothQuoteAndBackslash() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let value = #"a\"b\c"#
        let updated = Config.upsertStringField("prefix", value: value, in: content)
        XCTAssertEqual(try decode(updated).prefix, value)
    }

    func testStringFieldRoundTripsValueContainingTab() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let value = "col1\tcol2"
        let updated = Config.upsertStringField("prefix", value: value, in: content)
        XCTAssertFalse(updated.contains("\t"), "a raw tab inside a JSON string literal is invalid")
        XCTAssertEqual(try decode(updated).prefix, value)
    }

    func testStringFieldRoundTripsValueContainingNewline() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let value = "line1\nline2\r\nline3"
        let updated = Config.upsertStringField("prefix", value: value, in: content)
        XCTAssertEqual(try decode(updated).prefix, value)
    }

    func testStringFieldRoundTripsControlCharactersMixedWithQuotesAndBackslashes() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let value = "say \"hi\"\tC:\\path\nnext\u{01}end"
        let updated = Config.upsertStringField("prefix", value: value, in: content)
        XCTAssertEqual(try decode(updated).prefix, value)

        // And re-saving the already-escaped file must stay valid, the same way
        // the quote case does.
        let again = Config.upsertStringField("prefix", value: value, in: updated)
        XCTAssertEqual(try decode(again).prefix, value)
    }

    /// The reported corruption: the first save writes an escaped quote, the second
    /// save's matcher used to stop at that `\"` and truncate mid-literal.
    func testTwoConsecutiveSavesOfQuotedValueStayValid() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let first = Config.upsertStringField("prefix", value: #"say "hi""#, in: content)
        XCTAssertEqual(try decode(first).prefix, #"say "hi""#)

        let second = Config.upsertStringField("prefix", value: #"say "hi""#, in: first)
        XCTAssertEqual(try decode(second).prefix, #"say "hi""#)
        XCTAssertEqual(second, first, "re-saving the same value must be idempotent")

        let third = Config.upsertStringField("prefix", value: "plain", in: second)
        XCTAssertEqual(try decode(third).prefix, "plain")
    }

    func testStringFieldWithQuotedValueDoesNotDuplicateTheKey() throws {
        let content = #"{"providers": {}, "prefix": ""}"#
        let first = Config.upsertStringField("prefix", value: #"a"b"#, in: content)
        let second = Config.upsertStringField("prefix", value: #"c"d"#, in: first)
        XCTAssertEqual(second.components(separatedBy: "\"prefix\"").count - 1, 1,
                       "the key must be rewritten in place, not duplicated")
        XCTAssertEqual(try decode(second).prefix, #"c"d"#)
    }

    // MARK: - Raw values with trailing same-line comments

    func testRawFieldWithTrailingLineCommentIsUpdatedInPlace() throws {
        let content = """
        {
            "providers": {},
            "silence-threshold": 0.003 // tuned
        }
        """
        let updated = Config.upsertRawField("silence-threshold", rawValue: "0.0500", in: content)
        XCTAssertEqual(updated.components(separatedBy: "\"silence-threshold\"").count - 1, 1,
                       "the existing key must be updated, not duplicated")
        XCTAssertTrue(updated.contains("// tuned"), "the trailing comment must survive")
        XCTAssertEqual(try XCTUnwrap(decode(updated).silenceThreshold), 0.05, accuracy: 0.0001)
    }

    func testRawBooleanWithTrailingLineCommentIsUpdatedInPlace() throws {
        let content = """
        {
            "providers": {},
            "voice-commands": false // off by default
        }
        """
        let updated = Config.upsertRawField("voice-commands", rawValue: "true", in: content)
        XCTAssertEqual(updated.components(separatedBy: "\"voice-commands\"").count - 1, 1)
        XCTAssertTrue(try decode(updated).resolvedVoiceCommands)
    }
}
