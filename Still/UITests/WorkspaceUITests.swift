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

    @MainActor
    func testChooseDisposableFolderAndInspectWithoutMutation() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillUI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("camera.txt")
        try Data(repeating: 65, count: 137).write(to: file)
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.buttons["Inspect camera.txt"].waitForExistence(timeout: 10))
        app.buttons["Inspect camera.txt"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", file.path)).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Logical size: 137 bytes"].exists)
        XCTAssertTrue(app.buttons["Quick Look"].exists)
        XCTAssertTrue(app.buttons["Reveal in Finder"].exists)
        XCTAssertTrue(app.staticTexts["Observed"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: file), Data(repeating: 65, count: 137))
    }

    @MainActor
    func testUnavailableSelectedFolderShowsUnknownCoverageAndRecovery() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillCoverageUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("temporary.txt"))
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.buttons["Inspect temporary.txt"].waitForExistence(timeout: 10))
        try FileManager.default.removeItem(at: root)
        app.buttons["Recheck folder"].click()
        XCTAssertTrue(app.staticTexts["Complete scope logical bytes: Unknown"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No readable entries observed; this is not an empty-folder result."].exists)
        XCTAssertTrue(app.buttons["Choose folder again…"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Last complete observation:")).firstMatch.exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

}
