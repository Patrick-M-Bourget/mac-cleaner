import XCTest

/// A fixture home with an npm cache, inside the runner's temp folder. The app reads it only through
/// the DEBUG-only STILL_TEST_CATALOG_HOME seam, so the journey never touches real user paths.
@MainActor func configureCatalogHome(_ app: XCUIApplication) throws -> URL {
    let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestHome-" + UUID().uuidString)
    let file = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/ab/blob")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: 200_000).write(to: file)
    app.launchEnvironment["STILL_TEST_CATALOG_HOME"] = home.path
    return home
}

final class CatalogCleanupUITests: XCTestCase {
    @MainActor func testPreviewOnlyCleanupOfAFixtureCategoryReachesResultsAndChangesNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["0 bytes"].exists)
        row.click()

        // Opening a category from Overview never preselects it.
        let category = app.checkBoxes["planRule-npm-cache"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        category.click()

        let preview = app.checkBoxes["previewOnlyToggle"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(preview.value as? Int, 1)
        let review = app.buttons["Review cleanup"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        review.click()

        XCTAssertTrue(app.staticTexts["Clear npm cache"].waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache/content-v2/sha512/ab/blob").path))
    }
}
