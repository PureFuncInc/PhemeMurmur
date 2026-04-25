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
}
