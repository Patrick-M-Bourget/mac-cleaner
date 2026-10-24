import XCTest
import Darwin

final class HistoryActivityUITests: XCTestCase {
    @MainActor func testCompletedScanAppearsInHistoryWithoutRestoringSelection() throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let token = UUID().uuidString
        let state = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
        let downloads = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + token)
        for url in [state, downloads] { try manager.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        try Data(token.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        let file = downloads.appendingPathComponent("Owned-history.pdf")
        let original = Data([1, 5, 9]); try original.write(to: file)
        var stateID = stat(); var rootID = stat()
        XCTAssertEqual(lstat(state.path, &stateID), 0); XCTAssertEqual(lstat(downloads.path, &rootID), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": state.path, "STILL_TEST_STATE_ID": "\(stateID.st_dev):\(stateID.st_ino)", "STILL_TEST_DOWNLOADS_ROOT": downloads.path, "STILL_TEST_DOWNLOADS_ID": "\(rootID.st_dev):\(rootID.st_ino)"]
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: downloads) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(downloads.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app)
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        let completed = app.staticTexts["Completed scan"]
        guard completed.waitForExistence(timeout: 5) else {
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "history-activity-missing-completed-scan"; capture.lifetime = .keepAlways; add(capture)
            XCTFail("An explicit completed scan must produce a retained scan activity record in History")
            return
        }
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(completed.waitForExistence(timeout: 5), "Scan activity survives Quit")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertFalse(app.staticTexts["1 file selected"].exists, "History must not restore cleanup choices")
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
