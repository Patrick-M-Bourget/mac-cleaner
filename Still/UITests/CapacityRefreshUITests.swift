import XCTest
import Darwin

final class CapacityRefreshUITests: XCTestCase {
    @MainActor func testCapacityRefreshIsSeparateFromScanAndKeepsOverviewContext() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = ["--design-minimum"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let refresh = app.buttons["Refresh capacity"]
        guard refresh.waitForExistence(timeout: 10) else {
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "capacity-refresh-missing-action"; capture.lifetime = .keepAlways; add(capture)
            XCTFail("Overview needs a capacity-only refresh action separate from Scan again")
            return
        }
        let window = app.windows.firstMatch.frame
        let coverage = app.staticTexts["No included locations with current observations."]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        let coverageValue = coverage.value as? String ?? coverage.label
        XCTAssertTrue(app.buttons["Scan again"].exists)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(refresh.frame))
        refresh.click()
        XCTAssertTrue(app.staticTexts["Storage overview"].exists)
        XCTAssertTrue(coverage.exists)
        XCTAssertEqual(coverage.value as? String ?? coverage.label, coverageValue)
        XCTAssertFalse(app.buttons["Stop scan"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, window)
        app.buttons["Cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["Selected for Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "0 files selected", "0 files selected")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        app.buttons["Overview"].click()
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, window)
    }

    @MainActor func testCompletedScanRefreshesCapacityWithoutChangingChoices() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Review-me.pdf")
        let original = Data([1, 2, 3, 4]); try original.write(to: file)
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        func sample(_ available: Int64) throws {
            let data = try JSONSerialization.data(withJSONObject: ["available": available, "total": 512_000_000_000, "metric": "important"])
            try data.write(to: state.appendingPathComponent("capacity-reading.json"), options: .atomic)
        }
        try sample(40_000_000_000)
        var info = stat(); XCTAssertEqual(lstat(root.path, &info), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-capacity-reading", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(info.st_dev):\(info.st_ino)"
        app.launch()
        let amount = app.staticTexts["startupCapacityAmount"]
        func observes(_ expected: String) -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", expected, expected), object: amount)], timeout: 5) == .completed
        }
        guard observes("40 GB") else { XCTFail("Owned launch capacity must be visible"); return }
        try sample(50_000_000_000)
        app.buttons["Refresh capacity"].click()
        guard observes("50 GB") else { XCTFail("Manual capacity refresh must read independently"); return }
        try sample(60_000_000_000)
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app)
        guard observes("60 GB") else {
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = "capacity-after-scan"; screenshot.lifetime = .keepAlways; add(screenshot)
            XCTFail("Completing a logical scan must refresh startup capacity"); return
        }
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: .command)
        try sample(70_000_000_000); app.buttons["Refresh capacity"].click()
        XCTAssertTrue(observes("70 GB"))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor func testCapacityStatesStayStableAtMinimumSize() throws { try capacityStates(minimum: true) }
    @MainActor func testCapacityStatesStayStableAtInitialSize() throws { try capacityStates(minimum: false) }

    @MainActor private func capacityStates(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        func sample(available: Int64?, total: Int64?, metric: String = "important", delay: Int = 0) throws {
            var values: [String: Any] = ["metric": metric, "delayMilliseconds": delay]
            if let available { values["available"] = available }
            if let total { values["total"] = total }
            try JSONSerialization.data(withJSONObject: values).write(to: state.appendingPathComponent("capacity-reading.json"), options: .atomic)
        }
        try sample(available: 40_000_000_000, total: 512_000_000_000)
        app.launchArguments = ["--ui-test-capacity-reading", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        let amount = app.staticTexts["startupCapacityAmount"]
        guard amount.waitForExistence(timeout: 10) else { XCTFail("Launch capacity missing"); return }
        let bounds = app.windows.firstMatch.frame
        let observation = app.staticTexts["capacityObservation"]
        let anchor = observation.frame
        func capture(_ name: String) {
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                image.name = "capacity-" + name + (minimum ? "-minimum-" : "-initial-") + theme
                image.lifetime = .keepAlways; add(image)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                XCTAssertEqual(observation.frame, anchor)
                XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["refreshCapacity"].frame))
            }
        }
        capture("observed-important")
        try sample(available: 40_000_000_000, total: nil, metric: "available")
        app.buttons["Refresh capacity"].click()
        let partial = app.staticTexts["Total capacity unavailable"]
        guard partial.waitForExistence(timeout: 5) else { XCTFail("Partial metadata must retain available space"); return }
        XCTAssertTrue(app.staticTexts["sidebarCapacityObservation"].waitForExistence(timeout: 5))
        let sidebar = app.staticTexts["sidebarCapacityAmount"]
        guard sidebar.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "capacity-partial-sidebar-missing"; image.lifetime = .keepAlways; add(image)
            XCTFail("Sidebar must show valid available space without a total"); return
        }
        XCTAssertTrue((sidebar.value as? String ?? sidebar.label).contains("40 GB"))
        capture("partial-fallback")
        try sample(available: nil, total: nil)
        app.buttons["Refresh capacity"].click()
        guard app.buttons["Try again"].waitForExistence(timeout: 5) else { XCTFail("Failure needs retry"); return }
        XCTAssertTrue((observation.value as? String ?? observation.label).hasPrefix("Last observed "))
        XCTAssertEqual(amount.value as? String ?? amount.label, "40 GB")
        capture("stale-failure")
        try sample(available: 60_000_000_000, total: 512_000_000_000)
        app.buttons["Try again"].click()
        XCTAssertTrue(app.buttons["Refresh capacity"].waitForExistence(timeout: 5))
        capture("recovered")
    }
}
