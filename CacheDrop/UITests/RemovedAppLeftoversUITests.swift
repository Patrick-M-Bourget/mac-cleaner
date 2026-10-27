import XCTest

/// #173: leftovers of apps you removed, in a fixture home. Installed apps come only from the home's
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

        let overview = app.buttons["overviewCategory-leftovers"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        revealAndClick(overview, in: app)

        let category = app.checkBoxes["planCategory-leftovers"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        expandDisclosures(in: app)
        XCTAssertTrue(app.checkBoxes["planProfile-removed-app-leftovers-Synth"].waitForExistence(timeout: 5), "Grouped per app")
        let possible = app.checkBoxes["planItem-Gone"]
        XCTAssertTrue(possible.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'com.here.editor' OR identifier CONTAINS 'PACE'")).firstMatch.exists)

        revealAndClick(category, in: app)
        XCTAssertEqual(possible.value as? Int, 0, "A possibly related item is never ticked with its category")
        XCTAssertEqual(app.checkBoxes["planProfile-removed-app-leftovers-Synth"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "movedToTrash", "leftovers").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }
}
