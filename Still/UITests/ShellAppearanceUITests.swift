import XCTest
import Darwin
import StillCore

final class ShellAppearanceUITests: XCTestCase {
    @MainActor func testSelectedCategoryBadgeAndDestinationContextPreserveChoices() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let manager = FileManager.default
        let downloads = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: downloads, withIntermediateDirectories: false)
        let first = downloads.appendingPathComponent("First.pdf")
        let second = downloads.appendingPathComponent("Second.pdf")
        let bytes = Data([1, 7, 9])
        try bytes.write(to: first); try bytes.write(to: second)
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: downloads) }
        var identity = stat(); XCTAssertEqual(lstat(downloads.path, &identity), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = downloads.path
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
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
        XCTAssertTrue(app.staticTexts["2 files selected"].waitForExistence(timeout: 5))
        let selectedPlan = app.buttons["Cleanup plan, 1 category selected"]
        guard selectedPlan.waitForExistence(timeout: 5) else {
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "shell-missing-actionable-category-badge"; capture.lifetime = .keepAlways; add(capture)
            XCTFail("Two selected Downloads files must produce one accessible category badge")
            return
        }
        XCTAssertTrue(app.staticTexts["Choose files, then review"].exists)
        XCTAssertFalse(app.staticTexts["Read-only metadata · explicitly selected folder"].exists)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Recorded cleanup activity"].waitForExistence(timeout: 5))
            XCTAssertTrue(selectedPlan.exists)
            selectedPlan.click()
            XCTAssertTrue(app.staticTexts["2 files selected"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "shell-selected-category-minimum-" + theme; capture.lifetime = .keepAlways; add(capture)
        }
        var temporaryEntries: [URL] = []
        for index in 0..<300 {
            let url = downloads.appendingPathComponent("slow-metadata-" + String(index) + ".txt")
            try Data([1]).write(to: url); temporaryEntries.append(url)
        }
        app.typeKey("1", modifierFlags: .command)
        app.buttons["Scan again"].click()
        let stop = app.buttons["Stop scan"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertFalse(selectedPlan.exists, "A suspended selection must not advertise an actionable category")
        app.popUpButtons["Appearance"].click(); app.menuItems["Light"].click()
        XCTAssertTrue(stop.exists, "Appearance must not interrupt the active scan")
        stop.click()
        XCTAssertFalse(selectedPlan.exists)
        for url in temporaryEntries { try manager.removeItem(at: url) }
        app.buttons["Scan again"].click(); waitForScanIdle(app, timeout: 30)
        XCTAssertTrue(selectedPlan.waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["2 files selected"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate(); app.menuBars.menuBarItems["Window"].click(); app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(selectedPlan.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 files selected"].exists)
        XCTAssertEqual(app.popUpButtons["Appearance"].value as? String, "Light")
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        category.click()
        XCTAssertTrue(app.staticTexts["0 files selected"].waitForExistence(timeout: 5))
        XCTAssertFalse(selectedPlan.exists)
        XCTAssertTrue(app.buttons["Cleanup plan"].exists)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(try Data(contentsOf: second), bytes)
    }

    @MainActor func testAppearanceSurvivesRelaunchWithoutRestoringPlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = ["--design-minimum"]
        app.launch()
        let picker = app.popUpButtons["Appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.value as? String, "Automatic")
        let bounds = app.windows.firstMatch.frame
        picker.click(); app.menuItems["Dark"].click()
        XCTAssertEqual(picker.value as? String, "Dark")
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.terminate(); app.launch()
        guard picker.waitForExistence(timeout: 10), picker.value as? String == "Dark" else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "shell-appearance-not-restored"; image.lifetime = .keepAlways; add(image)
            XCTFail("The app-wide Dark preference must survive Quit and relaunch independently of cleanup choices"); return
        }
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["0 files selected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        picker.click(); app.menuItems["Automatic"].click()
        XCTAssertEqual(picker.value as? String, "Automatic")
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.terminate(); app.launch()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.value as? String, "Automatic")
    }

    @MainActor func testAttentionFooterOpensDetailsWithoutChangingChoicesOrSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        let manager = FileManager.default
        let downloads = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: downloads, withIntermediateDirectories: false)
        let file = downloads.appendingPathComponent("Choice.pdf"); try Data([4, 9]).write(to: file)
        let folder = state.appendingPathComponent("StorageAlerts")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        let badState = folder.appendingPathComponent("episode-state.json")
        let original = Data("owned invalid alert state".utf8); try original.write(to: badState)
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: downloads) }
        var identity = stat(); XCTAssertEqual(lstat(downloads.path, &identity), 0)
        app.launchArguments = ["--future-milestones", "--ui-test-alert-service", "--ui-test-downloads-root", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = downloads.path
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(identity.st_dev):\(identity.st_ino)"
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5)); app.textFields.firstMatch.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app); app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        let footer = app.buttons["Alerts need attention"]
        guard footer.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "shell-attention-footer-missing"; image.lifetime = .keepAlways; add(image)
            XCTFail("A known unreadable alert state must offer direct access to its details"); return
        }
        let bounds = app.windows.firstMatch.frame
        footer.click()
        XCTAssertTrue(app.staticTexts["Capacity checks only"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved alert state couldn’t be read. Monitoring is stopped to preserve suppression."].exists)
        XCTAssertTrue(app.staticTexts["Capacity polling is stopped."].exists)
        XCTAssertEqual(try Data(contentsOf: badState), original)
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "shell-attention-details-minimum-" + theme; image.lifetime = .keepAlways; add(image)
        }
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cleanup plan, 1 category selected"].exists)
        XCTAssertEqual(try Data(contentsOf: file), Data([4, 9]))
        XCTAssertEqual(try Data(contentsOf: badState), original)
    }

    @MainActor func testAppearanceSaveFailureAndRetryAtMinimumSize() throws { try saveFailure(minimum: true) }
    @MainActor func testAppearanceSaveFailureAndRetryAtInitialSize() throws { try saveFailure(minimum: false) }
    @MainActor private func saveFailure(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        let picker = app.popUpButtons["Appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        let anchor = app.staticTexts["Storage overview"].frame
        picker.click(); app.menuItems["Dark"].click()
        let file = state.appendingPathComponent("appearance-preference.txt")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        for theme in ["Light", "Dark"] {
            picker.click(); app.menuItems[theme].click()
            XCTAssertEqual(picker.value as? String, theme)
            XCTAssertTrue(app.buttons["Retry saving"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Retry saving"].isHittable)
            XCTAssertEqual(app.staticTexts["Storage overview"].frame, anchor)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            shellCapture(app, "save-failed-" + theme, minimum: minimum)
        }
        try FileManager.default.removeItem(at: file)
        app.buttons["Retry saving"].click()
        XCTAssertFalse(app.buttons["Retry saving"].exists)
        XCTAssertEqual(picker.value as? String, "Dark")
        XCTAssertEqual(app.staticTexts["Storage overview"].frame, anchor)
        app.buttons["Choose folder…"].click()
        XCTAssertTrue(app.dialogs.buttons["Scan folder"].waitForExistence(timeout: 5))
        let panel = XCTAttachment(screenshot: app.screenshot())
        panel.name = "shell-shared-Dark-native-dialog-" + (minimum ? "minimum" : "initial")
        panel.lifetime = .keepAlways; add(panel)
        app.typeKey(.escape, modifierFlags: [])
        app.terminate(); app.launch()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.value as? String, "Dark")
        shellCapture(app, "retry-saved-relaunched-Dark", minimum: minimum)
    }

    @MainActor func testAppearanceReadFallbackNeverRepairsAtMinimumSize() throws { try readFallback(minimum: true) }
    @MainActor func testAppearanceReadFallbackNeverRepairsAtInitialSize() throws { try readFallback(minimum: false) }
    @MainActor private func readFallback(minimum: Bool) throws {
        continueAfterFailure = false
        for unreadable in [false, true] {
            let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
            let file = state.appendingPathComponent("appearance-preference.txt")
            if unreadable { try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false) }
            else { try Data("owned invalid appearance".utf8).write(to: file) }
            app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
            app.launch()
            let picker = app.popUpButtons["Appearance"]
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            XCTAssertEqual(picker.value as? String, "Automatic")
            let message = unreadable ? "Couldn’t read saved appearance. Using Automatic." : "Saved appearance isn’t recognized. Using Automatic."
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Retry saving"].exists)
            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts[message].exists)
            if unreadable {
                var info = stat(); XCTAssertEqual(lstat(file.path, &info), 0); XCTAssertEqual(info.st_mode & S_IFMT, S_IFDIR)
            } else { XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "owned invalid appearance") }
            shellCapture(app, unreadable ? "unreadable-Automatic" : "invalid-Automatic", minimum: minimum)
        }
    }

    @MainActor func testAppearanceResetStagesAndClearAtMinimumSize() throws { try resetStages(minimum: true) }
    @MainActor func testAppearanceResetStagesAndClearAtInitialSize() throws { try resetStages(minimum: false) }
    @MainActor private func resetStages(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        let picker = app.popUpButtons["Appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.click(); app.menuItems["Dark"].click()
        app.typeKey("3", modifierFlags: .command)
        let manage = app.buttons["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); manage.click()
        let clear = app.buttons["clearHistory"]
        revealScrollElement(app, control: clear, label: "Clear completed runs")
        clear.click(); XCTAssertTrue(app.sheets.buttons["Clear completed runs"].waitForExistence(timeout: 5)); app.sheets.buttons["Clear completed runs"].click()
        let status = app.staticTexts["historyStatus"]
        func waitStatus(_ prefix: String) -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", prefix, prefix), object: status)], timeout: 10) == .completed
        }
        XCTAssertTrue(waitStatus("Cleared "))
        XCTAssertEqual(picker.value as? String, "Dark")
        let file = state.appendingPathComponent("appearance-preference.txt")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Dark")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        func reset() {
            let button = app.buttons["resetStill"]
            revealScrollElement(app, control: button, label: "Reset Still")
            button.click(); XCTAssertTrue(app.sheets.buttons["Reset Still"].waitForExistence(timeout: 5)); app.sheets.buttons["Reset Still"].click()
        }
        reset()
        guard waitStatus("Reset could not clear the appearance preference.") else { XCTFail("Appearance clear failure must be reported truthfully"); return }
        XCTAssertEqual(picker.value as? String, "Dark")
        shellCapture(app, "reset-appearance-clear-failed-Dark", minimum: minimum)
        try FileManager.default.removeItem(at: file)
        try Data("Dark".utf8).write(to: file)
        let alertFolder = state.appendingPathComponent("StorageAlerts")
        try FileManager.default.createDirectory(at: alertFolder, withIntermediateDirectories: true)
        let alertRecord = alertFolder.appendingPathComponent("episode-state.json")
        try FileManager.default.createDirectory(at: alertRecord, withIntermediateDirectories: false)
        reset()
        guard waitStatus("Reset could not finish safely. Appearance was reset to Automatic,") else { XCTFail("Later Reset failure must preserve the independently cleared appearance and report partial completion"); return }
        XCTAssertEqual(picker.value as? String, "Automatic")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        shellCapture(app, "reset-later-service-failed-Automatic", minimum: minimum)
        try FileManager.default.removeItem(at: alertRecord)
        reset()
        XCTAssertTrue(waitStatus("Still’s preferences,"))
        XCTAssertEqual(picker.value as? String, "Automatic")
        shellCapture(app, "reset-complete-Automatic", minimum: minimum)
    }

    @MainActor private func shellCapture(_ app: XCUIApplication, _ name: String, minimum: Bool) {
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = "shell-" + name + (minimum ? "-minimum" : "-initial"); image.lifetime = .keepAlways; add(image)
    }

    @MainActor func testShellGalleryAtInitialSize() throws { try shellGallery(minimum: false) }
    @MainActor func testShellGalleryAtMinimumSize() throws { try shellGallery(minimum: true) }
    @MainActor private func shellGallery(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = ["--design-gallery", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native design system"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.popUpButtons.count, 1)
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, theme)
            for index in 0..<7 {
                let heading = app.staticTexts["Monitoring example " + String(index)]
                revealScrollElement(app, control: heading, label: "Synthetic monitoring state")
                let container = app.descendants(matching: .any)["monitoringGallery-" + String(index)].firstMatch
                XCTAssertTrue(container.exists)
                for _ in 0..<12 where !app.scrollViews.firstMatch.frame.contains(container.frame) {
                    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -60)
                }
                XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(container.frame))
                if index == 0 { XCTAssertEqual(container.buttons.count, 0) }
                else { XCTAssertEqual(container.buttons.count, 1); XCTAssertTrue(container.buttons.firstMatch.isEnabled) }
                shellCapture(app, "gallery-monitoring-" + String(index) + "-" + theme, minimum: minimum)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
            for index in 0..<4 {
                let heading = app.staticTexts["Appearance notice example " + String(index)]
                revealScrollElement(app, control: heading, label: "Synthetic appearance notice")
                let container = app.descendants(matching: .any)["appearanceGallery-" + String(index)].firstMatch
                if index == 3 {
                    revealScrollElement(app, control: container.buttons["Retry saving"], label: "Inert Retry saving")
                    XCTAssertTrue(container.buttons["Retry saving"].isEnabled)
                }
                shellCapture(app, "gallery-appearance-" + String(index) + "-" + theme, minimum: minimum)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
            let badge = app.buttons["Cleanup plan, 1 category selected"].firstMatch
            let pluralBadge = app.buttons["Cleanup plan, 2 categories selected"]
            revealScrollElement(app, control: pluralBadge, label: "Synthetic category badges")
            XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(badge.frame))
            XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(pluralBadge.frame))
            shellCapture(app, "gallery-category-badges-" + theme, minimum: minimum)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
    }
}
