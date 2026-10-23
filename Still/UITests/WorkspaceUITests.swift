import XCTest

final class WorkspaceUITests: XCTestCase {
    @MainActor
    func testInspectingFixturesPreservesWindowAndNeverSelects() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic data — no personal files accessed"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let bounds = window.frame
        app.buttons["Review Downloads"].click()
        XCTAssertTrue(app.staticTexts["Downloads inspection"].exists)
        app.buttons["Inspect Summer trip.mov"].click()
        XCTAssertTrue(app.staticTexts["Downloads/Trips/Summer trip.mov"].exists)
        XCTAssertTrue(app.staticTexts["Nothing selected"].exists)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["Selected for Trash"].exists)
        XCTAssertTrue(app.staticTexts["Nothing selected"].exists)
        XCTAssertEqual(window.frame.width, bounds.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, bounds.height, accuracy: 1)
        app.buttons["Choose items"].click()
        XCTAssertTrue(app.staticTexts["Summer trip.mov"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(window.frame, bounds)
    }
    @MainActor
    func testKeyboardNavigationAndAppearanceKeepWindowBounds() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Selected for Trash"].waitForExistence(timeout: 3))
        for appearance in ["Dark", "Light"] {
            app.popUpButtons.firstMatch.click()
            app.menuItems[appearance].click()
            XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, appearance)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Review Downloads"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

}
