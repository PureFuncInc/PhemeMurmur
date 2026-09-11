import XCTest
@testable import PhemeMurmur

final class SemanticVersionTests: XCTestCase {

    func testParsesAPlainVersion() {
        XCTAssertEqual(SemanticVersion("1.2.3")?.description, "1.2.3")
    }

    func testToleratesTheLeadingVOnGitHubTags() {
        XCTAssertEqual(SemanticVersion("v0.4.1")?.description, "0.4.1")
    }

    func testRejectsAnythingThatIsNotThreeNumericSegments() {
        for raw in ["1.2", "1.2.3.4", "1.2.x", "", "v", "latest"] {
            XCTAssertNil(SemanticVersion(raw), "should not parse: \(raw)")
        }
    }

    func testComparesSegmentWise() {
        XCTAssertLessThan(SemanticVersion("1.2.3")!, SemanticVersion("1.2.4")!)
        XCTAssertLessThan(SemanticVersion("1.2.9")!, SemanticVersion("1.3.0")!)
        XCTAssertLessThan(SemanticVersion("1.9.9")!, SemanticVersion("2.0.0")!)
        // Not lexicographic: "10" beats "9" numerically.
        XCTAssertLessThan(SemanticVersion("1.9.0")!, SemanticVersion("1.10.0")!)
    }
}

final class GitHubReleaseFetcherTests: XCTestCase {

    func testParsesTagAndPageOutOfTheReleasePayload() throws {
        let json = """
        {"tag_name":"v2.1.0","html_url":"https://github.com/o/r/releases/tag/v2.1.0","name":"x"}
        """.data(using: .utf8)!
        let (tag, url) = try GitHubReleaseFetcher.parse(json)
        XCTAssertEqual(tag, "v2.1.0")
        XCTAssertEqual(url.absoluteString, "https://github.com/o/r/releases/tag/v2.1.0")
    }

    func testRejectsAPayloadMissingTheFieldsItNeeds() {
        let json = #"{"name":"just a name"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GitHubReleaseFetcher.parse(json))
    }
}

/// Stub so the checker can be exercised without touching the network.
private struct StubFetcher: ReleaseFetching {
    var tag: String = "1.0.0"
    var error: Error?

    func latestRelease() async throws -> (tag: String, url: URL) {
        if let error { throw error }
        return (tag, URL(string: "https://example.com/release")!)
    }
}

final class UpdateCheckerTests: XCTestCase {

    func testReportsAnUpdateWhenTheReleaseIsNewer() async {
        let checker = UpdateChecker(current: "1.0.0", fetcher: StubFetcher(tag: "v1.1.0"))
        guard case .updateAvailable(let current, let latest, _) = await checker.check() else {
            return XCTFail("expected an available update")
        }
        XCTAssertEqual(current, "1.0.0")
        XCTAssertEqual(latest, "1.1.0")
    }

    func testReportsUpToDateOnAnEqualRelease() async {
        let checker = UpdateChecker(current: "1.1.0", fetcher: StubFetcher(tag: "v1.1.0"))
        let outcome = await checker.check()
        XCTAssertEqual(outcome, .upToDate(current: "1.1.0"))
    }

    func testATaggedReleaseOlderThanThisBuildIsNotAnUpdate() async {
        // A local build can legitimately run ahead of the newest published tag.
        let checker = UpdateChecker(current: "2.0.0", fetcher: StubFetcher(tag: "v1.9.9"))
        let outcome = await checker.check()
        XCTAssertEqual(outcome, .upToDate(current: "2.0.0"))
    }

    func testAnUnparseableVersionFailsRatherThanGuessing() async {
        let checker = UpdateChecker(current: "dev", fetcher: StubFetcher(tag: "v1.0.0"))
        guard case .failed = await checker.check() else {
            return XCTFail("an unparseable current version must not compare as up to date")
        }
    }

    func testANetworkErrorIsReportedAsAFailure() async {
        let checker = UpdateChecker(current: "1.0.0",
                                    fetcher: StubFetcher(error: UpdateCheckError.http(503)))
        guard case .failed(let message) = await checker.check() else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(message.contains("503"), message)
    }
}

final class AppUpdaterTests: XCTestCase {

    func testQuotesPathsWithSpaces() {
        XCTAssertEqual(AppUpdater.shellQuoted("/Users/a b/x.sh"), "'/Users/a b/x.sh'")
    }

    func testEscapesEmbeddedApostrophes() {
        // A bare single quote would close the quoting and let the rest of the
        // path be interpreted by the shell.
        XCTAssertEqual(AppUpdater.shellQuoted("/tmp/it's"), #"'/tmp/it'\''s'"#)
    }

    func testTheInstallerIsSpawnedDetachedFromTheApp() {
        let command = AppUpdater.detachedCommand(script: "/tmp/i.sh", log: "/tmp/i.log")
        // nohup and & are what let the script outlive the app it is about to quit.
        XCTAssertTrue(command.hasPrefix("nohup /bin/bash "), command)
        XCTAssertTrue(command.hasSuffix("&"), command)
        XCTAssertTrue(command.contains("'/tmp/i.sh'"), command)
        XCTAssertTrue(command.contains("> '/tmp/i.log' 2>&1"), command)
    }

    func testInstallingWithoutABundledScriptFails() {
        XCTAssertThrowsError(try AppUpdater.run(script: nil)) { error in
            XCTAssertEqual(error as? AppUpdater.Failure, .scriptMissing)
        }
    }
}

final class UpdateAlertContentTests: XCTestCase {

    private let releaseURL = URL(string: "https://example.com/release")!

    func testUpToDateOffersOnlyAnAcknowledgement() {
        let content = UpdateAlertContent(outcome: .upToDate(current: "1.0.0"),
                                         canSelfUpdate: true)
        XCTAssertEqual(content.buttons.count, 1)
        XCTAssertNil(content.downloadURL)
        XCTAssertFalse(content.installs)
        XCTAssertTrue(content.informative.contains("1.0.0"))
    }

    func testAnInstallableUpdateInstallsInPlace() {
        let content = UpdateAlertContent(
            outcome: .updateAvailable(current: "1.0.0", latest: "1.1.0", url: releaseURL),
            canSelfUpdate: true)
        XCTAssertTrue(content.installs)
        XCTAssertNil(content.downloadURL, "an in-place update must not open the browser instead")
        XCTAssertEqual(content.buttons.count, 2)
        XCTAssertTrue(content.informative.contains("1.1.0"))
    }

    func testABuildOutsideApplicationsIsSentToTheReleasePageInstead() {
        // The installer always replaces /Applications/PhemeMurmur.app, so a copy
        // running elsewhere must never trigger it.
        let content = UpdateAlertContent(
            outcome: .updateAvailable(current: "1.0.0", latest: "1.1.0", url: releaseURL),
            canSelfUpdate: false)
        XCTAssertFalse(content.installs)
        XCTAssertEqual(content.downloadURL, releaseURL)
    }

    func testAFailureShowsTheReasonItGotBack() {
        let content = UpdateAlertContent(outcome: .failed("網路逾時"), canSelfUpdate: true)
        XCTAssertEqual(content.informative, "網路逾時")
        XCTAssertFalse(content.installs)
        XCTAssertNil(content.downloadURL)
    }
}
