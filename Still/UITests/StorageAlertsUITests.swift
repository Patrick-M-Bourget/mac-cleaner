import XCTest
final class StorageAlertsUITests: XCTestCase {
    @MainActor func testAlertsAreHiddenByDefaultAndFutureSettingsDoNotRequestPermission() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
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
        for size in ["--design-initial-size", "--design-minimum"] {
            let app = XCUIApplication()
            app.launchArguments = ["--future-milestones", size]
            app.launch()
            XCTAssertTrue(app.buttons["Review Docker storage"].waitForExistence(timeout: 10))
            let bounds = app.windows.firstMatch.frame
            app.buttons["Review Docker storage"].click()
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                XCTAssertTrue(app.textFields["Local Unix socket path"].exists)
                XCTAssertFalse(app.buttons["Inspect selected Docker"].isEnabled)
                let empty = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                empty.name = "docker-explicit-endpoint-" + size + "-" + theme
                empty.lifetime = .keepAlways; add(empty)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
                XCTAssertTrue(app.staticTexts["VM virtual capacity: Unknown"].exists)
                XCTAssertTrue(app.staticTexts["Host allocated bytes: Unknown"].exists)
                let example = app.buttons["Show synthetic Docker report"]
                XCTAssertTrue(example.waitForExistence(timeout: 5)); example.click()
                XCTAssertTrue(app.staticTexts["Synthetic daemon report"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Local Volumes · Persistent application data"].exists)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
                let report = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                report.name = "docker-persistent-data-" + size + "-" + theme
                report.lifetime = .keepAlways; add(report)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 1400)
            }
            app.buttons["Back to Overview"].click()
            XCTAssertTrue(app.buttons["Choose folder…"].exists)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.terminate()
        }
    }
}
