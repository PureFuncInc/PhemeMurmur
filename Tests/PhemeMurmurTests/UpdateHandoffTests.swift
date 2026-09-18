import XCTest
@testable import PhemeMurmur

final class UpdateHandoffTests: XCTestCase {

    /// A throwaway domain so these never touch the real app's preferences.
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "UpdateHandoffTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        defaults = nil
        super.tearDown()
    }

    func testAnOrdinaryLaunchReportsNothing() {
        // The overwhelming majority of launches did not follow an update and
        // must stay silent.
        XCTAssertNil(UpdateHandoff.consumeOutcome(currentVersion: "1.0.0", defaults: defaults))
    }

    func testAVersionChangeAfterAnUpdateIsReportedAsSuccess() {
        UpdateHandoff.markInstallStarted(version: "1.0.0", defaults: defaults)
        XCTAssertEqual(UpdateHandoff.consumeOutcome(currentVersion: "1.1.0", defaults: defaults),
                       .updated(from: "1.0.0", to: "1.1.0"))
    }

    func testTheSameVersionAfterAnUpdateIsReportedAsAFailure() {
        // The installer was spawned but the swap never happened; silently
        // pretending it worked would leave the user on an old build.
        UpdateHandoff.markInstallStarted(version: "1.0.0", defaults: defaults)
        XCTAssertEqual(UpdateHandoff.consumeOutcome(currentVersion: "1.0.0", defaults: defaults),
                       .unchanged(version: "1.0.0"))
    }

    func testTheNoteIsConsumedSoItReportsOnlyOnce() {
        UpdateHandoff.markInstallStarted(version: "1.0.0", defaults: defaults)
        _ = UpdateHandoff.consumeOutcome(currentVersion: "1.1.0", defaults: defaults)
        XCTAssertNil(UpdateHandoff.consumeOutcome(currentVersion: "1.1.0", defaults: defaults),
                     "every later launch would otherwise repeat the same alert")
    }

    func testClearingAbandonsTheNote() {
        // Used when the installer could not be launched at all, where the
        // failure is shown immediately instead of after a restart.
        UpdateHandoff.markInstallStarted(version: "1.0.0", defaults: defaults)
        UpdateHandoff.clear(defaults: defaults)
        XCTAssertNil(UpdateHandoff.consumeOutcome(currentVersion: "1.0.0", defaults: defaults))
    }
}
