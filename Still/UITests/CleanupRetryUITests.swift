import XCTest
import Darwin

final class CleanupRetryUITests: XCTestCase {
    @MainActor func testCancelledBatchRequiresFreshRetryApproval() throws { try exercise(minimum: false) }
    @MainActor func testCancelledBatchRetryAtMinimumWindow() throws { try exercise(minimum: true) }
    @MainActor private func exercise(minimum: Bool) throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.pdf", "b.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
        let stateID = UUID().uuidString
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("StillTestState-" + stateID).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let marker = state.appendingPathComponent(".still-owned-test-state")
        try Data(stateID.utf8).write(to: marker)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        var info = stat(); XCTAssertEqual(lstat(state.path, &info), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-trash", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
        app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(info.st_dev):\(info.st_ino)"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launch()
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.popUpButtons.firstMatch.click(); app.menuItems[minimum ? "Dark" : "Light"].click()
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10)); app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertTrue(app.checkBoxes["Selected b.pdf"].waitForExistence(timeout: 10))
        app.buttons["Review cleanup"].click()
        let confirmation = app.sheets.containing(.staticText, identifier: "Review Move to Trash").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.buttons["Move to Trash"].click()
        let stop = app.buttons["Stop after current file"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.click()
        XCTAssertTrue(app.buttons["Stop requested"].waitForExistence(timeout: 2))
        capture("stopping-" + (minimum ? "minimum-Dark" : "initial-Light"))
        XCTAssertTrue(app.staticTexts["Cleanup results"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Succeeded: 1"].exists)
        XCTAssertTrue(app.staticTexts["Cancelled: 1"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        try Data([9]).write(to: root.appendingPathComponent("new.pdf"))
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("partial-" + (minimum ? "minimum-" : "initial-") + theme)
        }
        app.buttons["Recheck unfinished files"].click()
        XCTAssertTrue(app.checkBoxes["Selected b.pdf"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.checkBoxes["Selected a.pdf"].exists)
        XCTAssertFalse(app.buttons["Inspect new.pdf"].exists)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("retry-plan-" + (minimum ? "minimum-" : "initial-") + theme)
        }
        app.popUpButtons.firstMatch.click(); app.menuItems[minimum ? "Dark" : "Light"].click()
        app.buttons["Review cleanup"].click()
        let retry = app.sheets.containing(.staticText, identifier: "Review Move to Trash").firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        let disclosure = retry.disclosureTriangles.firstMatch
        XCTAssertTrue(retry.scrollViews.firstMatch.frame.contains(disclosure.frame))
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertEqual(disclosure.value as? Int, 1)
        XCTAssertTrue(retry.descendants(matching: .any).matching(NSPredicate(format: "value == %@ OR label == %@", "b.pdf", "b.pdf")).firstMatch.waitForExistence(timeout: 5), retry.debugDescription)
        XCTAssertFalse(retry.descendants(matching: .any).matching(NSPredicate(format: "value == %@ OR label == %@", "new.pdf", "new.pdf")).firstMatch.exists)
        capture("retry-confirmation-" + (minimum ? "minimum-Dark" : "initial-Light"))
        XCTAssertTrue(retry.buttons["Cancel"].isHittable)
        retry.buttons["Cancel"].click()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("b.pdf")), Data([1]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("new.pdf")), Data([9]))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }
}
