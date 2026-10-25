import XCTest
import Darwin
import StillCore

final class HistoryActivityUITests: XCTestCase {
    @MainActor func testWhatGrewFirstScanStaysInJourney() throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Original.pdf"); try Data([5, 2]).write(to: file)
        app.launchArguments = ["--future-milestones", "--design-minimum"]
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["What grew"].firstMatch.waitForExistence(timeout: 10))
        let start = app.buttons["Scan to establish a baseline"]
        guard start.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "growth52-missing-first-baseline-action"; image.lifetime = .keepAlways; add(image)
            XCTFail("What grew must offer its own explicit first-baseline scan journey"); return
        }
        let bounds = app.windows.firstMatch.frame
        start.click(); app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.buttons["Scan again to compare"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["What grew"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Review cleanup"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "growth52-first-baseline-minimum-" + theme; image.lifetime = .keepAlways; add(image)
        }
        XCTAssertEqual(try Data(contentsOf: file), Data([5, 2]))
    }
    @MainActor func testWhatGrewKeepsIndependentLocationBaselines() async throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillGrowthUI-" + UUID().uuidString)
        let a = root.appendingPathComponent("First location"), b = root.appendingPathComponent("Second location")
        for folder in [a, b] { try manager.createDirectory(at: folder, withIntermediateDirectories: true) }
        let store = GrowthHistoryStore(directory: state.appendingPathComponent("Growth"))
        let recorder = GrowthScanRecorder(store: store)
        try Data([1]).write(to: a.appendingPathComponent("Original.txt"))
        var token = try await recorder.begin(scope: a); _ = try await recorder.complete(try await FolderScanner().scan(a), token: token)
        try Data([2, 3, 4, 5]).write(to: a.appendingPathComponent("Added.txt"))
        token = try await recorder.begin(scope: a); _ = try await recorder.complete(try await FolderScanner().scan(a), token: token)
        try Data([7, 8, 9]).write(to: b.appendingPathComponent("Other.txt"))
        token = try await recorder.begin(scope: b); _ = try await recorder.complete(try await FolderScanner().scan(b), token: token)
        app.launchArguments = ["--future-milestones", "--design-minimum"]
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); app.typeKey("6", modifierFlags: .command)
        let picker = app.popUpButtons["Comparison location"]
        guard picker.waitForExistence(timeout: 10) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "growth52-missing-location-selector"; image.lifetime = .keepAlways; add(image)
            XCTFail("Each location needs its own baseline and comparison selector"); return
        }
        XCTAssertEqual(picker.value as? String, "Second location")
        XCTAssertFalse(app.staticTexts["growthNetChange"].exists)
        picker.click(); app.menuItems["First location"].click()
        XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["growthNetChange"].label.contains("+4 bytes"))
        XCTAssertTrue(app.popUpButtons["Growth breakdown"].exists)
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "growth52-location-comparison-minimum-" + theme; image.lifetime = .keepAlways; add(image)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        picker.click(); app.menuItems["Second location"].click()
        XCTAssertFalse(app.staticTexts["growthNetChange"].exists)
        XCTAssertTrue(app.buttons["Scan again to compare"].exists)
        app.typeKey("1", modifierFlags: .command); app.typeKey("6", modifierFlags: .command)
        XCTAssertEqual(picker.value as? String, "Second location")
    }
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
        revealScrollElement(app, control: details, label: "Stopped scan details")
        details.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
        XCTAssertEqual(details.value as? Int, 1, "The native disclosure must actually expand before inspecting recorded coverage")
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

    @MainActor func testHistoryAvailabilityAndSaveFailureAtInitialSize() throws { try exerciseAvailability(minimum: false) }
    @MainActor func testHistoryAvailabilityAndSaveFailureAtMinimumSize() throws { try exerciseAvailability(minimum: true) }
    @MainActor private func exerciseAvailability(minimum: Bool) throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let original = root.appendingPathComponent("Still-usable.pdf"); try Data([6, 1]).write(to: original)
        let archive = state.appendingPathComponent("Growth/aggregates-v1.json")
        try manager.createDirectory(at: archive, withIntermediateDirectories: true)
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path; app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift]); XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.typeText(root.path); app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click(); waitForOverviewScan(app)
        let warning = app.staticTexts["This scan could not be saved to History. Current results and choices remain available."]
        guard warning.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-save-failure-missing-feedback"; image.lifetime = .keepAlways; add(image)
            XCTFail("A failed scan-history save must be explained without blocking current findings"); return
        }
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-availability-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("save-failed-" + theme) }
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.checkBoxes["downloadsCategorySelection"].waitForExistence(timeout: 5)); app.checkBoxes["downloadsCategorySelection"].click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["History unavailable"].waitForExistence(timeout: 5))
        let filter = app.popUpButtons["History activity filter"]
        filter.click(); app.menuItems["Scans"].click()
        XCTAssertFalse(app.staticTexts["No recorded scans."].exists)
        try manager.removeItem(at: archive)
        app.buttons["Try scan history again"].click()
        XCTAssertTrue(app.staticTexts["No recorded scans."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Completed scan"].exists, "Reload must not replay a failed save or start another scan")
        XCTAssertFalse(app.buttons["Stop scan"].exists)
        app.typeKey("1", modifierFlags: .command); app.buttons["Scan again"].click(); waitForOverviewScan(app)
        XCTAssertFalse(warning.exists)
        let journal = state.appendingPathComponent("cleanup.sqlite")
        XCTAssertFalse(manager.fileExists(atPath: journal.path)); try Data("owned unreadable journal".utf8).write(to: journal)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Completed scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cleanup history is unavailable. The local journal cannot be read. Clear and reset are unavailable; keep its recovery records."].waitForExistence(timeout: 5))
        filter.click(); app.menuItems["All activity"].click()
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("cleanup-unavailable-readable-scan-" + theme) }
        filter.click(); app.menuItems["Cleanups"].click()
        XCTAssertTrue(app.staticTexts["History unavailable"].exists); XCTAssertFalse(app.staticTexts["No recorded cleanup runs."].exists)
        try manager.removeItem(at: journal)
        app.buttons["Try cleanup history again"].click(); XCTAssertTrue(app.staticTexts["No recorded cleanup runs."].waitForExistence(timeout: 5))
        filter.click(); app.menuItems["Scans"].click(); XCTAssertEqual(app.staticTexts.matching(identifier: "Completed scan").count, 1)
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: original), Data([6, 1]))
    }

    @MainActor func testExplicitRetryRecheckRecordsAnotherScanWithoutMovingChangedFile() throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Retry.pdf"); try Data([1, 2]).write(to: file)
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path; app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift]); XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.typeText(root.path); app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click(); waitForOverviewScan(app)
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.checkBoxes["downloadsCategorySelection"].waitForExistence(timeout: 5)); app.checkBoxes["downloadsCategorySelection"].click(); expandPlanItems(app)
        XCTAssertTrue(app.checkBoxes["Selected Retry.pdf"].waitForExistence(timeout: 5))
        app.buttons["Review cleanup"].click(); XCTAssertTrue(app.sheets.buttons["Move to Trash"].waitForExistence(timeout: 5))
        let changed = Data([8, 7, 6, 5]); try changed.write(to: file)
        app.sheets.buttons["Move to Trash"].click()
        XCTAssertTrue(app.staticTexts["No files were moved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Skipped: 1"].exists)
        app.buttons["Recheck unfinished files"].click()
        XCTAssertTrue(app.staticTexts["No unfinished files passed the fresh identity and access checks. Start a new scan from Overview to review changed files."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["No files were moved"].exists)
        app.typeKey("3", modifierFlags: .command)
        let filter = app.popUpButtons["History activity filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5)); filter.click(); app.menuItems["Scans"].click()
        guard app.staticTexts.matching(identifier: "Completed scan").count == 2 else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-explicit-recheck-missing-activity"; image.lifetime = .keepAlways; add(image)
            XCTFail("The explicit unfinished-file Recheck must create its own scan activity, without internal-check duplicates"); return
        }
        filter.click(); app.menuItems["Cleanups"].click(); XCTAssertTrue(app.staticTexts["Cleanup run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recorded file results: 1"].exists)
        app.typeKey("2", modifierFlags: .command); XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertFalse(app.checkBoxes["Selected Retry.pdf"].exists)
        XCTAssertEqual(try Data(contentsOf: file), changed)
        XCTAssertFalse(app.sheets.buttons["Move to Trash"].exists, "Viewing History cannot restore cleanup authority")
    }

    @MainActor func testClearCompletedHistoryNamesAllRecordsAndReportsPartialSuccess() async throws { try await exerciseClearCompletedHistory(minimum: true) }
    @MainActor func testClearCompletedHistoryAtInitialSize() async throws { try await exerciseClearCompletedHistory(minimum: false) }
    @MainActor private func exerciseClearCompletedHistory(minimum: Bool) async throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Kept.pdf"); try Data([3, 9]).write(to: file)
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        let scan = try await FolderScanner().scan(root)
        var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
        let approval = try draft.approve(draft.review()), journal = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"))
        XCTAssertTrue(try journal.claim(approval)); var outcome = CleanupRecord(batch: approval, target: try XCTUnwrap(approval.targets.first)); outcome.state = .cancelled; outcome.message = "Owned terminal fixture; no operation"; try journal.outcome(outcome)
        let growthDirectory = state.appendingPathComponent("Growth"), store = GrowthHistoryStore(directory: growthDirectory)
        let epoch = try await store.recordingEpoch(), now = Date()
        _ = try await store.recordActivity(ScanActivity(startedAt: now.addingTimeInterval(-2), completedAt: now.addingTimeInterval(-1), outcome: .complete, locations: [ScanActivityLocation(path: root.path, observedAt: now.addingTimeInterval(-1), outcome: .complete, entryCount: 1, logicalBytes: 2, allocatedBytes: 4096, knownLogicalBytes: 2)]), expectedEpoch: epoch)
        let fingerprint = GrowthFingerprint(scopeID: "owned-scope", rootID: "owned-root", volumeID: "owned-volume", access: "explicit", rules: "owned", exclusions: "none", classification: "owned")
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Owned folder", observedAt: now, groups: [.init(id: "root", label: "Files", logicalBytes: 2)]), expectedEpoch: epoch)
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]; app.launch(); app.typeKey("3", modifierFlags: .command)
        let filter = app.popUpButtons["History activity filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10)); filter.click(); app.menuItems["Cleanups"].click()
        revealScrollElement(app, control: app.buttons["manageLocalRecords"], label: "Manage local records"); app.buttons["manageLocalRecords"].click()
        XCTAssertTrue(app.buttons["clearHistory"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "history-clear-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        let clear = app.sheets.buttons["Clear completed history"]
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            app.buttons["clearHistory"].click()
            guard clear.waitForExistence(timeout: 5) else {
                capture("ambiguous-confirmation-" + theme)
                XCTFail("Clear completed history must explicitly cover scan activity, completed cleanups and growth baselines regardless of filter"); return
            }
            let consequence = app.sheets.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", "scan activity", "scan activity")).firstMatch
            XCTAssertTrue(consequence.exists)
            capture("confirmation-" + theme)
            app.sheets.buttons["Cancel"].click()
            let beforeActivities = try await store.activities(), beforeBaselines = try await store.snapshots()
            XCTAssertEqual(beforeActivities.count, 1); XCTAssertEqual(beforeBaselines.count, 1); XCTAssertEqual(try journal.completedHistory().completedRuns.count, 1)
            XCTAssertEqual(try Data(contentsOf: file), Data([3, 9]))
        }
        let archive = growthDirectory.appendingPathComponent("aggregates-v1.json"), backup = growthDirectory.appendingPathComponent("owned-archive-backup.json")
        try manager.moveItem(at: archive, to: backup); try manager.createDirectory(at: archive, withIntermediateDirectories: false)
        app.buttons["clearHistory"].click(); clear.click()
        let status = app.staticTexts["historyStatus"]
        let partial = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = status.value as? String ?? status.label
            return text.contains("Cleared 1 completed cleanup run.") && text.contains("Scan activity and growth baseline clearing could not be confirmed.")
        }, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [partial], timeout: 5), .completed)
        XCTAssertTrue(try journal.completedHistory().completedRuns.isEmpty); XCTAssertFalse(try journal.claim(approval))
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            let text = status.value as? String ?? status.label
            XCTAssertTrue(text.contains("Cleared 1 completed cleanup run."))
            XCTAssertTrue(text.contains("Scan activity and growth baseline clearing could not be confirmed."))
            capture("partial-" + theme)
        }
        try manager.removeItem(at: archive); try manager.moveItem(at: backup, to: archive)
        app.buttons["clearHistory"].click(); clear.click()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (status.value as? String ?? status.label).contains("scan activity and growth baselines")
        }, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        let afterActivities = try await store.activities(), afterBaselines = try await store.snapshots()
        XCTAssertTrue(afterActivities.isEmpty); XCTAssertTrue(afterBaselines.isEmpty)
        app.buttons["Back to History"].click(); XCTAssertEqual(filter.value as? String, "Cleanups")
        XCTAssertTrue(app.staticTexts["No recorded cleanup runs."].waitForExistence(timeout: 5))
        filter.click(); app.menuItems["All activity"].click(); XCTAssertTrue(app.staticTexts["No retained history."].exists)
        XCTAssertEqual(app.popUpButtons["Appearance"].value as? String, "Dark")
        XCTAssertEqual(try Data(contentsOf: file), Data([3, 9])); XCTAssertFalse(try journal.claim(approval))
    }

    @MainActor func testHistoricalGrowthReturnAtInitialSize() async throws { try await exerciseHistoricalGrowth(minimum: false) }
    @MainActor func testHistoricalGrowthReturnAtMinimumSize() async throws { try await exerciseHistoricalGrowth(minimum: true) }
    @MainActor private func exerciseHistoricalGrowth(minimum: Bool) async throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let original = root.appendingPathComponent("Chosen.pdf"); try Data([5, 2]).write(to: original)
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--future-milestones", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path; app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift]); XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click(); waitForOverviewScan(app)
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.checkBoxes["downloadsCategorySelection"].waitForExistence(timeout: 5)); app.checkBoxes["downloadsCategorySelection"].click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        let added = root.appendingPathComponent("Added.txt"); try Data([1, 3, 7]).write(to: added)
        app.typeKey("1", modifierFlags: .command); app.buttons["Scan again"].click(); waitForOverviewScan(app)
        app.typeKey("3", modifierFlags: .command)
        let filter = app.popUpButtons["History activity filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5)); filter.click(); app.menuItems["Scans"].click()
        let disclosure = app.disclosureTriangles.firstMatch
        revealScrollElement(app, control: disclosure, label: "Recorded scan details")
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click(); XCTAssertEqual(disclosure.value as? Int, 1)
        let link = app.buttons["See what grew"].firstMatch
        guard link.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-missing-contextual-growth-route"; image.lifetime = .keepAlways; add(image)
            XCTFail("An eligible recorded location needs a gated route to its exact growth observation"); return
        }
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-growth-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image); XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            revealScrollElement(app, control: link, label: "See what grew"); let callerFrame = link.frame; link.click()
            XCTAssertTrue(app.staticTexts["Scope: " + root.lastPathComponent].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["growthNetChange"].exists)
            XCTAssertTrue((app.staticTexts["growthNetChange"].value as? String ?? "").contains("+3"))
            XCTAssertTrue(app.buttons["Back to History"].isHittable); XCTAssertFalse(app.buttons["Inspect a folder"].exists)
            capture("exact-" + theme); app.buttons["Back to History"].click()
            XCTAssertEqual(filter.value as? String, "Scans"); XCTAssertEqual(disclosure.value as? Int, 1)
            XCTAssertTrue(link.exists); XCTAssertFalse(app.buttons["Stop scan"].exists)
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in link.frame == callerFrame }, object: link)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
            capture("history-return-" + theme)
        }
        let store = GrowthHistoryStore(directory: state.appendingPathComponent("Growth"))
        try await store.clearCompletedHistory()
        let now = Date(), epoch = try await store.recordingEpoch()
        let fingerprint = GrowthFingerprint(scopeID: "other", rootID: "other", volumeID: "other", access: "complete", rules: "other", exclusions: "none", classification: "other")
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Other recorded scope", observedAt: now, groups: [.init(id: "files", label: "Files", logicalBytes: 99)]), expectedEpoch: epoch)
        revealScrollElement(app, control: link, label: "Expired exact observation"); link.click()
        XCTAssertTrue(app.staticTexts["Comparison unavailable for this recorded observation."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Scope: Other recorded scope"].exists); XCTAssertFalse(app.staticTexts["growthNetChange"].exists)
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("expired-" + theme) }
        app.buttons["Back to History"].click(); XCTAssertEqual(filter.value as? String, "Scans")
        XCTAssertTrue(app.staticTexts["No recorded scans."].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: original), Data([5, 2])); XCTAssertEqual(try Data(contentsOf: added), Data([1, 3, 7]))
    }

    @MainActor func testPartialAndFailedScanActivityAtInitialSize() throws { try exercisePartialAndFailed(minimum: false) }
    @MainActor func testPartialAndFailedScanActivityAtMinimumSize() throws { try exercisePartialAndFailed(minimum: true) }
    @MainActor private func exercisePartialAndFailed(minimum: Bool) throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        try Data([1]).write(to: root.appendingPathComponent("trigger.txt")); let file = root.appendingPathComponent("Kept.pdf"); try Data([7, 3]).write(to: file)
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--ui-test-directory-instability", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path; app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift]); XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click(); waitForOverviewScan(app, timeout: 30)
        app.typeKey("3", modifierFlags: .command); XCTAssertTrue(app.staticTexts["Partial scan"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-coverage-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image); XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        let partial = app.disclosureTriangles.firstMatch
        revealScrollElement(app, control: partial, label: "Partial scan details"); partial.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click(); XCTAssertEqual(partial.value as? Int, 1)
        let reason = app.staticTexts["Directory changed during scanning: 1"]
        guard reason.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-coverage-raw-reason-copy"; image.lifetime = .keepAlways; add(image)
            XCTFail("Partial coverage needs a plain-language recorded reason, not raw scanner identifiers"); return
        }
        revealScrollElement(app, control: reason, label: "Recorded partial coverage explanation")
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("partial-" + theme) }
        XCTAssertFalse(app.buttons["See what grew"].exists)
        XCTAssertEqual(try Data(contentsOf: file), Data([7, 3]))
        try manager.removeItem(at: root) // Owned fixture makes the previously selected location unavailable.
        app.typeKey("1", modifierFlags: .command); app.buttons["Scan again"].click()
        app.typeKey("3", modifierFlags: .command); XCTAssertTrue(app.staticTexts["Failed scan"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Partial scan").count, 1)
        let failed = app.disclosureTriangles.firstMatch
        revealScrollElement(app, control: failed, label: "Failed scan details"); failed.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click(); XCTAssertEqual(failed.value as? Int, 1)
        let noMeasurements = app.staticTexts["No measurements available"]
        XCTAssertTrue(noMeasurements.waitForExistence(timeout: 5)); revealScrollElement(app, control: noMeasurements, label: "Unknown failed-scan measurements")
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("failed-" + theme) }
        XCTAssertFalse(app.buttons["Stop scan"].exists); XCTAssertFalse(manager.fileExists(atPath: root.path), "History viewing cannot recreate or enumerate the missing location")
    }

    @MainActor func testHistoryGalleryAtInitialSize() throws { try exerciseHistoryGallery(minimum: false) }
    @MainActor func testHistoryGalleryAtMinimumSize() throws { try exerciseHistoryGallery(minimum: true) }
    @MainActor private func exerciseHistoryGallery(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(), manager = FileManager.default
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? manager.removeItem(at: state) }
        app.launchArguments = ["--design-gallery", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch(); XCTAssertTrue(app.staticTexts["Native design system"].waitForExistence(timeout: 10))
        let disclosure = app.disclosureTriangles["Synthetic History activity examples"]
        revealScrollElement(app, control: disclosure, label: "Synthetic History examples")
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click(); XCTAssertEqual(disclosure.value as? Int, 1)
        guard app.staticTexts["historyGalleryCase-partial"].waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-gallery-missing-exceptional-states"; image.lifetime = .keepAlways; add(image)
            XCTFail("The shared History Gallery must include terminal coverage, unknown, unavailable and empty states"); return
        }
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-gallery-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image); XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 12000)
            for name in ["complete", "partial", "stopped", "failed", "multi", "unknown", "unavailable", "empty-all", "empty-scans", "empty-cleanups", "save-failed", "partial-clear"] {
                let heading = app.staticTexts["historyGalleryCase-" + name], end = app.staticTexts["historyGalleryEnd-" + name]
                revealScrollElement(app, control: heading, label: "Synthetic " + name)
                XCTAssertTrue(end.waitForExistence(timeout: 5))
                let viewport = app.scrollViews.firstMatch
                let oversized = end.frame.maxY - heading.frame.minY > viewport.frame.height
                if oversized {
                    // Start a tall example at its heading so its first location is readable.
                    for _ in 0..<12 {
                        let distance = viewport.frame.minY + 8 - heading.frame.minY
                        if abs(distance) <= 1 { break }
                        viewport.scroll(byDeltaX: 0, deltaY: max(-240, min(240, distance)))
                    }
                    XCTAssertTrue(viewport.frame.contains(heading.frame))
                    capture(name + "-top-" + theme)
                }
                for _ in 0..<12 {
                    if viewport.frame.contains(end.frame) && (oversized || viewport.frame.contains(heading.frame)) { break }
                    // Fixed wheel increments can overshoot the small slack of a fitting block.
                    let distance = oversized ? viewport.frame.maxY - 8 - end.frame.maxY
                        : viewport.frame.minY + (viewport.frame.height - (end.frame.maxY - heading.frame.minY)) / 2 - heading.frame.minY
                    viewport.scroll(byDeltaX: 0, deltaY: max(-240, min(240, distance)))
                }
                if !viewport.frame.contains(end.frame) || (!oversized && !viewport.frame.contains(heading.frame)) {
                    let geometry = XCTAttachment(string: "Case: " + name + "\nViewport: \(viewport.frame)\nHeading: \(heading.frame)\nEnd: \(end.frame)\nOversized: \(oversized)\n" + app.debugDescription)
                    geometry.name = "history-gallery-containment-" + name; geometry.lifetime = .keepAlways; add(geometry)
                    capture(name + "-containment-failure-" + theme)
                }
                XCTAssertTrue(viewport.frame.contains(end.frame)); if !oversized { XCTAssertTrue(viewport.frame.contains(heading.frame)) }
                capture(name + "-" + theme)
            }
        }
        XCTAssertTrue(app.staticTexts["No retained history."].exists)
        XCTAssertTrue(app.staticTexts["No recorded scans."].exists)
        XCTAssertTrue(app.staticTexts["No recorded cleanup runs."].exists)
        XCTAssertFalse(manager.fileExists(atPath: state.appendingPathComponent("Growth/aggregates-v1.json").path), "Gallery examples never write history")
    }

    @MainActor func testScanHistoryWarningsAndStoreSpecificReloadsAtInitialSize() throws { try exerciseReviewFix(minimum: false) }
    @MainActor func testScanHistoryWarningsAndStoreSpecificReloadsAtMinimumSize() throws { try exerciseReviewFix(minimum: true) }
    @MainActor private func exerciseReviewFix(minimum: Bool) throws {
        continueAfterFailure = false
        let manager = FileManager.default, app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let original = root.appendingPathComponent("Visible.pdf"); try Data([4, 7]).write(to: original)
        let archive = state.appendingPathComponent("Growth/aggregates-v1.json")
        try manager.createDirectory(at: archive, withIntermediateDirectories: true)
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path; app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        app.launch(); XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10)); app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift]); XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click(); waitForOverviewScan(app)
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.checkBoxes["downloadsCategorySelection"].waitForExistence(timeout: 5)); app.checkBoxes["downloadsCategorySelection"].click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        let warning = app.staticTexts["This scan could not be saved to History. Current results and choices remain available."]
        app.typeKey("4", modifierFlags: .command)
        guard warning.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-review-missing-locations-feedback"; image.lifetime = .keepAlways; add(image)
            XCTFail("Scan-history save failure must remain explained on Locations, the scan caller"); return
        }
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); image.name = "history-review-" + (minimum ? "minimum-" : "initial-") + name; image.lifetime = .keepAlways; add(image); XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("locations-warning-" + theme) }
        app.typeKey("1", modifierFlags: .command); openObservedExplorer(app, root: root)
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("explorer-warning-" + theme) }
        let journal = state.appendingPathComponent("cleanup.sqlite")
        XCTAssertFalse(manager.fileExists(atPath: journal.path)); try Data("owned unreadable journal".utf8).write(to: journal)
        app.typeKey("3", modifierFlags: .command)
        let scanRetry = app.buttons["Try scan history again"], cleanupRetry = app.buttons["Try cleanup history again"]
        XCTAssertTrue(scanRetry.waitForExistence(timeout: 5)); XCTAssertTrue(cleanupRetry.exists)
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("independent-reloads-" + theme) }
        // Both adapters become readable; reloading one must not silently reload the other.
        try manager.removeItem(at: archive); try manager.removeItem(at: journal)
        let filter = app.popUpButtons["History activity filter"]
        filter.click(); app.menuItems["Scans"].click(); scanRetry.click()
        XCTAssertTrue(app.staticTexts["No recorded scans."].waitForExistence(timeout: 5)); XCTAssertTrue(cleanupRetry.exists)
        XCTAssertFalse(scanRetry.exists); XCTAssertFalse(app.buttons["Stop scan"].exists)
        filter.click(); app.menuItems["Cleanups"].click(); XCTAssertTrue(app.staticTexts["History unavailable"].exists)
        cleanupRetry.click(); XCTAssertTrue(app.staticTexts["No recorded cleanup runs."].waitForExistence(timeout: 5))
        XCTAssertFalse(cleanupRetry.exists); XCTAssertFalse(app.staticTexts["Completed scan"].exists)
        app.typeKey("2", modifierFlags: .command); XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: original), Data([4, 7]))
    }

}
