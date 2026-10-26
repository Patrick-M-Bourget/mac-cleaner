import XCTest

/// User-visible browser-cache journeys with real files under the app's guarded disposable state.
final class ChromeCleanupUITests: XCTestCase {
    @MainActor func testChromeSelectionCancelAndPermanentCleanupPreservePersonalData() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        let root = try makeChromeFixture(state)
        app.launchArguments = ["--chrome-cleanup-fixture", "--design-initial-size"]
        app.launch()
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
            capture.name = "chrome-review-initial-" + theme; capture.lifetime = .keepAlways; add(capture)
        }
        group.click()
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.buttons["Review cleanup"].waitForExistence(timeout: 5))
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.sheets.buttons["Run cleanup"].waitForExistence(timeout: 5))
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0").path))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.sheets.buttons["Run cleanup"].waitForExistence(timeout: 5), "Cancel returns focus to Review cleanup")
        app.sheets.buttons["Run cleanup"].click()
        XCTAssertTrue(app.staticTexts["Chrome cache results"].waitForExistence(timeout: 15))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Cookies")), Data("protected-cookie".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Default/Web Data")), Data("protected-autofill".utf8))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Running")).firstMatch.waitForExistence(timeout: 10))
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
            let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", expected)).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
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
