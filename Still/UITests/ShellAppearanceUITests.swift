import XCTest
import Darwin

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
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum"]
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
}
