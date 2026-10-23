import XCTest
import Darwin
import StillCore

final class ExclusionsUITests: XCTestCase {
    @MainActor func testExplicitExclusionPreviewSaveReopenScanAndRemove() async throws { try await journey(minimum: false) }
    @MainActor func testMinimumExclusionsKeepExplicitActionsReachable() async throws { try await journey(minimum: true) }
    @MainActor private func journey(minimum: Bool) async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try String(root.lastPathComponent.dropFirst("StillTestState-".count)).write(to: root.appendingPathComponent(".still-owned-test-state"), atomically: false, encoding: .utf8)
        let scope = root.appendingPathComponent("Scope")
        try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: false)
        let hidden = scope.appendingPathComponent("excluded.txt"), kept = scope.appendingPathComponent("included.txt")
        try Data([1, 2]).write(to: hidden); try Data([3]).write(to: kept)
        var info = stat(); XCTAssertEqual(lstat(root.path, &info), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(info.st_dev):\(info.st_ino)"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        // Exercise repeated explicit-capture launches through normal public readiness.
        for _ in 0..<2 {
            app.terminate(); app.launch()
            XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        app.typeKey("4", modifierFlags: .command)
        app.buttons["manageExclusions"].click()
        XCTAssertTrue(app.staticTexts["No custom exclusions"].waitForExistence(timeout: 3))
        captureThemes(app, state: "empty", minimum: minimum, bounds: bounds)
        XCTAssertTrue(app.buttons["chooseExclusion"].isEnabled && app.buttons["chooseExclusion"].isHittable)
        app.buttons["chooseExclusion"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 3)); path.typeKey("a", modifierFlags: .command); path.typeText(scope.path)
        app.typeKey(.return, modifierFlags: [])
        // Go to Folder leaves the parent selected in column view. Enter its file column
        // and use native type selection instead of clicking an offscreen column label.
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeText(hidden.lastPathComponent)
        app.dialogs.buttons["Preview exclusion"].click()
        XCTAssertTrue(app.staticTexts["Preview exclusion"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", hidden.path)).firstMatch.waitForExistence(timeout: 5))
        let save = app.buttons["Save exclusion"]
        if !save.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300) }
        captureThemes(app, state: "preview", minimum: minimum, bounds: bounds)
        XCTAssertTrue(save.isEnabled && save.isHittable); save.click()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        app.terminate()
        let store = ExclusionStore(directory: root.appendingPathComponent("Exclusions"))
        let savedRules = try await store.policy().rules
        XCTAssertEqual(savedRules.count, 1)
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let folderPath = app.textFields.firstMatch
        XCTAssertTrue(folderPath.waitForExistence(timeout: 3)); folderPath.typeKey("a", modifierFlags: .command); folderPath.typeText(scope.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250)
        XCTAssertTrue(app.buttons["Inspect included.txt"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Inspect excluded.txt"].exists)
        app.typeKey("4", modifierFlags: .command); app.buttons["manageExclusions"].click()
        for appearance in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[appearance].click()
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertTrue(app.buttons["Back to Locations & access"].isEnabled && app.buttons["Back to Locations & access"].isHittable)
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "exclusions-saved-" + (minimum ? "minimum-" : "initial-") + appearance
            capture.lifetime = .keepAlways; add(capture)
        }
        let remove = app.buttons.matching(NSPredicate(format: "label == %@", "Remove exclusion for " + hidden.resolvingSymlinksInPath().path)).firstMatch
        if !remove.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300) }
        XCTAssertTrue(remove.isHittable); remove.click()
        XCTAssertTrue(app.staticTexts["No custom exclusions"].waitForExistence(timeout: 5))
        app.terminate()
        let remainingRules = try await store.policy().rules
        XCTAssertTrue(remainingRules.isEmpty)
        XCTAssertEqual(try Data(contentsOf: hidden), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: kept), Data([3]))
    }
    @MainActor private func captureThemes(_ app: XCUIApplication, state: String, minimum: Bool, bounds: CGRect) {
        for appearance in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[appearance].click()
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "exclusions-" + state + "-" + (minimum ? "minimum-" : "initial-") + appearance
            capture.lifetime = .keepAlways; add(capture)
        }
    }

}
