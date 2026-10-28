import XCTest

/// #173: files from deleted apps, in a fixture home. Installed apps come only from the home's
/// `.cachedrop-test-installed-apps` (DEBUG seam), so the journey never asks Spotlight or Launch Services about this Mac.
final class RemovedAppLeftoversUITests: XCTestCase {
    @MainActor func testLeftoversAreGroupedPerAppAndPossiblyRelatedItemsAreNeverTickedWithTheirCategory() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try "com.here.editor\n".write(to: home.appendingPathComponent(".cachedrop-test-installed-apps"), atomically: true, encoding: .utf8)
        let files = ["Library/Preferences/com.gone.synth.plist", "Library/Containers/com.gone.synth/Data/state.db",
                     "Library/Application Support/Gone/presets.db", "Library/Preferences/com.here.editor.plist",
                     "Library/Application Support/PACE Anti-Piracy/license.dat"].map(home.appendingPathComponent)
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()

        // #255: a cold launch can take longer than any fixed wait, so wait for the scan itself.
        waitForCatalogScan(app)
        let overview = app.buttons["overviewCategory-leftovers"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        revealAndClick(overview, in: app)

        let category = app.checkBoxes["planCategory-leftovers"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        expandDisclosures(in: app)
        XCTAssertTrue(app.checkBoxes["planProfile-removed-app-leftovers-Synth"].waitForExistence(timeout: 5), "Grouped per app")
        let possible = app.checkBoxes["planItem-Gone"]
        XCTAssertTrue(possible.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'com.here.editor' OR identifier CONTAINS 'PACE'")).firstMatch.exists)

        tick(category, in: app)
        XCTAssertEqual(possible.value as? Int, 0, "A possibly related item is never ticked with its category")
        XCTAssertEqual(app.checkBoxes["planProfile-removed-app-leftovers-Synth"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "movedToTrash", "leftovers").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// #356: on Applications a possibly related item is chosen in the app: clicking its row ticks it, alone, with Reveal in
    /// Finder beside it, and the "Possibly related" row opens no Finder window. It is reviewed and cleaned (a dry run here).
    @MainActor func testAPossiblyRelatedItemIsTickedOnApplicationsReviewedAndCleaned() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try "com.here.editor\n".write(to: home.appendingPathComponent(".cachedrop-test-installed-apps"), atomically: true, encoding: .utf8)
        // Synth's saved window state ties it to the removed app; the "Gone" folder is named like its maker only.
        let files = ["Library/Saved Application State/com.gone.synth.savedState/data.data", "Library/Application Support/Gone/presets.db"]
            .map(home.appendingPathComponent)
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("5", modifierFlags: .command)

        XCTAssertTrue(app.checkBoxes["planCategory-leftovers"].waitForExistence(timeout: 10))
        expandDisclosures(in: app)
        let item = app.checkBoxes["planItem-Gone"], group = app.checkBoxes["planProfile-removed-app-leftovers-Synth"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? Int, 0, "A possibly related item is never recommended")
        XCTAssertTrue(app.descendants(matching: .any)["planItemReveal-Gone"].exists, "Reveal in Finder is beside it")
        XCTAssertFalse(app.buttons["Select Possibly related"].exists, "The rule's row is inert")
        XCTAssertFalse(app.links["planRuleReveal-removed-app-possibly-related"].exists, "and no Finder link")
        // Synth's confirmed file is recommended, so it may arrive ticked (#349); untick it, by clicking its row (#367), to clean
        // the one item alone.
        if group.value as? Int == 1 { revealAndClick(app.buttons["Select Synth"], in: app) }
        XCTAssertEqual(group.value as? Int, 0)

        revealAndClick(app.buttons["Select Gone"], in: app)
        XCTAssertEqual(item.value as? Int, 1, "Clicking its row ticks it in the app")
        XCTAssertEqual(group.value as? Int, 0, "Alone: its group stays unticked")
        XCTAssertEqual(app.staticTexts["actionStripNote"].value as? String, "1 item selected", "The bar counts it")
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "movedToTrash", "leftovers").waitForExistence(timeout: 5), "It goes to the Trash")
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "A dry run moves nothing: " + file.path) }
    }

    /// #240: a category of only possibly related items. Its checkbox used to do nothing; now it lists the items to tick one by
    /// one, shows the ones ticked, and clears them.
    @MainActor func testACategoryOfOnlyPossiblyRelatedItemsListsThemAndClearsThem() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try "com.here.editor\n".write(to: home.appendingPathComponent(".cachedrop-test-installed-apps"), atomically: true, encoding: .utf8)
        // Named by a removed app's ID, but nothing shows it was an app's: possibly related only (#251).
        let file = home.appendingPathComponent("Library/Preferences/com.gone.synth.plist")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: file)
        app.launch()

        let overview = app.buttons["overviewCategory-leftovers"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        revealAndClick(overview, in: app)
        let category = app.checkBoxes["planCategory-leftovers"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.isEnabled)

        revealAndClick(category, in: app)
        let item = app.checkBoxes["planItem-com.gone.synth.plist"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The category's checkbox lists its items")
        XCTAssertEqual(item.value as? Int, 0, "and never ticks a possibly related item")
        XCTAssertEqual(category.value as? Int, 0)

        revealAndClick(item, in: app)
        XCTAssertEqual(item.value as? Int, 1)
        XCTAssertEqual(category.value as? Int, 1, "An item ticked by hand shows on its category")
        revealAndClick(category, in: app)
        XCTAssertEqual(item.value as? Int, 0, "The category's checkbox clears it")
        XCTAssertEqual(category.value as? Int, 0)
    }
}
