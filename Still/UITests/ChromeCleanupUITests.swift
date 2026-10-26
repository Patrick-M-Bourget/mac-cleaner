import XCTest
import StillCore

/// User-visible browser-cache journeys with real files under the app's guarded disposable state.
final class ChromeCleanupUITests: XCTestCase {
    @MainActor func testChromeSelectionCancelAndPermanentCleanupPreservePersonalData() throws {
        try runCleanupJourney(minimum: false)
    }

    @MainActor func testMinimumChromeSelectionCancelAndPermanentCleanupPreservePersonalData() throws {
        try runCleanupJourney(minimum: true)
    }

    @MainActor private func runCleanupJourney(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        let root = try makeChromeFixture(state)
        let downloads = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: downloads) }
        let ordinaryFile = downloads.appendingPathComponent("owned-review.pdf")
        try Data("owned personal-file fixture".utf8).write(to: ordinaryFile)
        app.launchArguments = ["--chrome-cleanup-fixture", "--ui-test-downloads-root", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = downloads.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5)); app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        let downloadsCategory = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(downloadsCategory.waitForExistence(timeout: 5)); downloadsCategory.click()
        app.typeKey("1", modifierFlags: .command)
        revealOverviewControl(app, label: "Review browser caches")
        app.buttons["Review browser caches"].click()
        XCTAssertTrue(app.buttons["Enable Chrome inspection"].waitForExistence(timeout: 5))
        app.buttons["Enable Chrome inspection"].click()
        XCTAssertTrue(app.checkBoxes["chromeGroupSelection-Default"].waitForExistence(timeout: 10))
        let group = app.checkBoxes["chromeGroupSelection-Default"]
        XCTAssertEqual(group.value as? Int, 0)
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "chrome-review-" + (minimum ? "minimum-" : "initial-") + theme; capture.lifetime = .keepAlways; add(capture)
        }
        group.click()
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.buttons["Review cleanup"].waitForExistence(timeout: 5))
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            XCTAssertTrue(app.staticTexts["Selected for cleanup"].exists)
            XCTAssertFalse(app.staticTexts["Selected for Trash"].exists)
            capture(app, name: "chrome-mixed-plan-" + (minimum ? "minimum-" : "initial-") + theme)
            app.buttons["Review cleanup"].click()
            XCTAssertTrue(app.sheets.buttons["Run cleanup"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Permanently clear Chrome asset caches"].exists)
            capture(app, name: "chrome-mixed-confirmation-" + (minimum ? "minimum-" : "initial-") + theme)
            app.sheets.buttons["Cancel"].click()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ordinaryFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0").path))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.sheets.buttons["Run cleanup"].waitForExistence(timeout: 5), "Cancel returns focus to Review cleanup")
        app.sheets.buttons["Run cleanup"].click()
        XCTAssertTrue(app.staticTexts["Chrome cache results"].waitForExistence(timeout: 15))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ordinaryFile.path), "The separately approved ordinary file moves to Trash")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Cookies")), Data("protected-cookie".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Web Data")), Data("protected-autofill".utf8))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            capture(app, name: "chrome-mixed-results-" + (minimum ? "minimum-" : "initial-") + theme)
        }
    }

    @MainActor func testChromeGalleryExamplesAtInitialAndMinimumSizes() throws {
        continueAfterFailure = false
        for minimum in [false, true] {
            let app = XCUIApplication()
            let state = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
            app.launchArguments = ["--design-gallery", minimum ? "--design-minimum" : "--design-initial-size"]
            app.launch()
            let examples = app.disclosureTriangles["Synthetic browser cache groups"]
            revealScrollElement(app, control: examples, label: "Browser cache gallery")
            examples.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
            XCTAssertEqual(examples.value as? Int, 1)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                revealScrollElement(app, control: app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "These cache files do not go to Trash")).firstMatch, label: "Cache permanence notice")
                capture(app, name: "chrome-gallery-top-" + (minimum ? "minimum-" : "initial-") + theme)
                revealScrollElement(app, control: app.checkBoxes["chromeGroupSelection-Profile 5"], label: "Unsupported browser group")
                capture(app, name: "chrome-gallery-groups-" + (minimum ? "minimum-" : "initial-") + theme)
            }
            app.terminate()
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testStoppingDownloadsPreventsStartingChrome() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        let root = try makeChromeFixture(state)
        let downloads = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: downloads) }
        try Data("owned personal file".utf8).write(to: downloads.appendingPathComponent("stop-review.pdf"))
        app.launchArguments = ["--chrome-cleanup-fixture", "--ui-test-downloads-root", "--ui-test-slow-trash", "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = downloads.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5)); app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        app.typeKey("1", modifierFlags: .command)
        revealOverviewControl(app, label: "Review browser caches"); app.buttons["Review browser caches"].click()
        XCTAssertTrue(app.buttons["Enable Chrome inspection"].waitForExistence(timeout: 5)); app.buttons["Enable Chrome inspection"].click()
        let group = app.checkBoxes["chromeGroupSelection-Default"]
        XCTAssertTrue(group.waitForExistence(timeout: 10)); group.click()
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.buttons["Review cleanup"].waitForExistence(timeout: 5)); app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.sheets.buttons["Run cleanup"].waitForExistence(timeout: 5)); app.sheets.buttons["Run cleanup"].click()
        let stop = app.buttons["Stop after current file"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.click()
        XCTAssertTrue(app.staticTexts["Chrome cache results"].waitForExistence(timeout: 20))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0").path), "Stopping the mixed run must preserve the unstarted Chrome stage")
        revealScrollElement(app, control: app.staticTexts["Cancelled"].firstMatch, label: "Cancelled browser group")
        XCTAssertTrue(app.staticTexts["Cancelled"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "0 cache files permanently removed")).firstMatch.exists)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Web Data")), Data("protected-autofill".utf8))
    }

    @MainActor func testChromeRescanKeepsNewGroupsUncheckedAndRunningInvalidatesSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        let root = try makeChromeFixture(state)
        app.launchArguments = ["--chrome-cleanup-fixture", "--design-minimum"]
        app.launch()
        revealOverviewControl(app, label: "Review browser caches"); app.buttons["Review browser caches"].click()
        XCTAssertTrue(app.buttons["Enable Chrome inspection"].waitForExistence(timeout: 5)); app.buttons["Enable Chrome inspection"].click()
        let first = app.checkBoxes["chromeGroupSelection-Default"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        revealScrollElement(app, control: first, label: "Default cache group")
        let bounds = app.windows.firstMatch.frame
        first.click()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 1/Cache/Cache_Data"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("{}".utf8).write(to: root.appendingPathComponent("Profile 1/Preferences"))
        try Data("new cache".utf8).write(to: root.appendingPathComponent("Profile 1/Cache/Cache_Data/fedcba9876543210_0"))
        try Data(#"{"profile":{"info_cache":{"Default":{},"Profile 1":{}}}}"#.utf8).write(to: root.appendingPathComponent("Local State"))
        revealScrollElement(app, control: app.buttons["Recheck Chrome"], label: "Recheck Chrome"); app.buttons["Recheck Chrome"].click()
        let added = app.checkBoxes["chromeGroupSelection-Profile 1"]
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        XCTAssertEqual(first.value as? Int, 1)
        XCTAssertEqual(added.value as? Int, 0, "A new eligible profile never joins the plan automatically")
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            revealScrollElement(app, control: added, label: "New profile group")
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "chrome-review-minimum-" + theme; capture.lifetime = .keepAlways; add(capture)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        try Data("running".utf8).write(to: root.appendingPathComponent("environment.txt"))
        revealScrollElement(app, control: app.buttons["Recheck Chrome"], label: "Recheck Chrome"); app.buttons["Recheck Chrome"].click()
        let runningStatus = app.staticTexts["chromeInspectionStatus"]
        XCTAssertTrue(runningStatus.waitForExistence(timeout: 10))
        let running = expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Running"), evaluatedWith: runningStatus)
        wait(for: [running], timeout: 10)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.buttons["Review cleanup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Cookies")), Data("protected-cookie".utf8))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor func testChromeUnavailableAndEmptyStatesNeverEnableCleanup() throws {
        continueAfterFailure = false
        for (mode, expected) in [("unsupported", "Unsupported version or layout"), ("denied", "Access unavailable"), ("unknown", "Unknown"), ("empty", "No eligible downloaded asset caches found.")] {
            let app = XCUIApplication()
            let state = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
            let root = try makeChromeFixture(state)
            if mode == "empty" {
                try FileManager.default.removeItem(at: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0"))
            } else { try Data(mode.utf8).write(to: root.appendingPathComponent("environment.txt")) }
            app.launchArguments = ["--chrome-cleanup-fixture", "--design-minimum"]
            app.launch()
            revealOverviewControl(app, label: "Review browser caches"); app.buttons["Review browser caches"].click()
            XCTAssertTrue(app.buttons["Enable Chrome inspection"].waitForExistence(timeout: 5)); app.buttons["Enable Chrome inspection"].click()
            let status = app.staticTexts["chromeInspectionStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
            let observed = expectation(for: NSPredicate(format: "value BEGINSWITH %@", expected), evaluatedWith: status)
            wait(for: [observed], timeout: 10)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                revealScrollElement(app, control: status, label: "Chrome " + mode + " state")
                let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                capture.name = "chrome-" + mode + "-minimum-" + theme; capture.lifetime = .keepAlways; add(capture)
            }
            if mode == "empty" {
                XCTAssertTrue(app.checkBoxes["chromeGroupSelection-Default"].exists)
                XCTAssertFalse(app.checkBoxes["chromeGroupSelection-Default"].isEnabled)
            }
            app.buttons["View cleanup plan"].click()
            XCTAssertTrue(app.buttons["Review cleanup"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Web Data")), Data("protected-autofill".utf8))
            app.terminate()
        }
    }

    @MainActor func testHistoryReportsChromeClearWhenDownloadsJournalLaterFails() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        let root = try makeChromeFixture(state)
        let service = ChromeCacheService(environment: ChromeHistoryEnvironment(), journalURL: state.appendingPathComponent("chrome-cleanup.json"))
        let scan = await service.inspect(.init(applicationURL: root.appendingPathComponent("Google Chrome.app"), dataRootURL: root, cacheRootURL: root, customLocation: true))
        let run = await service.execute(try await service.approve(groupIDs: Set(scan.groups.map(\.id))), cancellation: CleanupCancellation())
        XCTAssertEqual(run.groups.first?.status, .succeeded)
        app.launchArguments = ["--chrome-cleanup-fixture", "--design-initial-size"]
        app.launch(); app.typeKey("3", modifierFlags: .command)
        let manage = app.buttons["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); revealScrollElement(app, control: manage, label: "Local records"); manage.click()
        let clear = app.buttons["clearHistory"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        try FileManager.default.createDirectory(at: state.appendingPathComponent("cleanup.sqlite"), withIntermediateDirectories: false)
        revealScrollElement(app, control: clear, label: "Clear completed history"); clear.click()
        XCTAssertTrue(app.sheets.buttons["Clear completed history"].waitForExistence(timeout: 5)); app.sheets.buttons["Clear completed history"].click()
        let status = app.staticTexts["historyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let reported = expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Cleared 1 completed Chrome cleanup run."), evaluatedWith: status)
        await fulfillment(of: [reported], timeout: 10)
        let retained = try await service.records()
        XCTAssertTrue(retained.isEmpty)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Web Data")), Data("protected-autofill".utf8))
    }

    @MainActor func testResetIdentifiesChromePreferenceFailureBeforeAppearanceChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        _ = try makeChromeFixture(state)
        app.launchArguments = ["--chrome-cleanup-fixture", "--design-initial-size"]
        app.launch(); app.popUpButtons["Appearance"].click(); app.menuItems["Dark"].click()
        app.typeKey("3", modifierFlags: .command)
        let manage = app.buttons["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); revealScrollElement(app, control: manage, label: "Local records"); manage.click()
        let reset = app.buttons["resetStill"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        try FileManager.default.createDirectory(at: state.appendingPathComponent("chrome-inspection-intent.txt"), withIntermediateDirectories: false)
        revealScrollElement(app, control: reset, label: "Reset Still"); reset.click()
        XCTAssertTrue(app.sheets.buttons["Reset Still"].waitForExistence(timeout: 5)); app.sheets.buttons["Reset Still"].click()
        let status = app.staticTexts["historyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let reported = expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Reset could not clear the Chrome inspection preference."), evaluatedWith: status)
        wait(for: [reported], timeout: 10)
        XCTAssertEqual(app.popUpButtons["Appearance"].value as? String, "Dark")
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.appendingPathComponent("chrome-inspection-intent.txt").path))
    }

    private func makeChromeFixture(_ state: URL) throws -> URL {
        let root = state.appendingPathComponent("ChromeFixture")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Default/Cache/Cache_Data"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(#"{"profile":{"info_cache":{"Default":{}}}}"#.utf8).write(to: root.appendingPathComponent("Local State"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("Default/Preferences"))
        try Data("owned-recreatable-cache".utf8).write(to: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0"))
        try Data("protected-cookie".utf8).write(to: root.appendingPathComponent("Default/Cookies"))
        try Data("protected-autofill".utf8).write(to: root.appendingPathComponent("Default/Web Data"))
        try Data("closed".utf8).write(to: root.appendingPathComponent("environment.txt"))
        return root
    }
}

private struct ChromeHistoryEnvironment: ChromeCacheEnvironment {
    func validateInstallation(at url: URL) throws {}
    func browserIsRunning(bundleURL: URL) throws -> Bool { false }
    func now() -> Date { Date() }
}
