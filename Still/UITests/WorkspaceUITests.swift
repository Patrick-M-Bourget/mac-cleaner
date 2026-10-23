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
        path.typeKey("a", modifierFlags: .command)
        path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        XCTAssertTrue(app.buttons["Inspect camera.txt"].waitForExistence(timeout: 5))
        app.buttons["Inspect camera.txt"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", file.path)).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Logical size: 137 bytes"].exists)
        XCTAssertTrue(app.buttons["Quick Look"].isEnabled)
        XCTAssertTrue(app.buttons["Reveal in Finder"].exists)
        XCTAssertTrue(app.staticTexts["Observed"].exists)
        XCTAssertTrue(app.staticTexts["iCloud in this scan"].exists)
        XCTAssertTrue(app.staticTexts["Pinning: Unknown — not established by this scan"].exists)
        XCTAssertFalse(app.buttons["Remove local download"].exists)
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
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeKey("a", modifierFlags: .command); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Complete scope logical bytes: 1 bytes"].waitForExistence(timeout: 10))
        try FileManager.default.removeItem(at: root)
        app.buttons["Recheck folder"].click()
        XCTAssertTrue(app.staticTexts["Complete scope logical bytes: Unknown"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Identified local downloaded allocation: Unknown · 0 files"].exists)
        XCTAssertTrue(app.staticTexts["No readable entries observed; this is not an empty-folder result."].exists)
        XCTAssertTrue(app.buttons["Choose folder again…"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Last complete observation:")).firstMatch.exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor
    func testLiveSelectionSurvivesSearchNavigationAndWindowClosure() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("selected.pdf"))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        let checkbox = app.checkBoxes["Select selected.pdf"]
        for _ in 0..<5 { if checkbox.exists { break }; app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350) }
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(checkbox.value as? Int, 0)
        app.buttons["Inspect selected.pdf"].click()
        XCTAssertEqual(checkbox.value as? Int, 0)
        checkbox.click()
        let search = app.textFields["Search inspected files"]
        search.click(); search.typeText("does-not-match")
        XCTAssertTrue(app.staticTexts["1 files selected"].exists)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["liveSelectionSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        let bounds = app.windows.firstMatch.frame
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.checkBoxes["Select selected.pdf"].click()
        XCTAssertFalse(app.checkBoxes["Selected selected.pdf"].exists)
        app.checkBoxes["Select selected.pdf"].click()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertFalse(app.checkBoxes["Selected selected.pdf"].exists)
    }

}
