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
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(info.st_dev):\(info.st_ino)", "STILL_EXCLUSIONS_DIAGNOSTICS": "1"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        app.typeKey("4", modifierFlags: .command)
        app.buttons["manageExclusions"].click()
        XCTAssertTrue(app.staticTexts["No custom exclusions"].waitForExistence(timeout: 3))
        app.buttons["chooseExclusion"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 3)); path.typeKey("a", modifierFlags: .command); path.typeText(hidden.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Preview exclusion"].click()
        XCTAssertTrue(app.staticTexts["Preview exclusion"].waitForExistence(timeout: 3))
        let save = app.buttons["Save exclusion"]
        if !save.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300) }
        let probe = app.staticTexts["exclusionModalProbe"]
        let state = "[DEBUG-exclusions-modal-31] appEnabled=\(app.isEnabled) windowEnabled=\(app.windows.firstMatch.isEnabled) saveEnabled=\(save.isEnabled) saveHittable=\(save.isHittable) saveFrame=\(save.frame) windowFrame=\(app.windows.firstMatch.frame) dialogs=\(app.dialogs.count) model=\(probe.exists ? (probe.value as? String ?? probe.label) : "missing")"
        let stateAttachment = XCTAttachment(string: state + "\n" + app.debugDescription); stateAttachment.name = "DEBUG-exclusions-modal-31-state"; stateAttachment.lifetime = .keepAlways; add(stateAttachment)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); screenshot.name = "DEBUG-exclusions-modal-31-preview"; screenshot.lifetime = .keepAlways; add(screenshot)
        print(state)
        XCTAssertTrue(save.isHittable); save.click()
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
            XCTAssertTrue(app.buttons["Back to Locations & access"].isHittable)
        }
        let remove = app.buttons["Remove exclusion for " + hidden.resolvingSymlinksInPath().path]
        if !remove.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300) }
        XCTAssertTrue(remove.isHittable); remove.click()
        XCTAssertTrue(app.staticTexts["No custom exclusions"].waitForExistence(timeout: 5))
        app.terminate()
        let remainingRules = try await store.policy().rules
        XCTAssertTrue(remainingRules.isEmpty)
        XCTAssertEqual(try Data(contentsOf: hidden), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: kept), Data([3]))
    }
}
