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

    @MainActor func testFutureHomebrewPreviewIsSecondaryAndClearlySynthetic() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Review Homebrew opportunities"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Review Homebrew opportunities"].click()
        XCTAssertTrue(app.buttons["Choose Homebrew executable…"].exists)
        XCTAssertFalse(app.buttons["Inspect selected Homebrew"].isEnabled)
        app.buttons["Show disposable preview example"].click()
        XCTAssertTrue(app.staticTexts["Synthetic preview evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["/disposable/cache/archive (12.3MB)"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Back to Overview"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
    }

    @MainActor func testFuturePipInventoryShowsRecordedQualificationWithoutRunningPersonalTools() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Review pip cache opportunities"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Review pip cache opportunities"].click()
        XCTAssertTrue(app.buttons["Choose Python interpreter…"].exists)
        XCTAssertFalse(app.buttons["Inspect selected pip cache"].isEnabled)
        app.buttons["Show recorded disposable qualification"].click()
        XCTAssertTrue(app.staticTexts["Recorded disposable evidence"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Back to Overview"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
    }

    @MainActor func testFutureDockerReportKeepsHostCapacityAndPersistentDataDistinct() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Review Docker storage"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Review Docker storage"].click()
        XCTAssertTrue(app.staticTexts["VM virtual capacity: Unknown"].exists)
        XCTAssertTrue(app.staticTexts["Host allocated bytes: Unknown"].exists)
        XCTAssertFalse(app.buttons["Inspect selected Docker"].isEnabled)
        app.buttons["Show synthetic Docker report"].click()
        XCTAssertTrue(app.staticTexts["Synthetic daemon report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Local Volumes · Persistent application data"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Back to Overview"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
    }
}
