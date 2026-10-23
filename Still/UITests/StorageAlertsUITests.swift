import XCTest
final class StorageAlertsUITests: XCTestCase {
    @MainActor func testAlertsAreHiddenByDefaultAndFutureSettingsDoNotRequestPermission() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Storage alerts"].exists)
        app.terminate()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Storage alerts"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Storage alerts"].click()
        XCTAssertTrue(app.staticTexts["Alerts are off."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Minimum available space (GB)"].value as? String, "40")
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Review Downloads"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor func testOnDemandWindowCloseTerminatesAndLoginControlsAreReadOnlyUntilChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Storage alerts"].waitForExistence(timeout: 10))
        app.buttons["Storage alerts"].click()
        XCTAssertTrue(app.checkBoxes["Start Still at Login"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["loginRegistrationStatus"].exists)
        XCTAssertTrue(app.staticTexts["Alerts are off."].exists)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }
}
