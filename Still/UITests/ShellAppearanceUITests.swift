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
}
