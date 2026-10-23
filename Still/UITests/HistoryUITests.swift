import XCTest
import Darwin
import StillCore

final class HistoryUITests: XCTestCase {
    @MainActor func testCompletedHistoryClearAndFreshResetGuard() async throws { try await exercise(minimum: false) }
    @MainActor func testHistoryAtMinimumWindow() async throws { try await exercise(minimum: true) }
    @MainActor private func exercise(minimum: Bool) async throws {
        continueAfterFailure = false
        let stateID = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + stateID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(stateID.utf8).write(to: root.appendingPathComponent(".still-owned-test-state"))
        var info = stat(); XCTAssertEqual(lstat(root.path, &info), 0)
        let app = XCUIApplication()
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(info.st_dev):\(info.st_ino)"]
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("unrelated-sentinel")
        try Data([9]).write(to: sentinel)
        app.launch(); app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No completed runs"].waitForExistence(timeout: 5))
        app.terminate()
        let files = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false)
        let original = files.appendingPathComponent("owned-history.pdf")
        try Data([7]).write(to: original)
        let scan = try await FolderScanner().scan(files)
        var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: files))
        let approval = try draft.approve(draft.review())
        let url = root.appendingPathComponent("cleanup.sqlite")
        let journal = try SQLiteCleanupJournal(url: url)
        XCTAssertTrue(try journal.claim(approval))
        var record = CleanupRecord(batch: approval, target: try XCTUnwrap(approval.targets.first))
        record.state = .succeeded; record.message = "Disposable history fixture; no filesystem operation performed"
        try journal.outcome(record)
        app.launch(); app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 recorded file results"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = name + (minimum ? "-minimum" : "-initial"); attachment.lifetime = .keepAlways; add(attachment)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("history-populated-" + theme)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        func reveal(_ button: XCUIElement) {
            for _ in 0..<5 where !bounds.contains(button.frame) { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250) }
        }
        let clear = app.buttons["clearHistory"]
        reveal(clear); XCTAssertTrue(clear.exists); clear.click()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 2)); capture("history-clear-confirmation")
        app.buttons["Cancel"].click()
        XCTAssertEqual(try journal.completedHistory().completedRuns.count, 1)
        clear.click(); app.buttons["Clear completed runs"].click()
        XCTAssertTrue(app.staticTexts["No completed runs"].waitForExistence(timeout: 5))
        XCTAssertTrue(try journal.records().isEmpty)
        // Insert new unfinished evidence AFTER History loaded. Reset must read it afresh.
        let another = try draft.approve(draft.review())
        XCTAssertTrue(try journal.claim(another))
        let reset = app.buttons["resetStill"]
        reveal(reset); reset.click(); app.buttons["Reset Still"].click()
        let blocked = app.staticTexts["Reset is blocked by unfinished cleanup records. Open recovery review; no operations will resume automatically."]
        XCTAssertTrue(blocked.waitForExistence(timeout: 5))
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("history-reset-blocked-" + theme)
        }
        app.buttons["historyRecovery"].click()
        XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 unresolved · 1 not started"].exists)
        app.buttons["Return to Overview"].click(); app.typeKey("3", modifierFlags: .command)
        // Public journal fixture now supplies a known not-moved outcome, never a retry.
        var known = CleanupRecord(batch: another, target: try XCTUnwrap(another.targets.first)); known.state = .cancelled
        try journal.outcome(known)
        reveal(reset); reset.click(); app.buttons["Reset Still"].click()
        XCTAssertTrue(app.staticTexts["No completed runs"].waitForExistence(timeout: 5))
        XCTAssertTrue(try journal.records().isEmpty)
        XCTAssertFalse(try journal.claim(approval))
        XCTAssertFalse(try journal.claim(another))
        app.terminate(); app.launch(); app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No completed runs"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: original), Data([7]))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([9]))
    }
}
