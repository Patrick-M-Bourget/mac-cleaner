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
        XCTAssertTrue(app.checkBoxes["Chrome Default downloaded asset cache"].waitForExistence(timeout: 10))
        let group = app.checkBoxes["Chrome Default downloaded asset cache"]
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
