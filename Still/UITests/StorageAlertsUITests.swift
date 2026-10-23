import XCTest
import Darwin
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

    @MainActor func testSelectedPipCacheInventoryIsReadOnlyAcrossThemesAndSizes() throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("StillPipUI-" + UUID().uuidString)
        let wheel = root.appendingPathComponent("wheels/a/package-1.0-py3-none-any.whl")
        try manager.createDirectory(at: wheel.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let seed = Data("disposable-inventory-sentinel".utf8)
        try seed.write(to: wheel)
        for minimum in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--future-milestones", "--pip-inventory-fixture", minimum ? "--design-minimum" : "--design-initial-size"]
            var information = stat()
            XCTAssertEqual(lstat(root.path, &information), 0)
            app.launchEnvironment["STILL_TEST_PIP_CACHE"] = root.path
            app.launchEnvironment["STILL_TEST_PIP_CACHE_ID"] = "\(information.st_dev):\(information.st_ino)"
            app.launch()
            XCTAssertTrue(app.buttons["Review pip cache opportunities"].waitForExistence(timeout: 10))
            let bounds = app.windows.firstMatch.frame
            app.buttons["Review pip cache opportunities"].click()
            XCTAssertTrue(app.buttons["Inspect selected pip cache"].isEnabled,
                          "Fixture preload failed; canonical root: \(root.resolvingSymlinksInPath().path); UI: \(app.debugDescription)")
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let selection = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                selection.name = "pip-selected-" + (minimum ? "minimum-" : "initial-") + theme
                selection.lifetime = .keepAlways; add(selection)
            }
            app.buttons["Inspect selected pip cache"].click()
            let status = app.staticTexts["pipInventoryStatus"]
            let completed = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Read-only inventory complete", "Read-only inventory complete")
            expectation(for: completed, evaluatedWith: status)
            waitForExpectations(timeout: 45)
            for _ in 0..<4 {
                let evidence = app.staticTexts["Listed wheels: 1"]
                if evidence.exists && app.scrollViews.firstMatch.frame.contains(evidence.frame) { break }
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -180)
            }
            XCTAssertTrue(app.staticTexts["Listed wheels: 1"].exists)
            XCTAssertTrue(app.staticTexts["Wheel logical bytes: 29"].exists)
            XCTAssertFalse(app.buttons["Clean pip cache"].exists)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let inventory = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                inventory.name = "pip-inventory-" + (minimum ? "minimum-" : "initial-") + theme
                inventory.lifetime = .keepAlways; add(inventory)
            }
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(try Data(contentsOf: wheel), seed)
            XCTAssertEqual(try manager.contentsOfDirectory(atPath: root.path), ["wheels"])
            app.terminate()
        }
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
                let endpoint = app.textFields["Local Unix socket path"]
                endpoint.click(); endpoint.typeKey("a", modifierFlags: .command)
                endpoint.typeText("/disposable/" + theme + "/daemon.sock")
                XCTAssertTrue(app.staticTexts["Socket changed. Inspect explicitly to read this endpoint. No command was run."].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["Synthetic daemon report"].exists)
                XCTAssertFalse(app.staticTexts["Local Volumes · Persistent application data"].exists)
                XCTAssertTrue(app.staticTexts["Host allocated bytes: Unknown"].exists)
                XCTAssertTrue(app.staticTexts["VM virtual capacity: Unknown"].exists)
                XCTAssertFalse(app.buttons["Inspect selected Docker"].isEnabled)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
            app.buttons["Back to Overview"].click()
            XCTAssertTrue(app.buttons["Choose folder…"].exists)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.terminate()
        }
    }
}
