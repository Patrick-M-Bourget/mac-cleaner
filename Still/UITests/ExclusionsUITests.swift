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
        // Send the path to the focused Go to Folder field; firstMatch can resolve
        // an existing browser filename field before the Go to Folder sheet opens.
        app.typeKey("a", modifierFlags: .command); app.typeText(scope.path)
        app.typeKey(.return, modifierFlags: [])
        let atScope = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.dialogs.popUpButtons["where popup"].value as? String == scope.lastPathComponent
        }, object: nil)
        let destinationResult = await XCTWaiter.fulfillment(of: [atScope], timeout: 5)
        guard destinationResult == .completed else {
            XCTFail("The native picker must reach the owned Scope folder before selecting a file"); return
        }
        app.dialogs.menuButtons["View Options"].click()
        let listView = app.menuItems["cmdViewAsList:"]
        guard listView.waitForExistence(timeout: 5) else { XCTFail("Native List view must be available"); return }
        listView.click()
        let excludedFile = app.dialogs.descendants(matching: .any).matching(NSPredicate(format: "value == %@", hidden.lastPathComponent)).firstMatch
        guard excludedFile.waitForExistence(timeout: 5) else { XCTFail("The exact owned file must be visible in the picker"); return }
        excludedFile.click()
        app.dialogs.buttons["Preview exclusion"].click()
        XCTAssertTrue(app.staticTexts["Preview exclusion"].waitForExistence(timeout: 3))
        guard app.staticTexts.matching(NSPredicate(format: "value == %@", hidden.path)).firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("The preview must name the exact file before Save"); return
        }
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
        waitForOverviewScan(app, timeout: 10)
        openObservedExplorer(app, root: scope)
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
