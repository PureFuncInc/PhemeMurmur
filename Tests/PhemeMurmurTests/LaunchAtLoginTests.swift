import XCTest
@testable import PhemeMurmur

final class LaunchAtLoginTests: XCTestCase {

    // MARK: - Pure helper: action(for:)

    func testActionWhenDisabled() {
        XCTAssertEqual(LaunchAtLogin.action(for: .disabled), .enable)
    }

    func testActionWhenEnabled() {
        XCTAssertEqual(LaunchAtLogin.action(for: .enabled), .disable)
    }

    func testActionWhenRequiresApproval() {
        XCTAssertEqual(LaunchAtLogin.action(for: .requiresApproval), .openSystemSettings)
    }

    func testActionWhenFailed() {
        XCTAssertEqual(LaunchAtLogin.action(for: .failed("any error")), .openSystemSettings)
    }

    // MARK: - Plist filesystem behavior (uses temp directory)

    private func tempPlistURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pheme-murmur-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("com.purefuncinc.PhemeMurmur.plist")
    }

    func testReadStateWhenPlistExistsReturnsEnabled() throws {
        let url = tempPlistURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try Data("placeholder".utf8).write(to: url)

        let lal = LaunchAtLogin(plistURL: url)
        XCTAssertEqual(lal.state, .enabled)
    }

    func testReadStateWhenPlistAbsentDoesNotCrash() {
        // Don't assert exact value — depends on real SMAppService.mainApp.status on this
        // machine. Just ensure init doesn't throw and `state` is readable.
        let url = tempPlistURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let lal = LaunchAtLogin(plistURL: url)
        _ = lal.state
    }

    func testWritePlistEmitsExpectedKeys() throws {
        let url = tempPlistURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let exec = "/Applications/PhemeMurmur.app/Contents/MacOS/PhemeMurmur"
        try LaunchAtLogin.writePlist(at: url, executablePath: exec)

        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization
            .propertyList(from: data, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(parsed?["Label"] as? String, "com.purefuncinc.PhemeMurmur")
        XCTAssertEqual(parsed?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(parsed?["KeepAlive"] as? Bool, false)
        XCTAssertEqual(parsed?["ProgramArguments"] as? [String], [exec])
    }

    func testRemovePlistIsIdempotentWhenAbsent() throws {
        let url = tempPlistURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Plist deliberately not created. removePlistIfPresent should be a no-op.
        XCTAssertNoThrow(try LaunchAtLogin.removePlistIfPresent(at: url))
    }
}
