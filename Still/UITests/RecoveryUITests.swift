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
        let summary = app.staticTexts["liveSelectionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertEqual(summary.value as? String, "0 files selected")
        XCTAssertTrue(app.staticTexts["Not scanned"].exists)
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
    func testManualHistoryRecoveryReturnsToHistoryWithoutChangingFacts() async throws {
        continueAfterFailure = false
        let (root, environment) = try stateRoot()
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        let original = downloads.appendingPathComponent("owned-interrupted.pdf")
        try Data([17, 23]).write(to: original)
        let scan = try await FolderScanner().scan(downloads)
        var draft = PlanDraft()
        _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: downloads))
        let approval = try draft.approve(draft.review())
        let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
        XCTAssertTrue(try journal.claim(approval))
        let before = try journal.records()
        app.launchArguments = ["--design-minimum"]
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.buttons["Return to Overview"].waitForExistence(timeout: 5))
        app.buttons["Return to Overview"].click()
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.buttons["historyRecovery"].waitForExistence(timeout: 5))
        app.buttons["historyRecovery"].click()
        let back = app.buttons["Back to History"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        back.click()
        XCTAssertTrue(app.buttons["historyRecovery"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back to History"].exists)
        XCTAssertFalse(app.buttons["Move to Trash"].exists)
        app.terminate()
        XCTAssertEqual(try Data(contentsOf: original), Data([17, 23]))
        XCTAssertEqual(try journal.records().map(\.state), before.map(\.state))
        XCTAssertEqual(try journal.records().map(\.originalURL), before.map(\.originalURL))
    }
    @MainActor
    func testHistoryRecoveryPreservesExpandedEvidenceAndObservedViewport() async throws { try await historyContext(minimum: true) }
    @MainActor
    func testInitialHistoryRecoveryPreservesExpandedEvidenceAndObservedViewport() async throws { try await historyContext(minimum: false) }
    @MainActor
    private func historyContext(minimum: Bool) async throws {
        continueAfterFailure = false
        let (root, environment) = try stateRoot()
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        let original = downloads.appendingPathComponent("owned-history-evidence.pdf")
        try Data([31, 41]).write(to: original)
        let scan = try await FolderScanner().scan(downloads)
        var draft = PlanDraft()
        _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: downloads))
        let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
        for _ in 0..<4 {
            let approval = try draft.approve(draft.review())
            XCTAssertTrue(try journal.claim(approval))
            var record = CleanupRecord(batch: approval, target: try XCTUnwrap(approval.targets.first))
            record.state = .cancelled; record.message = "Owned recorded cancellation; original unchanged"
            try journal.outcome(record)
        }
        let interrupted = try draft.approve(draft.review())
        XCTAssertTrue(try journal.claim(interrupted))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(journal.records())
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size", "--ui-test-downloads-root"]
        app.launchEnvironment = environment
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = downloads.path
        app.launch()
        XCTAssertTrue(app.buttons["Return to Overview"].waitForExistence(timeout: 5))
        let startupHeader = app.staticTexts["Review interrupted cleanup"].frame
        func capture(_ state: String) {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "recovery-context-" + (minimum ? "minimum-" : "initial-") + state
            image.lifetime = .keepAlways; add(image)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            XCTAssertTrue(app.buttons["Return to Overview"].isHittable)
            capture("startup-" + theme)
        }
        app.buttons["Return to Overview"].click()
        // An owned live choice keeps the process alive across native window closure.
        let choose = app.buttons["Choose folder…"]
        revealScrollElement(app, control: choose, label: "Choose owned Downloads")
        choose.click(); app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 15)
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertEqual(app.staticTexts["liveSelectionSummary"].value as? String, "1 file selected")
        app.typeKey("3", modifierFlags: .command)
        let recoveryButton = app.buttons["historyRecovery"]
        XCTAssertTrue(recoveryButton.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        let disclosure = app.disclosureTriangles.firstMatch
        for _ in 0..<8 where !scroll.frame.contains(disclosure.frame) { scroll.scroll(byDeltaX: 0, deltaY: -100) }
        XCTAssertTrue(disclosure.isHittable)
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
        let expanded = app.staticTexts["owned-history-evidence.pdf"].firstMatch
        XCTAssertTrue(expanded.waitForExistence(timeout: 5))
        for _ in 0..<12 where !scroll.frame.contains(recoveryButton.frame) { scroll.scroll(byDeltaX: 0, deltaY: 80) }
        scroll.scroll(byDeltaX: 0, deltaY: -40)
        XCTAssertTrue(scroll.frame.contains(recoveryButton.frame))
        XCTAssertTrue(recoveryButton.isHittable)
        let observed = recoveryButton.frame
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            capture("history-before-" + theme)
            recoveryButton.click()
            let back = app.buttons["Back to History"]
            XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(back.isHittable)
            XCTAssertTrue(bounds.contains(back.frame))
            XCTAssertEqual(app.staticTexts["Review interrupted cleanup"].frame, startupHeader)
            capture("manual-history-" + theme)
            back.click()
            XCTAssertTrue(recoveryButton.waitForExistence(timeout: 5))
            XCTAssertEqual(recoveryButton.frame, observed)
            XCTAssertTrue(expanded.exists, "Expanded recorded evidence survives recovery return")
            XCTAssertEqual(app.disclosureTriangles.firstMatch.value as? Int, 1)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            capture("history-return-" + theme)
        }
        recoveryButton.click()
        XCTAssertTrue(app.buttons["Back to History"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate(); app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(app.buttons["Back to History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Back to History"].isHittable)
        XCTAssertEqual(app.staticTexts["Review interrupted cleanup"].frame, startupHeader)
        app.buttons["Back to History"].click()
        XCTAssertTrue(recoveryButton.waitForExistence(timeout: 5))
        XCTAssertEqual(recoveryButton.frame, observed)
        XCTAssertEqual(app.disclosureTriangles.firstMatch.value as? Int, 1)
        capture("window-reopened-history")
        // Sidebar navigation clears contextual Back; new Overview entry owns its return.
        recoveryButton.click(); app.typeKey("1", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Back to History"].exists)
        let overviewRecovery = app.buttons["Review interrupted cleanup"]
        revealScrollElement(app, control: overviewRecovery, label: "Overview recovery")
        let overviewFrame = overviewRecovery.frame
        overviewRecovery.click()
        XCTAssertTrue(app.buttons["Return to Overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back to History"].exists)
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            XCTAssertTrue(app.buttons["Return to Overview"].isHittable)
            capture("manual-overview-" + theme)
        }
        app.buttons["Return to Overview"].click()
        XCTAssertEqual(overviewRecovery.frame, overviewFrame)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.staticTexts["liveSelectionSummary"].value as? String, "1 file selected")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Return to Overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back to History"].exists)
        app.buttons["Return to Overview"].click(); app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.staticTexts["liveSelectionSummary"].value as? String, "0 files selected")
        app.terminate()
        XCTAssertEqual(try Data(contentsOf: original), Data([31, 41]))
        XCTAssertEqual(try encoder.encode(journal.records()), before)
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
