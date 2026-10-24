import XCTest

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
        let coverage = app.staticTexts["overviewScopeCoverage"]
        let coverageValue = coverage.value as? String
        XCTAssertTrue(app.buttons["Scan again"].exists)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(refresh.frame))
        refresh.click()
        XCTAssertTrue(app.staticTexts["Storage overview"].exists)
        XCTAssertEqual(coverage.value as? String, coverageValue)
        XCTAssertFalse(app.buttons["Stop scan"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, window)
        app.buttons["Cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["Selected for Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing selected"].exists)
        app.buttons["Overview"].click()
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, window)
    }
}
