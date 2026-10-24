import XCTest
import Darwin

@MainActor func revealScrollElement(_ app: XCUIApplication, control: XCUIElement, label: String) {
    XCTAssertTrue(control.waitForExistence(timeout: 10))
    for _ in 0..<12 {
        let viewport = app.scrollViews.firstMatch.frame
        if viewport.contains(control.frame) { return }
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: control.frame.minY < viewport.minY ? 220 : -220)
    }
    XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(control.frame), label)
}
@MainActor func revealOverviewControl(_ app: XCUIApplication, label: String) {
    revealScrollElement(app, control: app.buttons[label], label: label)
}
@MainActor func revealOverviewTool(_ app: XCUIApplication, label: String) {
    revealOverviewControl(app, label: "More tools")
    let more = app.buttons["More tools"]
    if more.value as? String != "Expanded" { more.click() }
    revealOverviewControl(app, label: label)
}

/// Public readiness stays on the scan's originating Overview; browsing is an explicit next action.
@MainActor func waitForScanIdle(_ app: XCUIApplication, timeout: TimeInterval) {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: app.buttons["Scan again"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
}
@MainActor func waitForOverviewScan(_ app: XCUIApplication, timeout: TimeInterval = 15) {
    XCTAssertTrue(app.staticTexts["overviewScopeCoverage"].waitForExistence(timeout: timeout))
    waitForScanIdle(app, timeout: timeout)
    XCTAssertTrue(app.staticTexts["Storage overview"].exists)
}
@MainActor func enterObservedExplorerRoot(_ app: XCUIApplication, root: URL) {
    let open = app.buttons["Open folder " + root.lastPathComponent]
    if !open.exists {
        let roots = app.buttons["Selected locations"].exists ? app.buttons["Selected locations"] : app.buttons["Scanned Downloads locations"]
        XCTAssertTrue(roots.waitForExistence(timeout: 5)); roots.click()
    }
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    revealScrollElement(app, control: open, label: root.lastPathComponent); open.click()
    XCTAssertTrue(app.textFields["Search scanned descendants"].waitForExistence(timeout: 5))
}
@MainActor func openObservedExplorer(_ app: XCUIApplication, root: URL) {
    revealOverviewControl(app, label: "Explore storage"); app.buttons["Explore storage"].click()
    enterObservedExplorerRoot(app, root: root)
}
@MainActor func expandPlanItems(_ app: XCUIApplication) {
    guard !app.textFields["Search Downloads items"].exists else { return }
    let disclosure = app.disclosureTriangles.firstMatch
    revealScrollElement(app, control: disclosure, label: "Choose items disclosure")
    disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
    XCTAssertEqual(disclosure.value as? Int, 1)
    XCTAssertTrue(app.textFields["Search Downloads items"].waitForExistence(timeout: 5))
}

/// Remembered scopes are persistent settings, so each independent journey owns a fresh store.
@MainActor func configureIsolatedJourneyState(_ app: XCUIApplication) throws -> URL {
    let token = UUID().uuidString
    let state = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let marker = state.appendingPathComponent(".still-owned-test-state")
    try Data(token.utf8).write(to: marker)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    var info = stat()
    guard lstat(state.path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
    app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
    app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(info.st_dev):\(info.st_ino)"
    return state
}

final class WorkspaceUITests: XCTestCase {
    @MainActor func testPlanStartsWithContextualDownloadsCategoryAndNoSetupDetour() throws {
        continueAfterFailure = false
        let token = UUID().uuidString
        let state = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(token.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        defer { try? FileManager.default.removeItem(at: state) }
        var info = stat(); XCTAssertEqual(lstat(state.path, &info), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--design-minimum"]
        app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
        app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(info.st_dev):\(info.st_ino)"
        app.launch(); defer { app.terminate() }
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["downloadsCategorySelection"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.checkBoxes["downloadsCategorySelection"].isEnabled)
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            XCTAssertFalse(app.checkBoxes["downloadsCategorySelection"].isEnabled)
            XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        }
        XCTAssertTrue(app.staticTexts["Not scanned"].exists)
        XCTAssertTrue(app.buttons["Scan Downloads…"].isHittable)
        XCTAssertFalse(app.buttons["Choose Downloads…"].exists)
        let bounds = app.windows.firstMatch.frame
        app.buttons["Scan Downloads…"].click()
        XCTAssertTrue(app.dialogs.buttons["Scan folder"].waitForExistence(timeout: 5))
        app.dialogs.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Cleanup plan"].exists)
        XCTAssertTrue(app.buttons["Scan Downloads…"].isHittable)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor func testConnectedDownloadsJourneyPreservesContextAndConsumesPlan() throws { try exerciseConnectedDownloads(minimum: false) }
    @MainActor func testMinimumConnectedDownloadsJourneyPreservesContextAndConsumesPlan() throws { try exerciseConnectedDownloads(minimum: true) }
    @MainActor private func exerciseConnectedDownloads(minimum: Bool) throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        let child = root.appendingPathComponent("Media")
        let token = UUID().uuidString
        let state = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
        for url in [root, child, state] { try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try Data(token.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
        let guide = root.appendingPathComponent("Camera guide.pdf")
        let trip = child.appendingPathComponent("Summer trip.mov")
        try Data([1,2,3]).write(to: guide); try Data([4,5,6,7]).write(to: trip)
        defer { try? manager.removeItem(at: root); try? manager.removeItem(at: state) }
        var rootID = stat(); var stateID = stat()
        XCTAssertEqual(lstat(root.path, &rootID), 0); XCTAssertEqual(lstat(state.path, &stateID), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(rootID.st_dev):\(rootID.st_ino)"
        app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
        app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(stateID.st_dev):\(stateID.st_ino)"
        app.launch(); defer { app.terminate() }
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan Downloads…"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) {
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                attachment.name = "downloads-" + name + (minimum ? "-minimum-" : "-initial-") + theme
                attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
        }
        capture("unscanned")
        app.buttons["Scan Downloads…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: category)
        wait(for: [enabled], timeout: 20)
        XCTAssertTrue(app.staticTexts["Cleanup plan"].exists)
        XCTAssertFalse(app.buttons["Choose Downloads…"].exists)
        XCTAssertFalse(app.textFields["Search Downloads items"].exists)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        capture("ready")
        category.click()
        XCTAssertTrue(app.staticTexts["2 files selected"].waitForExistence(timeout: 10))
        expandPlanItems(app)
        XCTAssertTrue(app.textFields["Search Downloads items"].waitForExistence(timeout: 5))
        let one = app.checkBoxes["Selected Summer trip.mov"]
        revealScrollElement(app, control: one, label: "Selected Summer trip.mov"); one.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
        app.buttons["Explore Downloads"].click()
        XCTAssertTrue(app.buttons["Open folder " + root.lastPathComponent].waitForExistence(timeout: 5))
        app.buttons["Open folder " + root.lastPathComponent].click()
        app.textFields["Search scanned descendants"].click(); app.textFields["Search scanned descendants"].typeText("Media")
        app.buttons["Open folder Media"].click()
        XCTAssertTrue(["", "Search scanned descendants"].contains(app.textFields["Search scanned descendants"].value as? String ?? "Unexpected query"))
        app.buttons["Inspect Summer trip.mov"].click()
        let inspector = app.descendants(matching: .any)["explorerInspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let list = app.descendants(matching: .any)["explorerList"].firstMatch
        if minimum { XCTAssertGreaterThanOrEqual(inspector.frame.minY, list.frame.maxY - 1) }
        else if bounds.width >= 1000 { XCTAssertGreaterThanOrEqual(inspector.frame.minX, list.frame.maxX - 1) }
        XCTAssertTrue(app.buttons["Close inspector"].isHittable)
        XCTAssertTrue(app.buttons["View cleanup plan"].isHittable)
        capture("inspector")
        let explorerSearch = app.textFields["Search scanned descendants"]
        explorerSearch.click(); explorerSearch.typeText("no-such-observed-file")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["explorerInspector"].firstMatch.exists)
        app.buttons["Clear search"].click()
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.textFields["Search Downloads items"].waitForExistence(timeout: 5), "Plan disclosure must survive its Explorer round trip")
        XCTAssertFalse(app.buttons["Back to Explorer"].exists, "Plan ancestor must be reused")
        app.buttons["Explore Downloads"].click()
        XCTAssertTrue(app.descendants(matching: .any)["explorerInspector"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Back to previous folder"].click()
        XCTAssertEqual(app.textFields["Search scanned descendants"].value as? String, "Media")
        app.buttons["Back to previous folder"].click()
        app.buttons["Back to Cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.sheets.buttons["Move to Trash"].waitForExistence(timeout: 5))
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: guide), Data([1,2,3]))
        app.buttons["Review cleanup"].click(); app.sheets.buttons["Move to Trash"].click()
        XCTAssertTrue(app.staticTexts["Cleanup results"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Succeeded: 1"].exists)
        XCTAssertFalse(manager.fileExists(atPath: guide.path))
        XCTAssertEqual(try Data(contentsOf: trip), Data([4,5,6,7]))
        capture("results")
        app.buttons["View history"].click()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan Downloads…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Not scanned"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scan selected locations"].isEnabled)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        app.buttons["Scan Downloads…"].click() // remembered grant: no picker and no automatic selection
        XCTAssertTrue(app.staticTexts["Downloads · 1 file eligible"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.dialogs.buttons["Scan folder"].exists)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        try manager.removeItem(at: trip) // Owned fixture: exercise a complete, genuinely empty eligible set.
        app.buttons["Scan Downloads again"].click()
        XCTAssertTrue(app.staticTexts["No eligible files"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Inspected coverage: " + root.lastPathComponent].exists, "A complete-empty result must name its actual inspected location")
        XCTAssertFalse(app.checkBoxes["downloadsCategorySelection"].isEnabled)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        capture("complete-empty")
        app.typeKey("4", modifierFlags: .command)
        app.checkBoxes["Include " + root.lastPathComponent].click()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No included locations with current observations."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Explore storage"].exists)
        app.typeKey("4", modifierFlags: .command)
        app.checkBoxes["Include " + root.lastPathComponent].click()
        XCTAssertTrue(app.staticTexts["Not scanned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Stop scan"].exists, "Re-inclusion does not scan")
    }

    @MainActor func testOverviewFindingsRestoreHierarchyAndPreserveReviewChoices() throws {
        continueAfterFailure = false
        let manager = FileManager.default
        for minimum in [false, true] {
            let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
            let other = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillBrowseUI-" + UUID().uuidString)
            let token = UUID().uuidString
            let state = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
            let child = root.appendingPathComponent("Child")
            let denied = other.appendingPathComponent("Unreadable")
            for url in [root, other, state, child] { try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            try Data(token.utf8).write(to: state.appendingPathComponent(".still-owned-test-state"))
            defer {
                try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                for url in [root, other, state] { try? manager.removeItem(at: url) }
            }
            let target = root.appendingPathComponent("A-review-target.pdf")
            let original = Data(repeating: 65, count: 4 * 1024 * 1024)
            try Data([1, 2, 3]).write(to: other.appendingPathComponent("browse-only.txt"))
            var rootID = stat(); XCTAssertEqual(lstat(root.path, &rootID), 0)
            var stateID = stat(); XCTAssertEqual(lstat(state.path, &stateID), 0)
            let app = XCUIApplication()
            let isolatedState = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
            app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--ui-test-cloud-unknown", minimum ? "--design-minimum" : "--design-initial-size"]
            app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
            app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(rootID.st_dev):\(rootID.st_ino)"
            app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
            app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(stateID.st_dev):\(stateID.st_ino)"
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.staticTexts["Recommended for review"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Scanned locations"].exists)
            let bounds = app.windows.firstMatch.frame
            func capture(_ name: String, bothPages: Bool = true, findingsOnly: Bool = false) {
                for theme in ["Light", "Dark"] {
                    app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: findingsOnly ? -3000 : 3000)
                    let top = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    top.name = "overview-" + name + (findingsOnly ? "-findings-" : "-top-") + (minimum ? "minimum-" : "initial-") + theme
                    top.lifetime = .keepAlways; add(top)
                    if bothPages && !findingsOnly {
                        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -3000)
                        let findings = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                        findings.name = "overview-" + name + "-findings-" + (minimum ? "minimum-" : "initial-") + theme
                        findings.lifetime = .keepAlways; add(findings)
                    }
                    XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                }
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
            }
            func captureRefresh(_ theme: String) {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                image.name = "overview-refreshing-top-" + (minimum ? "minimum-" : "initial-") + theme
                image.lifetime = .keepAlways; add(image)
                XCTAssertTrue(app.buttons["Stop scan"].exists)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
            func scan(_ url: URL) {
                app.typeKey("1", modifierFlags: .command)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
                app.buttons["Choose folder…"].click()
                app.typeKey("g", modifierFlags: [.command, .shift])
                let field = app.textFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeKey("a", modifierFlags: .command); field.typeText(url.path)
                app.typeKey(.return, modifierFlags: [])
                app.dialogs.buttons["Scan folder"].click()
                waitForOverviewScan(app, timeout: 90)
            }
            func selectedOne() -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "1 file selected", "1 file selected")).firstMatch }
            capture("unscanned")
            scan(root)
            app.typeKey("1", modifierFlags: .command)
            let emptyFinding = app.descendants(matching: .any)["overviewDownloadsFinding"].firstMatch
            XCTAssertTrue(emptyFinding.waitForExistence(timeout: 5))
            XCTAssertTrue((emptyFinding.value as? String ?? "").contains("No eligible files"))
            try original.write(to: target)
            try manager.linkItem(at: target, to: child.appendingPathComponent("hard-link.pdf"))
            for index in 0..<600 { try Data(repeating: 1, count: 16).write(to: root.appendingPathComponent("batch-\(index).txt")) }
            app.buttons["Scan again"].click()
            XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 5))
            waitForScanIdle(app, timeout: 90)
            try Data().write(to: child.appendingPathComponent("unknown-cloud-metadata.txt"))
            scan(child) // Overlap/hard links must not inflate the Overview review amount.
            app.typeKey("1", modifierFlags: .command)
            let reviewFiles = app.buttons["Review files"]
            XCTAssertTrue(reviewFiles.waitForExistence(timeout: 5))
            XCTAssertTrue((reviewFiles.value as? String ?? "").contains("4.2 MB"))
            XCTAssertTrue((reviewFiles.value as? String ?? "").contains("Logical file size"))
            let cloudFinding = app.descendants(matching: .any)["overviewCloudFinding"].firstMatch
            XCTAssertTrue((cloudFinding.value as? String ?? "").contains(" · Unknown · Local allocation"))
            capture("findings")
            revealOverviewControl(app, label: "Review iCloud inventory")
            app.buttons["Review iCloud inventory"].click()
            XCTAssertTrue(app.staticTexts["iCloud in this scan"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "iCloud membership unknown", "iCloud membership unknown")).firstMatch.exists)
            capture("cloud-evidence", bothPages: false, findingsOnly: true)
            revealOverviewControl(app, label: "Hide iCloud inventory")
            app.buttons["Hide iCloud inventory"].click()
            revealOverviewControl(app, label: "Review files")
            app.buttons["Review files"].click()
            enterObservedExplorerRoot(app, root: root)
            XCTAssertTrue(app.staticTexts["Explore Downloads"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "0 files selected", "0 files selected")).firstMatch.exists)
            let initialSearch = app.textFields["Search scanned descendants"]
            XCTAssertTrue(initialSearch.isHittable)
            initialSearch.click(); initialSearch.typeKey("a", modifierFlags: .command); initialSearch.typeText(target.lastPathComponent)
            let checkbox = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS %@", target.lastPathComponent)).firstMatch
            revealScrollElement(app, control: checkbox, label: target.lastPathComponent)
            checkbox.click()
            XCTAssertTrue(selectedOne().waitForExistence(timeout: 5))
            app.buttons["View cleanup plan"].click()
            app.buttons["Review cleanup"].click()
            XCTAssertTrue(app.sheets.buttons["Move to Trash"].waitForExistence(timeout: 5))
            app.sheets.buttons["Cancel"].click()
            XCTAssertTrue(selectedOne().waitForExistence(timeout: 5))
            scan(other) // Focus moves outside Downloads; review must still open its actual Downloads report.
            app.typeKey("1", modifierFlags: .command)
            revealOverviewControl(app, label: "Review files")
            app.buttons["Review files"].click()
            enterObservedExplorerRoot(app, root: root)
            let returnedSearch = app.textFields["Search scanned descendants"]
            XCTAssertTrue(returnedSearch.isHittable)
            returnedSearch.click(); returnedSearch.typeKey("a", modifierFlags: .command); returnedSearch.typeText(target.lastPathComponent)
            XCTAssertTrue(app.checkBoxes.matching(NSPredicate(format: "label CONTAINS %@", target.lastPathComponent)).firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(selectedOne().exists)
            try Data([7]).write(to: root.appendingPathComponent("new-download.txt"))
            try Data([8]).write(to: other.appendingPathComponent("new-browse.txt"))
            app.typeKey("1", modifierFlags: .command)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
            app.buttons["Scan again"].click()
            XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 5))
            captureRefresh("Light")
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -3000)
            XCTAssertTrue(app.buttons["Stop scan"].isHittable)
            XCTAssertTrue(bounds.contains(app.buttons["Stop scan"].frame))
            app.buttons["Stop scan"].click()
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
            waitForScanIdle(app, timeout: 5)
            app.buttons["Scan again"].click() // A cancelled generation must not stop this new queue.
            XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 5))
            captureRefresh("Dark")
            waitForScanIdle(app, timeout: 90)
            app.buttons["Explore storage"].click()
            enterObservedExplorerRoot(app, root: root)
            let search = app.textFields["Search scanned descendants"]
            XCTAssertTrue(search.isHittable)
            search.click(); search.typeKey("a", modifierFlags: .command); search.typeText("new-download.txt")
            let discoveredDownload = app.checkBoxes["Select new-download.txt"]
            XCTAssertTrue(discoveredDownload.waitForExistence(timeout: 5))
            XCTAssertEqual(discoveredDownload.value as? Int, 0)
            search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
            XCTAssertTrue(selectedOne().exists)
            app.buttons["Selected locations"].click()
            enterObservedExplorerRoot(app, root: other)
            let browseSearch = app.textFields["Search scanned descendants"]
            XCTAssertTrue(browseSearch.isHittable)
            browseSearch.click(); browseSearch.typeKey("a", modifierFlags: .command); browseSearch.typeText("new-browse.txt")
            let discoveredBrowse = app.buttons["Inspect new-browse.txt"]
            revealScrollElement(app, control: discoveredBrowse, label: "Inspect new-browse.txt")
            XCTAssertTrue(discoveredBrowse.isHittable)
            XCTAssertFalse(app.checkBoxes.matching(NSPredicate(format: "label CONTAINS %@", "new-browse.txt")).firstMatch.exists)
            try manager.createDirectory(at: denied, withIntermediateDirectories: false)
            try Data([9]).write(to: denied.appendingPathComponent("not-readable.txt"))
            try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
            scan(other)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Partial coverage", "Partial coverage")).firstMatch.waitForExistence(timeout: 10))
            app.typeKey("1", modifierFlags: .command)
            let coverage = app.staticTexts["overviewScopeCoverage"]
            XCTAssertTrue(coverage.waitForExistence(timeout: 5))
            XCTAssertTrue((coverage.value as? String ?? coverage.label).contains("Remaining bytes unknown"))
            capture("partial-browse-only")
            XCTAssertEqual(try Data(contentsOf: target), original)
            try manager.removeItem(at: root) // Only this test's owned scope; failed coverage is not an empty Downloads finding.
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 3000)
            app.buttons["Scan again"].click()
            waitForScanIdle(app, timeout: 90)
            let unavailable = app.descendants(matching: .any)["overviewDownloadsFinding"].firstMatch
            XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
            let unknownState = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (unavailable.value as? String ?? "").contains("Unknown")
            }, object: unavailable)
            XCTAssertEqual(XCTWaiter.wait(for: [unknownState], timeout: 30), .completed)
            waitForScanIdle(app, timeout: 10)
            XCTAssertFalse((unavailable.value as? String ?? "").contains("No eligible files"))
            capture("unavailable-downloads", bothPages: false, findingsOnly: true)
            app.terminate()
        }
    }

    @MainActor func testOverviewSecondaryToolsRemainReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--future-milestones", "--design-minimum"]
        app.launch(); defer { app.terminate() }
        for (label, page) in [("Review Docker storage", "Docker storage"), ("Review Homebrew opportunities", "Homebrew opportunities"), ("Review pip cache opportunities", "Pip cache opportunities"), ("Review app-managed storage", "App-managed storage"), ("Review diagnostics", "Diagnostics")] {
            revealOverviewTool(app, label: label)
            app.buttons[label].click()
            XCTAssertTrue(app.buttons["Back to Overview"].waitForExistence(timeout: 5), page)
            app.buttons["Back to Overview"].click()
            XCTAssertTrue(app.staticTexts["Recommended for review"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testInspectingFixturesPreservesWindowAndNeverSelects() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--fixture-workspace"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic data — no personal files accessed"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let bounds = window.frame
        revealOverviewControl(app, label: "Review Downloads")
        app.buttons["Review Downloads"].click()
        XCTAssertTrue(app.staticTexts["Downloads inspection"].exists)
        app.buttons["Inspect Summer trip.mov"].click()
        XCTAssertTrue(app.staticTexts["Downloads/Trips/Summer trip.mov"].exists)
        XCTAssertTrue(app.staticTexts["Nothing selected"].exists)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["Selected for Trash"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "0 files selected", "0 files selected")).firstMatch.exists)
        XCTAssertEqual(window.frame.width, bounds.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, bounds.height, accuracy: 1)
        XCTAssertTrue(app.staticTexts["Not scanned"].exists)
        XCTAssertFalse(app.checkBoxes["downloadsCategorySelection"].isEnabled)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertFalse(app.textFields["Search Downloads items"].exists)
        XCTAssertEqual(window.frame, bounds)
    }
    @MainActor
    func testKeyboardNavigationAndAppearanceKeepWindowBounds() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--fixture-workspace"]
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
    func testKeyboardCancelRestoresReviewFocusWithoutChangingSelection() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keyboard-review.pdf")
        let original = Data(repeating: 65, count: 137)
        try original.write(to: file)
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.typeKey("a", modifierFlags: .command); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        let selected = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "1 file selected", "1 file selected")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        app.buttons["Review cleanup"].click()
        for key: XCUIKeyboardKey in [.return, .space] {
            let confirmation = app.sheets.containing(.staticText, identifier: "Review Move to Trash").firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            XCTAssertTrue(confirmation.buttons["Move to Trash"].isHittable)
            app.typeKey(.escape, modifierFlags: [])
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirmation)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            XCTAssertTrue(selected.waitForExistence(timeout: 5))
            XCTAssertEqual(category.value as? Int, 1)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(try Data(contentsOf: file), original)
            // No click or tab-count workaround: dismissal must restore the opener's native focus.
            app.typeKey(key, modifierFlags: [])
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "Escape must return keyboard focus to Review cleanup")
        }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: file), original)
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
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
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
        waitForOverviewScan(app, timeout: 10)
        openObservedExplorer(app, root: root)
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        XCTAssertTrue(app.buttons["Inspect camera.txt"].waitForExistence(timeout: 5))
        app.buttons["Inspect camera.txt"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", file.path)).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Logical size: 137 bytes"].exists)
        XCTAssertTrue(app.buttons["Quick Look"].isEnabled)
        XCTAssertTrue(app.buttons["Reveal in Finder"].exists)
        XCTAssertFalse(app.buttons["Remove local download"].exists)
        app.typeKey("1", modifierFlags: .command)
        revealOverviewControl(app, label: "Review iCloud inventory"); app.buttons["Review iCloud inventory"].click()
        XCTAssertTrue(app.staticTexts["iCloud in this scan"].waitForExistence(timeout: 5))
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
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeKey("a", modifierFlags: .command); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        let coverage = app.staticTexts["overviewScopeCoverage"]
        XCTAssertTrue((coverage.value as? String ?? coverage.label).contains("1 byte"))
        try FileManager.default.removeItem(at: root)
        app.buttons["Scan again"].click()
        let unavailable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (coverage.value as? String ?? coverage.label).contains("Unknown")
        }, object: coverage)
        XCTAssertEqual(XCTWaiter.wait(for: [unavailable], timeout: 10), .completed)
        XCTAssertFalse((coverage.value as? String ?? coverage.label).contains("No eligible files"))
        let downloadsFinding = app.descendants(matching: .any)["overviewDownloadsFinding"].firstMatch
        let downloadsUnknown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (downloadsFinding.value as? String ?? downloadsFinding.label).contains("Unknown")
        }, object: downloadsFinding)
        XCTAssertEqual(XCTWaiter.wait(for: [downloadsUnknown], timeout: 5), .completed)
        XCTAssertFalse((downloadsFinding.value as? String ?? downloadsFinding.label).contains("No eligible files"))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Choose again…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", "unavailable", "unavailable")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Last complete observation:", "Last complete observation:")).firstMatch.exists)
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
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
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
        openObservedExplorer(app, root: root)
        let checkbox = app.checkBoxes["Select selected.pdf"]
        for _ in 0..<5 { if checkbox.exists { break }; app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350) }
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(checkbox.value as? Int, 0)
        app.buttons["Inspect selected.pdf"].click()
        XCTAssertEqual(checkbox.value as? Int, 0)
        checkbox.click()
        let search = app.textFields["Search scanned descendants"]
        search.click(); search.typeText("does-not-match")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "1 file selected", "1 file selected")).firstMatch.exists)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["liveSelectionSummary"].waitForExistence(timeout: 5))
        expandPlanItems(app)
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        let bounds = app.windows.firstMatch.frame
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        expandPlanItems(app)
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.checkBoxes["Selected selected.pdf"].click()
        XCTAssertFalse(app.checkBoxes["Selected selected.pdf"].exists)
        app.checkBoxes["Select selected.pdf"].click()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertFalse(app.checkBoxes["Selected selected.pdf"].exists)
    }

    @MainActor
    func testBulkMixedReviewCancelAndImmutableApprovalKeepWindowStable() throws { try exerciseBulk(minimum: false) }

    @MainActor
    func testCleanupResultsAtMinimumWindow() throws { try exerciseBulk(minimum: true) }

    @MainActor
    private func exerciseBulk(minimum: Bool) throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = minimum ? 3 : 20
        for index in 0..<count {
            let path = index % 2 == 0 ? "file\(index).pdf" : "Nested/file\(index).pdf"
            try Data([1]).write(to: root.appendingPathComponent(path))
        }
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(category.value as? Int, 0)
        let bounds = app.windows.firstMatch.frame
        category.click()
        let allSelected = NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "\(count) files selected", "\(count) files selected")
        XCTAssertTrue(app.staticTexts.matching(allSelected).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        expandPlanItems(app)
        let item = app.checkBoxes.matching(NSPredicate(format: "label BEGINSWITH %@", "Selected ")).firstMatch
        for _ in 0..<4 { if item.exists { break }; app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250) }
        XCTAssertTrue(item.exists, app.debugDescription); revealScrollElement(app, control: item, label: "Selected file"); item.click()
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 2000)
        XCTAssertEqual(category.value as? Int, 2)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5))
        let confirmation = app.sheets.containing(.staticText, identifier: "Review Move to Trash").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let disclosure = confirmation.disclosureTriangles.firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.scrollViews.firstMatch.frame.contains(disclosure.frame))
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).click()
        XCTAssertEqual(disclosure.value as? Int, 1)
        XCTAssertTrue(confirmation.buttons["Move to Trash"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "\(count-1) files selected", "\(count-1) files selected")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5), "Cancel must restore focus to Review cleanup")
        app.buttons["Move to Trash"].click()
        XCTAssertTrue(app.staticTexts["Cleanup results"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Succeeded: \(count-1)"].exists)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "cleanup-results-" + (minimum ? "minimum-" : "initial-") + theme; capture.lifetime = .keepAlways; add(capture)
        }
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        let remaining = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".pdf") }
        XCTAssertEqual(remaining.count, 1)
    }

    @MainActor
    func testDesignReviewCaptures() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }; app.launchArguments = ["--fixture-workspace", "--design-initial-size"]; app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            app.typeKey("1", modifierFlags: .command); capture("overview-" + theme)
            revealOverviewControl(app, label: "Review Downloads")
        app.buttons["Review Downloads"].click(); capture("inspection-" + theme)
            app.buttons["View cleanup plan"].click(); capture("plan-" + theme)
            app.typeKey("4", modifierFlags: .command); capture("settings-" + theme)
        }
    }

    @MainActor
    func testNativeDesignReviewAndMinimumGalleryCaptures() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("selected.pdf"))
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click(); capture("native-overview-" + theme)
        }
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        openObservedExplorer(app, root: root)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click(); capture("native-inspection-" + theme)
        }
        let selected = app.checkBoxes["Select selected.pdf"]
        for _ in 0..<5 {
            if selected.exists && app.scrollViews.firstMatch.frame.contains(selected.frame) { break }
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        }
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(selected.frame)); selected.click()
        XCTAssertEqual(selected.value as? Int, 1)

        app.buttons["View cleanup plan"].click()
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("native-plan-" + theme)
            XCTAssertTrue(app.buttons["Review cleanup"].isEnabled && app.buttons["Review cleanup"].isHittable)
            app.buttons["Review cleanup"].click()
            XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5))
            capture("native-confirmation-" + theme)
            XCTAssertTrue(app.buttons["Cancel"].isHittable && app.buttons["Move to Trash"].isHittable)
            app.buttons["Cancel"].click()
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.typeKey("4", modifierFlags: .command); capture("native-locations-" + theme)
            app.typeKey("2", modifierFlags: .command)
        }
        app.terminate()
        app.launchArguments = ["--future-milestones", "--design-initial-size"]
        app.launch(); app.typeKey("5", modifierFlags: .command)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click(); capture("native-alert-settings-" + theme)
        }

    }

    @MainActor
    func testMinimumGalleryStatesAndOpaqueChromeCaptures() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        app.launchArguments = ["--design-gallery", "--design-minimum"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native design system"].waitForExistence(timeout: 10))
        let minimum = app.windows.firstMatch.frame
        XCTAssertEqual(minimum.width, 900, accuracy: 1)
        XCTAssertEqual(minimum.height, 640, accuracy: 1)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("gallery-minimum-" + theme)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1200)
            capture("gallery-states-minimum-" + theme)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 2000)
        }
        app.checkBoxes["Opaque chrome"].click()
        capture("gallery-minimum-opaque-Dark")
        XCTAssertEqual(app.windows.firstMatch.frame, minimum)
    }

    @MainActor
    func testDownloadsScopeGuidanceAndShortcutPreserveInspection() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillBrowseUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Inspection-only document.txt")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }
        for size in ["--design-initial-size", "--design-minimum"] {
            let app = XCUIApplication()
            let isolatedState = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
            app.launchArguments = [size, "--design-opaque-chrome"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Choose Downloads…"].waitForExistence(timeout: 10))
            let bounds = app.windows.firstMatch.frame
            func checkOverview(_ state: String) {
                for theme in ["Light", "Dark"] {
                    app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                    XCTAssertTrue(app.staticTexts["Cleanup currently supports files in Downloads only. Other folders are inspection only."].exists)
                    XCTAssertTrue(app.buttons["Choose Downloads…"].isHittable)
                    let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    capture.name = "scope-" + state + "-" + theme + size; capture.lifetime = .keepAlways; add(capture)
                    app.buttons["Choose Downloads…"].click()
                    XCTAssertTrue(app.dialogs.buttons["Scan folder"].waitForExistence(timeout: 5))
                    app.dialogs.buttons["Cancel"].click()
                    XCTAssertTrue(app.buttons["Choose Downloads…"].waitForExistence(timeout: 5))
                    XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                }
            }
            func checkPlan() {
                app.typeKey("2", modifierFlags: .command)
                XCTAssertTrue(app.staticTexts["Not scanned"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["Choose Downloads…"].exists)
                XCTAssertFalse(app.checkBoxes["downloadsCategorySelection"].isEnabled)
                XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
                XCTAssertTrue(app.buttons["Scan Downloads…"].isHittable)
                app.buttons["Scan Downloads…"].click()
                XCTAssertTrue(app.dialogs.buttons["Scan folder"].waitForExistence(timeout: 5))
                app.dialogs.buttons["Cancel"].click()
                XCTAssertTrue(app.staticTexts["Cleanup plan"].exists)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
            checkOverview("overview")
            XCTAssertFalse(app.staticTexts["overviewScopeCoverage"].exists)
            checkPlan()
            app.typeKey("1", modifierFlags: .command)
            app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
            let path = app.textFields.firstMatch
            XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
            app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
            waitForOverviewScan(app, timeout: 10)
            checkOverview("inspection-only-observed")
            let uninspectedDownloads = app.descendants(matching: .any)["overviewDownloadsFinding"].firstMatch
            XCTAssertTrue(uninspectedDownloads.waitForExistence(timeout: 5))
            XCTAssertTrue((uninspectedDownloads.value as? String ?? "").contains("Not inspected"))
            openObservedExplorer(app, root: root)
            XCTAssertTrue(app.buttons["Inspect " + file.lastPathComponent].waitForExistence(timeout: 5))
            XCTAssertFalse(app.checkBoxes.matching(NSPredicate(format: "label CONTAINS %@", file.lastPathComponent)).firstMatch.exists)
            XCTAssertFalse(app.buttons["Stop scan"].exists, "Browsing observed files must not scan")
            checkPlan()
            XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
            app.terminate()
        }
    }

    @MainActor
    func testScrolledCategorySelectionKeepsContentAnchored() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Long project folder name for layout and keyboard review")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<120 { try Data(repeating: 1, count: 128 * 1024).write(to: nested.appendingPathComponent("A long descriptive document name with several words - \(i).pdf")) }
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum", "--design-opaque-chrome"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        let bounds = app.windows.firstMatch.frame
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        func settle(_ expected: Int) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                category.isEnabled && category.value as? Int == expected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        }
        category.click(); settle(1)
        expandPlanItems(app)
        let topFrame = category.frame
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -140)
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(category.frame))
        let anchor = category.frame
        XCTAssertLessThan(anchor.minY, topFrame.minY)
        for expected in [0, 1] {
            let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            before.name = "scrolled-category-before-" + String(expected); before.lifetime = .keepAlways; add(before)
            category.click(); settle(expected)
            let after = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            after.name = "scrolled-category-after-" + String(expected); after.lifetime = .keepAlways; add(after)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(category.frame, anchor, "Bulk selection must preserve the scrolled category anchor")
        }
    }

    @MainActor
    func testCheckboxSelectionKeepsContentAnchored() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Long project folder name for layout and keyboard review")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<120 { try Data([1]).write(to: nested.appendingPathComponent("A long descriptive document name with several words - \(i).pdf")) }
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum", "--design-opaque-chrome"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        let bounds = app.windows.firstMatch.frame
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        let categoryFrame = category.frame
        for index in 0..<4 {
            let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            before.name = "checkbox-category-before-" + String(index); before.lifetime = .keepAlways; add(before)
            category.click()
            XCTAssertEqual(category.value as? Int, index.isMultiple(of: 2) ? 1 : 0)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(category.frame, categoryFrame, "Selection must not displace its category control")
            let after = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            after.name = "checkbox-category-after-" + String(index); after.lifetime = .keepAlways; add(after)
        }
        expandPlanItems(app)
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        let rows = app.checkBoxes.allElementsBoundByIndex.filter {
            $0.label.hasSuffix(".pdf") && $0.isHittable && app.scrollViews.firstMatch.frame.contains($0.frame)
        }
        let row = try XCTUnwrap(rows.last)
        let filename = row.label.replacingOccurrences(of: "Selected ", with: "").replacingOccurrences(of: "Select ", with: "")
        let control = app.checkBoxes.matching(NSPredicate(format: "label ENDSWITH %@", filename)).firstMatch
        for index in 0..<4 {
            let frame = control.frame
            XCTAssertTrue(control.isHittable)
            control.click()
            let expected = index.isMultiple(of: 2) ? 1 : 0
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                control.value as? Int == expected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(control.frame, frame, "Selection must keep the clicked item anchored in the viewport")
        }
    }

    @MainActor
    func testInspectionCheckboxSelectionKeepsContentAnchored() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Long project folder name for layout and keyboard review")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<120 { try Data([1]).write(to: nested.appendingPathComponent("A long descriptive document name with several words - \(i).pdf")) }
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum", "--design-opaque-chrome"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        openObservedExplorer(app, root: root)
        app.buttons["Open folder " + nested.lastPathComponent].click()
        let bounds = app.windows.firstMatch.frame
        for _ in 0..<4 {
            if app.checkBoxes.allElementsBoundByIndex.contains(where: { $0.label.hasSuffix(".pdf") && $0.isHittable && app.scrollViews.firstMatch.frame.contains($0.frame) }) { break }
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        }
        let rows = app.checkBoxes.allElementsBoundByIndex.filter { $0.label.hasSuffix(".pdf") && $0.isHittable && app.scrollViews.firstMatch.frame.contains($0.frame) }
        let row = try XCTUnwrap(rows.last)
        let filename = row.label.replacingOccurrences(of: "Selected ", with: "").replacingOccurrences(of: "Select ", with: "")
        let control = app.checkBoxes.matching(NSPredicate(format: "label ENDSWITH %@", filename)).firstMatch
        for index in 0..<4 {
            let frame = control.frame
            let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            before.name = "checkbox-inspection-before-" + String(index); before.lifetime = .keepAlways; add(before)
            control.click()
            let expected = index.isMultiple(of: 2) ? 1 : 0
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                control.value as? Int == expected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(control.frame, frame, "Selection must keep the inspected item anchored in the viewport")
            let after = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            after.name = "checkbox-inspection-after-" + String(index); after.lifetime = .keepAlways; add(after)
        }
    }

    @MainActor
    func testMinimumPopulatedPlanAndConfirmationRemainReachable() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Long project folder name for layout and keyboard review")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<12 { try Data([1]).write(to: nested.appendingPathComponent("A long descriptive document name with several words - \(i).pdf")) }
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum", "--design-opaque-chrome"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        app.typeKey("2", modifierFlags: .command)
        app.checkBoxes["downloadsCategorySelection"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "12 files selected")).firstMatch.waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        XCTAssertEqual(bounds.width, 900, accuracy: 1); XCTAssertEqual(bounds.height, 640, accuracy: 1)
        func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("native-plan-minimum-opaque-" + theme)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1500)
            XCTAssertTrue(app.buttons["Review cleanup"].isEnabled && app.buttons["Review cleanup"].isHittable)
            app.buttons["Review cleanup"].click()
            XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5))
            capture("native-confirmation-minimum-" + theme)
            XCTAssertTrue(app.buttons["Cancel"].isHittable && app.buttons["Move to Trash"].isHittable)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertFalse(app.staticTexts["Review Move to Trash"].exists)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 2000)
        }
    }

    @MainActor
    func testOwnedLargeScanShowsBoundedProgressAndAcknowledgesStop() throws {
        try assertOwnedProgress(minimum: false)
    }
    @MainActor
    func testMinimumOwnedLargeScanKeepsProgressAndStopReachable() throws {
        try assertOwnedProgress(minimum: true)
    }
    @MainActor
    private func assertOwnedProgress(minimum: Bool) throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
        let available = try temporary.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        guard available > 1_900_000_000 else { throw XCTSkip("Owned progress fixture requires conservative disk headroom") }
        let root = temporary.appendingPathComponent("StillProgressUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        for index in 0..<50_000 {
            try autoreleasepool {
                if index % 1000 == 0 { try manager.createDirectory(at: root.appendingPathComponent("batch-\(index / 1000)"), withIntermediateDirectories: false) }
                try Data().write(to: root.appendingPathComponent("batch-\(index / 1000)/file-\(index)"))
            }
        }
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        for appearance in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[appearance].click()
            if appearance == "Light" {
                app.buttons["Choose folder…"].click()
                app.typeKey("g", modifierFlags: [.command, .shift])
                let field = app.textFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.typeKey("a", modifierFlags: .command); field.typeText(root.path)
                app.typeKey(.return, modifierFlags: [])
                app.dialogs.buttons["Scan folder"].click()
            } else { app.buttons["Scan again"].click() }
            XCTAssertTrue(app.staticTexts["scanProgressSummary"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 1))
            XCTAssertTrue(bounds.contains(app.buttons["Stop scan"].frame))
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "bounded-scan-progress-" + (minimum ? "minimum-" : "") + appearance; shot.lifetime = .keepAlways; add(shot)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -40)
            app.buttons["Stop scan"].click()
            let stopped = app.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] 'Stop requested' OR value CONTAINS[c] 'Scan stopped'"))
            XCTAssertTrue(stopped.firstMatch.waitForExistence(timeout: 1))
            waitForScanIdle(app, timeout: 3)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertFalse(app.buttons["Review cleanup"].exists)
        }
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("batch-0/file-0").path))
    }

    @MainActor
    func testInitialReviewWindowFitsConstrainedDisplayAndKeepsToolbarReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--fixture-workspace", "--design-initial-size", "--design-constrained-screen"]
        app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(bounds.width, 1024)
        XCTAssertLessThanOrEqual(bounds.height, 720)
        XCTAssertGreaterThanOrEqual(bounds.width, 900)
        XCTAssertGreaterThanOrEqual(bounds.height, 640)
        XCTAssertTrue(app.popUpButtons["Appearance"].isHittable)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.popUpButtons["Appearance"].click(); app.menuItems["Dark"].click()
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Review Downloads"].isHittable)
        XCTAssertTrue(app.popUpButtons["Appearance"].isHittable)
    }

    @MainActor
    func testRefreshPreservesChoicesAndSearchThenExplainsChangedTargets() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("selected.pdf")
        try Data([1, 2, 3]).write(to: chosen)
        let app = XCUIApplication()
        let isolatedState = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app, timeout: 10)
        openObservedExplorer(app, root: root)
        let checkbox = app.checkBoxes["Select selected.pdf"]
        for _ in 0..<5 {
            if checkbox.exists && app.scrollViews.firstMatch.frame.contains(checkbox.frame) { break }
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        }
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(checkbox.frame)); checkbox.click()
        XCTAssertEqual(checkbox.value as? Int, 1)
        app.buttons["View cleanup plan"].click()
        expandPlanItems(app)
        let search = app.textFields["Search Downloads items"]
        search.click(); search.typeText("selected.pdf")
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        for i in 0..<500 { try Data().write(to: root.appendingPathComponent("new-\(i).txt")) }
        let recheck = app.buttons["Scan Downloads again"]
        XCTAssertTrue(recheck.isHittable); recheck.click()
        XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(search.exists, "Expanded observations must remain visible while the manual refresh runs")
        XCTAssertEqual(search.value as? String, "selected.pdf", "Refreshing must retain the visible refinement query")
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Return to scan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add folder…"].isEnabled)
        XCTAssertTrue(app.buttons["Stop scan"].isHittable)
        app.buttons["Return to scan"].click()
        XCTAssertTrue(app.staticTexts["Cleanup plan"].exists)
        app.buttons["Stop scan"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Refresh required ·")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("refresh-required-" + theme) }
        recheck.click()
        XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["Review cleanup"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(search.value as? String, "selected.pdf")
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "1 file selected", "1 file selected")).firstMatch.exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        // Same-size change: contents do not need to be read to invalidate the original observation.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)], ofItemAtPath: chosen.path)
        recheck.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "File changed or is no longer eligible.")).firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertTrue(app.checkBoxes["Select selected.pdf"].exists)
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("refresh-changed-" + theme) }
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: chosen), Data([1, 2, 3]))
    }

    @MainActor
    func testCompletedGrowthUsesExplicitScopesAndShowsUnknownForUnmeasuredCoverage() throws {
        continueAfterFailure = false
        for minimum in [false, true] {
            let suffix = UUID().uuidString
            let state = FileManager.default.temporaryDirectory.appendingPathComponent("StillTestState-" + suffix).resolvingSymlinksInPath()
            let scope = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthUI-" + suffix).resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: scope) }
            let marker = state.appendingPathComponent(".still-owned-test-state")
            try Data(suffix.utf8).write(to: marker)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            var info = stat(); XCTAssertEqual(lstat(state.path, &info), 0)
            try Data([1, 2, 3]).write(to: scope.appendingPathComponent("private-fixture.pdf"))
            let app = XCUIApplication()
            let isolatedState = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
            app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
            app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(info.st_dev):\(info.st_ino)"
            app.launchArguments = ["--future-milestones", minimum ? "--design-minimum" : "--design-initial-size"]
            app.launch()
            let bounds = app.windows.firstMatch.frame
            func scan() {
                app.buttons["What grew"].click()
                XCTAssertTrue(app.buttons["Inspect a folder"].waitForExistence(timeout: 5))
                app.buttons["Inspect a folder"].click()
                app.typeKey("g", modifierFlags: [.command, .shift])
                let path = app.textFields.firstMatch
                XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(scope.path)
                app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
                // Growth stays at its origin and has no Overview-only “Scan again” control.
                // Wait for the shared running state to end; each caller below also requires
                // the newly completed comparison result, so stale content cannot pass.
                let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Stop scan"])
                XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
                XCTAssertTrue(app.staticTexts["What grew"].exists)
                XCTAssertFalse(app.buttons["Back to Overview"].exists)
                XCTAssertTrue(app.buttons["Inspect a folder"].exists)
            }
            func captures(_ stateName: String) {
                for theme in ["Light", "Dark"] {
                    app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    attachment.name = "growth-" + stateName + "-" + (minimum ? "minimum-" : "initial-") + theme
                    attachment.lifetime = .keepAlways; add(attachment)
                    XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                }
            }
            scan()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "First observation")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Scope: " + scope.lastPathComponent].waitForExistence(timeout: 5))
            captures("first")
            try Data([1, 2, 3, 4, 5]).write(to: scope.appendingPathComponent("new-fixture.pdf"))
            scan()
            XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["growthNetChange"].value as? String, "+5 bytes net logical change")
            captures("compared")
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(app.staticTexts["Documents"].isHittable)
            captures("compared-details")
            try FileManager.default.createDirectory(at: scope.appendingPathComponent("Unmeasured.photoslibrary"), withIntermediateDirectories: false)
            scan()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Growth unknown")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["growthNetChange"].exists)
            captures("unknown")
            let history = try String(contentsOf: state.appendingPathComponent("Growth/aggregates-v1.json"), encoding: .utf8)
            XCTAssertFalse(history.contains("private-fixture")); XCTAssertFalse(history.contains("new-fixture"))
            app.terminate()
        }
    }

    @MainActor
    func testChangingDirectoryRecheckKeepsStopReachableAndNeverEnablesCleanup() throws {
        continueAfterFailure = false
        for minimum in [false, true] {
            let suffix = UUID().uuidString
            let scope = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + suffix).resolvingSymlinksInPath()
            let state = FileManager.default.temporaryDirectory.appendingPathComponent("StillTestState-" + suffix).resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: scope); try? FileManager.default.removeItem(at: state) }
            let marker = state.appendingPathComponent(".still-owned-test-state")
            try Data(suffix.utf8).write(to: marker)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            var information = stat(); XCTAssertEqual(lstat(state.path, &information), 0)
            try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
            for index in 0..<500 { try Data().write(to: scope.appendingPathComponent("entry-\(index).txt")) }
            let app = XCUIApplication()
            let isolatedState = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: isolatedState) }
            app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--ui-test-directory-instability", minimum ? "--design-minimum" : "--design-initial-size"]
            app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = scope.path
            var scopeInformation = stat(); XCTAssertEqual(lstat(scope.path, &scopeInformation), 0)
            app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(scopeInformation.st_dev):\(scopeInformation.st_ino)"
            app.launchEnvironment["STILL_TEST_STATE_ROOT"] = state.path
            app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(information.st_dev):\(information.st_ino)"
            app.launch()
            let bounds = app.windows.firstMatch.frame
            app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
            let path = app.textFields.firstMatch
            XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(scope.path)
            app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND value BEGINSWITH %@", "scanPhase", "Rechecking changed coverage")).firstMatch.waitForExistence(timeout: 25))
            let stop = app.buttons["Stop scan"]
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                XCTAssertTrue(bounds.contains(stop.frame))
                let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                shot.name = "directory-recheck-" + (minimum ? "minimum-" : "initial-") + theme
                shot.lifetime = .keepAlways; add(shot)
            }
            stop.click()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Stop requested.")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Review cleanup"].exists)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(try Data(contentsOf: scope.appendingPathComponent("trigger.txt")), Data([1]))
            app.terminate()
        }
    }

}
