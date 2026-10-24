import XCTest
import Darwin
import StillCore

final class HistoryUITests: XCTestCase {
    @MainActor func testLocalRecordsUsesBothCallersAndClearPreservesOriginals() async throws {
        continueAfterFailure = false
        let stateID = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + stateID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(stateID.utf8).write(to: root.appendingPathComponent(".still-owned-test-state"))
        var info = stat(); XCTAssertEqual(lstat(root.path, &info), 0)
        let original = root.appendingPathComponent("owned-record.pdf")
        try Data([19, 27]).write(to: original)
        let scan = try await FolderScanner().scan(root)
        var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
        let approval = try draft.approve(draft.review())
        let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
        XCTAssertTrue(try journal.claim(approval))
        for target in approval.targets {
            var record = CleanupRecord(batch: approval, target: target)
            record.state = .cancelled; record.message = "Owned completed fixture; no file operation performed"
            try journal.outcome(record)
        }
        let app = XCUIApplication()
        app.launchArguments = ["--design-minimum"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(info.st_dev):\(info.st_ino)"]
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.launch(); app.typeKey("3", modifierFlags: .command)
        let manage = app.buttons["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        func revealManagement() {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<8 where !scroll.frame.contains(manage.frame) { scroll.scroll(byDeltaX: 0, deltaY: -100) }
            XCTAssertTrue(scroll.frame.contains(manage.frame)); XCTAssertTrue(manage.isHittable)
        }
        revealManagement(); manage.click()
        XCTAssertTrue(app.staticTexts["Local records"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        XCTAssertTrue(app.buttons["Back to History"].isHittable)
        app.buttons["clearHistory"].click()
        XCTAssertTrue(app.sheets.buttons["Cancel"].waitForExistence(timeout: 3))
        app.sheets.buttons["Cancel"].click()
        XCTAssertEqual(try journal.completedHistory().completedRuns.count, 1)
        app.buttons["Back to History"].click()
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Locations & access"].waitForExistence(timeout: 5))
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); revealManagement(); manage.click()
        XCTAssertTrue(app.buttons["Back to Locations & access"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back to History"].exists)
        app.buttons["clearHistory"].click()
        app.sheets.buttons["Clear completed runs"].click()
        let cleared = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        cleared.name = "local-records-clear-status-minimum"; cleared.lifetime = .keepAlways; add(cleared)
        let status = app.staticTexts["historyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue((status.value as? String ?? status.label).hasPrefix("Cleared 1 completed runs."), "Actual maintenance status: " + (status.value as? String ?? status.label))
        XCTAssertTrue(try journal.records().isEmpty)
        app.buttons["Back to Locations & access"].click()
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: original), Data([19, 27]))
        XCTAssertFalse(try journal.claim(approval))
    }
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
        XCTAssertTrue(app.staticTexts["Recorded file results: 1"].waitForExistence(timeout: 5))
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
        let manage = app.buttons["manageLocalRecords"]
        reveal(manage); manage.click()
        XCTAssertTrue(app.buttons["Back to History"].waitForExistence(timeout: 5))
        let clear = app.buttons["clearHistory"]
        reveal(clear); XCTAssertTrue(clear.exists); clear.click()
        XCTAssertTrue(app.sheets.firstMatch.buttons["Cancel"].waitForExistence(timeout: 2)); capture("local-records-clear-confirmation")
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertEqual(try journal.completedHistory().completedRuns.count, 1)
        clear.click(); app.sheets.firstMatch.buttons["Clear completed runs"].click()
        XCTAssertTrue(app.staticTexts["historyStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(try journal.records().isEmpty)
        app.buttons["Back to History"].click()
        XCTAssertTrue(app.staticTexts["No completed runs"].waitForExistence(timeout: 5))
        reveal(manage); manage.click()
        let reset = app.buttons["resetStill"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: reset)
        wait(for: [ready], timeout: 5)
        // Insert new unfinished evidence AFTER Local records loaded. Reset must read it afresh.
        let another = try draft.approve(draft.review())
        XCTAssertTrue(try journal.claim(another))
        reveal(reset); reset.click(); app.sheets.firstMatch.buttons["Reset Still"].click()
        let blocked = app.staticTexts["Reset is blocked by unfinished cleanup records. Open recovery review; no operations will resume automatically."]
        XCTAssertTrue(blocked.waitForExistence(timeout: 5))
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("local-records-reset-blocked-" + theme)
        }
        reveal(app.buttons["localRecordsRecovery"]); app.buttons["localRecordsRecovery"].click()
        XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 unresolved · 1 not started"].exists)
        app.buttons["Back to Local records"].click()
        XCTAssertTrue(app.buttons["localRecordsRecovery"].waitForExistence(timeout: 5))
        // Public journal fixture now supplies a known not-moved outcome, never a retry.
        var known = CleanupRecord(batch: another, target: try XCTUnwrap(another.targets.first)); known.state = .cancelled
        try journal.outcome(known)
        reveal(reset); reset.click(); app.sheets.firstMatch.buttons["Reset Still"].click()
        XCTAssertTrue(app.staticTexts["historyStatus"].waitForExistence(timeout: 5))
        app.buttons["Back to History"].click()
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
