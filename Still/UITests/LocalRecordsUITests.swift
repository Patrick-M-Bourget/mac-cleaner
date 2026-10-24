import XCTest
import Darwin
import StillCore

final class LocalRecordsUITests: XCTestCase {
    @MainActor func testManagementPreservesContextAndFreshRecoveryGuard() async throws { try await context(minimum: true) }
    @MainActor func testInitialManagementPreservesContextAndFreshRecoveryGuard() async throws { try await context(minimum: false) }

    @MainActor func testGatedDiagnosticsReturnsToBothActualCallers() async throws {
        continueAfterFailure = false
        let stateID = UUID().uuidString
        let state = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + stateID)
        let downloads = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(stateID.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        let original = downloads.appendingPathComponent("owned-private-context.pdf")
        try Data([47, 53]).write(to: original)
        let scan = try await FolderScanner().scan(downloads)
        var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: downloads))
        let approval = try draft.approve(draft.review())
        let journal = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"))
        XCTAssertTrue(try journal.claim(approval))
        var record = CleanupRecord(batch: approval, target: try XCTUnwrap(approval.targets.first))
        record.state = .cancelled; record.message = "Owned diagnostics fixture; no operation performed"
        try journal.outcome(record)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(journal.records())
        var stateInfo = stat(); XCTAssertEqual(lstat(state.path, &stateInfo), 0)
        var downloadsInfo = stat(); XCTAssertEqual(lstat(downloads.path, &downloadsInfo), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--design-minimum", "--ui-test-downloads-root", "--future-milestones"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": state.path, "STILL_TEST_STATE_ID": "\(stateInfo.st_dev):\(stateInfo.st_ino)", "STILL_TEST_DOWNLOADS_ROOT": downloads.path, "STILL_TEST_DOWNLOADS_ID": "\(downloadsInfo.st_dev):\(downloadsInfo.st_ino)"]
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: downloads) }
        app.launch(); app.typeKey("2", modifierFlags: .command)
        app.buttons["Scan Downloads…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: category)
        await fulfillment(of: [ready], timeout: 20)
        category.click()
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "local-records-diagnostics-minimum-" + name; image.lifetime = .keepAlways; add(image)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        for (shortcut, caller) in [("3", "History"), ("4", "Locations & access")] {
            app.typeKey(shortcut, modifierFlags: .command)
            let disclosure = app.disclosureTriangles.firstMatch
            revealScrollElement(app, control: disclosure, label: "Retain caller disclosure")
            if disclosure.value as? Int != 1 {
                disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
            }
            let manage = app.buttons["manageLocalRecords"]
            revealScrollElement(app, control: manage, label: "Caller local records")
            let callerFrame = manage.frame
            manage.click()
            let open = app.buttons["Review diagnostics"]
            guard open.waitForExistence(timeout: 5) else {
                capture(caller + "-missing-diagnostics-entry")
                XCTFail("Local records must offer gated diagnostics from " + caller)
                return
            }
            revealScrollElement(app, control: open, label: "Gated diagnostics")
            open.click()
            let payload = app.staticTexts["diagnosticsPayload"]
            XCTAssertTrue(payload.waitForExistence(timeout: 5))
            let frozen = payload.value as? String ?? payload.label
            XCTAssertFalse(frozen.contains(original.lastPathComponent)); XCTAssertFalse(frozen.contains(state.path))
            let back = app.buttons["Back to " + caller]
            XCTAssertTrue(back.isHittable); XCTAssertFalse(app.buttons["Back to Local records"].exists)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                capture(caller + "-" + theme)
                app.buttons["Save diagnostics…"].click()
                XCTAssertTrue(app.dialogs.buttons["Cancel"].waitForExistence(timeout: 5)); app.dialogs.buttons["Cancel"].click()
                XCTAssertEqual(payload.value as? String ?? payload.label, frozen)
                XCTAssertTrue((app.staticTexts["diagnosticsStatus"].value as? String ?? app.staticTexts["diagnosticsStatus"].label).contains("Save cancelled"))
            }
            app.typeKey("w", modifierFlags: .command)
            XCTAssertNotEqual(app.state, .notRunning)
            app.activate(); app.menuBars.menuBarItems["Window"].click(); app.menuItems["Show Still"].firstMatch.click()
            XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(back.isHittable)
            XCTAssertEqual(payload.value as? String ?? payload.label, frozen)
            capture(caller + "-reopened")
            back.click()
            XCTAssertTrue(manage.waitForExistence(timeout: 5)); XCTAssertEqual(manage.frame, callerFrame)
            XCTAssertEqual(app.disclosureTriangles.firstMatch.value as? Int, 1)
            XCTAssertFalse(back.exists)
            XCTAssertFalse(app.buttons["Back to Local records"].exists)
        }
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.staticTexts["liveSelectionSummary"].value as? String, "1 file selected")
        XCTAssertTrue(app.buttons["Review cleanup"].isEnabled)
        XCTAssertEqual(try encoder.encode(journal.records()), before)
        XCTAssertEqual(try Data(contentsOf: original), Data([47, 53]))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor private func context(minimum: Bool) async throws {
        continueAfterFailure = false
        let stateID = UUID().uuidString
        let state = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + stateID)
        let downloads = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(stateID.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        let original = downloads.appendingPathComponent("owned-context.pdf")
        try Data([37, 43]).write(to: original)
        let scan = try await FolderScanner().scan(downloads)
        var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: downloads))
        let journal = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"))
        for index in 0..<5 {
            let approval = try draft.approve(draft.review())
            XCTAssertTrue(try journal.claim(approval))
            var record = CleanupRecord(batch: approval, target: try XCTUnwrap(approval.targets.first))
            record.state = .cancelled; record.message = "Owned completed context fixture; original unchanged"
            if index == 0 { record.outcomeRecordedAt = Date(timeIntervalSinceNow: -100 * 86_400) }
            try journal.outcome(record)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let beforeOpening = try encoder.encode(journal.records())
        var stateInfo = stat(); XCTAssertEqual(lstat(state.path, &stateInfo), 0)
        var downloadsInfo = stat(); XCTAssertEqual(lstat(downloads.path, &downloadsInfo), 0)
        let app = XCUIApplication()
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size", "--ui-test-downloads-root"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": state.path, "STILL_TEST_STATE_ID": "\(stateInfo.st_dev):\(stateInfo.st_ino)", "STILL_TEST_DOWNLOADS_ROOT": downloads.path, "STILL_TEST_DOWNLOADS_ID": "\(downloadsInfo.st_dev):\(downloadsInfo.st_ino)"]
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: downloads) }
        app.launch()
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = "local-records-" + (minimum ? "minimum-" : "initial-") + name
            attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        let manage = app.buttons["manageLocalRecords"]
        // Locations entry must only read records, including an expired fixture. History
        // has its own existing retention contract and has deliberately not opened yet.
        app.typeKey("4", modifierFlags: .command)
        revealScrollElement(app, control: manage, label: "Locations local records")
        let locationsFrame = manage.frame
        manage.click()
        XCTAssertTrue(app.buttons["Back to Locations & access"].waitForExistence(timeout: 5))
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            XCTAssertTrue(app.buttons["Back to Locations & access"].isHittable)
            capture("locations-management-" + theme)
        }
        XCTAssertEqual(try encoder.encode(journal.records()), beforeOpening)
        app.buttons["clearHistory"].click()
        XCTAssertTrue(app.sheets.buttons["Cancel"].waitForExistence(timeout: 3))
        app.sheets.buttons["Cancel"].click()
        XCTAssertEqual(try encoder.encode(journal.records()), beforeOpening)
        app.buttons["Back to Locations & access"].click()
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); XCTAssertEqual(manage.frame, locationsFrame)
        // A real owned scan and live choice must survive all record-management routes.
        app.typeKey("2", modifierFlags: .command)
        app.buttons["Scan Downloads…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: category)
        await fulfillment(of: [ready], timeout: 20)
        category.click()
        XCTAssertEqual(app.staticTexts["liveSelectionSummary"].value as? String, "1 file selected")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        let disclosure = app.disclosureTriangles.firstMatch
        revealScrollElement(app, control: disclosure, label: "History per-file evidence")
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
        XCTAssertTrue(app.staticTexts["owned-context.pdf"].firstMatch.waitForExistence(timeout: 5))
        revealScrollElement(app, control: manage, label: "History local records")
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -40)
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(manage.frame))
        let historyFrame = manage.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            capture("history-before-" + theme)
            manage.click()
            XCTAssertTrue(app.buttons["Back to History"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.staticTexts["Local records"].frame))
            capture("management-" + theme)
            app.buttons["clearHistory"].click()
            XCTAssertTrue(app.sheets.buttons["Cancel"].waitForExistence(timeout: 3)); capture("clear-cancel-" + theme)
            app.sheets.buttons["Cancel"].click()
            app.buttons["Back to History"].click()
            XCTAssertTrue(manage.waitForExistence(timeout: 5)); XCTAssertEqual(manage.frame, historyFrame)
            XCTAssertEqual(disclosure.value as? Int, 1)
        }
        manage.click()
        let reset = app.buttons["resetStill"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        let resetReady = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: reset)
        await fulfillment(of: [resetReady], timeout: 5)
        // Insert unfinished facts after the panel's fresh read. Reset must consult
        // the actual journal rather than cached completed-history evidence.
        let interrupted = try draft.approve(draft.review()); XCTAssertTrue(try journal.claim(interrupted))
        let protectedFacts = try encoder.encode(journal.records())
        reset.click(); app.sheets.buttons["Reset Still"].click()
        let status = app.staticTexts["historyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue((status.value as? String ?? status.label).contains("Reset is blocked by unfinished cleanup records."))
        let review = app.buttons["localRecordsRecovery"]
        revealScrollElement(app, control: review, label: "Recovery from Local records")
        if minimum {
            let beforeScroll = review.frame
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -40)
            XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(review.frame))
            XCTAssertNotEqual(review.frame, beforeScroll, "Exercise an observed nonzero Local records viewport")
        }
        let panelFrame = review.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("blocked-" + theme)
            review.click()
            XCTAssertTrue(app.staticTexts["Review interrupted cleanup"].waitForExistence(timeout: 5))
            let back = app.buttons["Back to Local records"]
            XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(back.isHittable)
            capture("recovery-" + theme)
            back.click()
            XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertEqual(review.frame, panelFrame)
            XCTAssertTrue(app.buttons["Back to History"].isHittable)
        }
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate(); app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertEqual(review.frame, panelFrame)
        XCTAssertTrue(app.buttons["Back to History"].isHittable)
        capture("window-reopened-management")
        review.click(); app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["Back to Local records"].exists)
        XCTAssertFalse(app.buttons["Back to History"].exists)
        revealScrollElement(app, control: manage, label: "New management entry")
        manage.click()
        XCTAssertTrue(app.buttons["Back to History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.staticTexts["Local records"].frame), "New entry starts at the top")
        capture("new-entry-top")
        app.buttons["Back to History"].click()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.staticTexts["liveSelectionSummary"].value as? String, "1 file selected")
        XCTAssertTrue(app.buttons["Review cleanup"].isEnabled)
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["Include " + downloads.lastPathComponent].exists)
        XCTAssertEqual(try encoder.encode(journal.records()), protectedFacts)
        XCTAssertEqual(try Data(contentsOf: original), Data([37, 43]))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }
}
