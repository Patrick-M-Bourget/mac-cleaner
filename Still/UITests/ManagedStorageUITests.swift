import XCTest

final class ManagedStorageUITests: XCTestCase {
    @MainActor
    func testFutureManagedGuidanceIsReadOnlyAndReturnsToOverviewWithoutResizing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Review app-managed storage"].waitForExistence(timeout: 5))
        let frame = app.windows.firstMatch.frame
        app.buttons["Review app-managed storage"].click()
        XCTAssertTrue(app.staticTexts["App-managed storage"].exists)
        app.buttons["Review Photos"].click()
        XCTAssertTrue(app.buttons["Open Photos"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "deleting photos can delete them")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Add to cleanup plan"].exists)
        app.buttons["Review System-managed storage"].click()
        XCTAssertTrue(app.staticTexts["Not independently estimated"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, frame)
        app.buttons["Back to Overview"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, frame)
    }
}
