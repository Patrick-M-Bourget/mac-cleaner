import XCTest
import Darwin
import StillCore

final class HistoryActivityUITests: XCTestCase {
    @MainActor func testCompletedScanAppearsInHistoryWithoutRestoringSelection() throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let token = UUID().uuidString
        let state = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
        let downloads = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + token)
        for url in [state, downloads] { try manager.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        try Data(token.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        let file = downloads.appendingPathComponent("Owned-history.pdf")
        let original = Data([1, 5, 9]); try original.write(to: file)
        var stateID = stat(); var rootID = stat()
        XCTAssertEqual(lstat(state.path, &stateID), 0); XCTAssertEqual(lstat(downloads.path, &rootID), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": state.path, "STILL_TEST_STATE_ID": "\(stateID.st_dev):\(stateID.st_ino)", "STILL_TEST_DOWNLOADS_ROOT": downloads.path, "STILL_TEST_DOWNLOADS_ID": "\(rootID.st_dev):\(rootID.st_ino)"]
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: downloads) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app)
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        let completed = app.staticTexts["Completed scan"]
        guard completed.waitForExistence(timeout: 5) else {
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "history-activity-missing-completed-scan"; capture.lifetime = .keepAlways; add(capture)
            XCTFail("An explicit completed scan must produce a retained scan activity record in History")
            return
        }
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(completed.waitForExistence(timeout: 5), "Scan activity survives Quit")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertFalse(app.staticTexts["1 file selected"].exists, "History must not restore cleanup choices")
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    @MainActor func testHistoryFiltersPreserveChoicesAtInitialSize() async throws { try await exerciseFilters(minimum: false) }
    @MainActor func testHistoryFiltersPreserveChoicesAtMinimumSize() async throws { try await exerciseFilters(minimum: true) }
    @MainActor private func exerciseFilters(minimum: Bool) async throws {
        continueAfterFailure = false
        let manager = FileManager.default, token = UUID().uuidString
        let state = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
        let downloads = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + token)
        for url in [state, downloads] { try manager.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        try Data(token.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        let file = downloads.appendingPathComponent("Retained-choice.pdf"); try Data([4, 2]).write(to: file)
        let observed = try await FolderScanner().scan(downloads)
        var draft = PlanDraft(); _ = draft.selectAll(in: [observed], downloads: try DownloadsRoot(url: downloads))
        let approval = try draft.approve(draft.review())
        let journal = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"))
        XCTAssertTrue(try journal.claim(approval))
        var record = CleanupRecord(batch: approval, target: try XCTUnwrap(approval.targets.first))
        record.state = .cancelled; record.message = "Owned completed fixture; no mutation"
        try journal.outcome(record)
        var stateID = stat(), rootID = stat(); XCTAssertEqual(lstat(state.path, &stateID), 0); XCTAssertEqual(lstat(downloads.path, &rootID), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": state.path, "STILL_TEST_STATE_ID": "\(stateID.st_dev):\(stateID.st_ino)", "STILL_TEST_DOWNLOADS_ROOT": downloads.path, "STILL_TEST_DOWNLOADS_ID": "\(rootID.st_dev):\(rootID.st_ino)"]
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: downloads) }
        app.launch(); XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click(); waitForOverviewScan(app)
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.checkBoxes["downloadsCategorySelection"].waitForExistence(timeout: 5)); app.checkBoxes["downloadsCategorySelection"].click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        let filter = app.popUpButtons["History activity filter"]
        guard filter.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-missing-activity-filter"; image.lifetime = .keepAlways; add(image)
            XCTFail("History needs All activity, Scans and Cleanups filters"); return
        }
        let bounds = app.windows.firstMatch.frame
        func choose(_ label: String) { filter.click(); app.menuItems[label].click() }
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            choose("All activity")
            XCTAssertTrue(app.staticTexts["Completed scan"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["Cleanup run"].exists)
            XCTAssertLessThan(app.staticTexts["Completed scan"].frame.minY, app.staticTexts["Cleanup run"].frame.minY)
            capture("all-" + theme)
            choose("Cleanups"); XCTAssertFalse(app.staticTexts["Completed scan"].exists); XCTAssertTrue(app.staticTexts["Recorded file results: 1"].exists); capture("cleanups-" + theme)
            choose("Scans"); XCTAssertTrue(app.staticTexts["Completed scan"].exists); XCTAssertFalse(app.staticTexts["Recorded file results: 1"].exists); capture("scans-" + theme)
        }
        revealScrollElement(app, control: app.buttons["manageLocalRecords"], label: "Manage local records"); app.buttons["manageLocalRecords"].click()
        XCTAssertTrue(app.buttons["Back to History"].waitForExistence(timeout: 5)); app.buttons["Back to History"].click()
        XCTAssertEqual(filter.value as? String, "Scans")
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: file), Data([4, 2])); XCTAssertEqual(try journal.completedHistory().completedRuns.count, 1)
    }

    @MainActor func testGroupedScanAndStopRetainOneHonestActivityPerOperation() throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
        for folder in [a, b] { try manager.createDirectory(at: folder, withIntermediateDirectories: true); try Data([1, 7]).write(to: folder.appendingPathComponent("Original.pdf")) }
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); app.typeKey("4", modifierFlags: .command)
        func remember(_ folder: URL) {
            XCTAssertTrue(app.buttons["Add folder…"].waitForExistence(timeout: 10)); app.buttons["Add folder…"].click()
            app.typeKey("g", modifierFlags: [.command, .shift]); XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
            app.textFields.firstMatch.typeText(folder.path); app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Remember folder"].click()
        }
        remember(a); remember(b)
        XCTAssertFalse(app.buttons["Stop scan"].exists)
        app.buttons["Scan selected locations"].click()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Scan selected locations"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Completed scan"].waitForExistence(timeout: 5))
        guard app.staticTexts.matching(identifier: "Completed scan").count == 1 && app.staticTexts["Requested locations: 2"].exists else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-ungrouped-terminal-scan"; image.lifetime = .keepAlways; add(image)
            XCTFail("One explicit two-location scan must retain one grouped activity, not one record per location"); return
        }
        for index in 0..<300 { try Data([2]).write(to: a.appendingPathComponent("Slow-" + String(index) + ".txt")) }
        app.typeKey("4", modifierFlags: .command); app.buttons["Scan selected locations"].click()
        let stop = app.buttons["Stop scan"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.click()
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Stopped scan"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Completed scan").count, 1)
        let details = app.disclosureTriangles.firstMatch
        revealScrollElement(app, control: details, label: "Stopped scan details"); details.click()
        XCTAssertTrue(app.staticTexts["Not attempted"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Stop scan"].exists)
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-stopped-group-minimum-" + theme; image.lifetime = .keepAlways; add(image)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for folder in [a, b] { XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Original.pdf")), Data([1, 7])) }
    }

}
