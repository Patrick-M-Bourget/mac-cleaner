import XCTest
import Darwin
import StillCore

final class RecoveryUITests: XCTestCase {
    private func stateRoot() throws -> (URL, [String: String]) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try String(root.lastPathComponent.dropFirst("StillTestState-".count)).write(to: root.appendingPathComponent(".still-owned-test-state"), atomically: false, encoding: .utf8)
        var info = stat()
        guard lstat(root.path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        return (root, ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(info.st_dev):\(info.st_ino)"])
    }
    @MainActor
    func testStartupRecoveryRetainsUnknownFactsAndNeverRestoresPlan() async throws { try await review(minimum: false) }
    @MainActor
    func testMinimumRecoveryKeepsEvidenceAndReturnActionReachable() async throws { try await review(minimum: true) }
    @MainActor
    private func review(minimum: Bool) async throws {
        continueAfterFailure = false
        let (root, environment) = try stateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        for name in ["01-unresolved.pdf", "02-succeeded.pdf", "03-failed.pdf", "04-not-started.pdf"] { try Data([7]).write(to: downloads.appendingPathComponent(name)) }
        let scan = try await FolderScanner().scan(downloads)
        var plan = PlanDraft()
        _ = plan.selectAll(in: [scan], downloads: try DownloadsRoot(url: downloads))
        let approval = try plan.approve(plan.review())
        do {
            let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
            XCTAssertTrue(try journal.claim(approval))
            for (target, state) in zip(approval.targets, [CleanupTargetState.intent, .succeeded, .failed, .pending]) {
                var record = CleanupRecord(batch: approval, target: target)
                record.state = state; record.message = "Disposable journal fixture · Recorded evidence only"
                try journal.outcome(record)
            }
        }
        let holding = root.appendingPathComponent("owned-holding.pdf")
        try FileManager.default.moveItem(at: downloads.appendingPathComponent("01-unresolved.pdf"), to: holding)
        let app = XCUIApplication()
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        XCTAssertTrue(app.staticTexts["1 unresolved · 1 not started"].exists)
        XCTAssertTrue(app.staticTexts["2 recorded results in these batches"].exists)
        XCTAssertTrue(app.staticTexts["Unresolved · Outcome unknown"].exists)
        XCTAssertFalse(app.buttons["Move to Trash"].exists)
        for appearance in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[appearance].click()
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "recovery-" + (minimum ? "minimum-" : "") + appearance; shot.lifetime = .keepAlways; add(shot)
            XCTAssertTrue(bounds.contains(app.buttons["Return to Overview"].frame))
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        XCTAssertTrue(app.staticTexts["Recorded success · Moved to Trash"].waitForExistence(timeout: 3))
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        XCTAssertTrue(app.staticTexts["Recorded failure"].waitForExistence(timeout: 3))
        app.buttons["Return to Overview"].click()
        XCTAssertTrue(app.buttons["Review interrupted cleanup"].exists)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "0 files selected")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertFalse(app.buttons["Move to Trash"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 unresolved · 1 not started"].exists)
        app.terminate()
        XCTAssertEqual(try Data(contentsOf: holding), Data([7]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("01-unresolved.pdf").path))
        XCTAssertEqual(try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"), readOnly: true).records().map(\.state), [.intent, .succeeded, .failed, .pending])
    }
    @MainActor
    func testMissingAndCorruptOwnedJournalNeverFallsBackToNormalState() throws {
        continueAfterFailure = false
        let (root, environment) = try stateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        var invalid = environment; invalid["STILL_TEST_STATE_ID"] = "0:0"
        app.launchEnvironment = invalid; app.launch()
        XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
        app.terminate()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cleanup.sqlite").path))
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cleanup.sqlite").path))
        app.terminate()
        let corrupt = Data("owned corrupt database fixture".utf8)
        try corrupt.write(to: root.appendingPathComponent("cleanup.sqlite"))
        app.launch()
        XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The local cleanup journal could not be read. Outcomes cannot be confirmed. Nothing will resume automatically."].exists)
        XCTAssertFalse(app.buttons["Move to Trash"].exists)
        app.terminate()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("cleanup.sqlite")), corrupt)
    }
}
