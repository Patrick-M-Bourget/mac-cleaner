import XCTest
import Darwin
import StillCore

final class DiagnosticsUITests: XCTestCase {
    @MainActor func testReviewedDiagnosticsCancelKeepsPayloadAndRecovery() async throws { try await inspect(minimum: false) }
    @MainActor func testMinimumDiagnosticsKeepsSaveAndPayloadReachable() async throws { try await inspect(minimum: true) }
    @MainActor private func inspect(minimum: Bool) async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try String(root.lastPathComponent.dropFirst("StillTestState-".count)).write(to: root.appendingPathComponent(".still-owned-test-state"), atomically: false, encoding: .utf8)
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        let original = downloads.appendingPathComponent("private-person-secret.pdf")
        try Data([9]).write(to: original)
        let scan = try await FolderScanner().scan(downloads)
        var plan = PlanDraft(); _ = plan.selectAll(in: [scan], downloads: try DownloadsRoot(url: downloads))
        let approval = try plan.approve(plan.review())
        let target = try XCTUnwrap(approval.targets.first)
        do {
            let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
            XCTAssertTrue(try journal.claim(approval))
            var record = CleanupRecord(batch: approval, target: target); record.state = .intent
            try journal.intent(record)
        }
        var metadata = stat(); XCTAssertEqual(lstat(root.path, &metadata), 0)
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(metadata.st_dev):\(metadata.st_ino)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Return to Overview"].waitForExistence(timeout: 5))
        app.buttons["Return to Overview"].click()
        let open = app.buttons["Review diagnostics"]
        if !open.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250) }
        open.click()
        let bounds = app.windows.firstMatch.frame
        let payload = app.staticTexts["diagnosticsPayload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 3))
        let text = payload.value as? String ?? payload.label
        XCTAssertTrue(text.contains("requiresReview"))
        XCTAssertFalse(text.contains(original.lastPathComponent))
        XCTAssertFalse(text.contains(root.path))
        XCTAssertFalse(text.contains(target.resourceID))
        XCTAssertFalse(text.contains(approval.id.uuidString))
        for appearance in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[appearance].click()
            let top = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); top.name = "diagnostics-" + (minimum ? "minimum-" : "initial-") + appearance; top.lifetime = .keepAlways; add(top)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -450)
            let preview = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); preview.name = "diagnostics-payload-" + (minimum ? "minimum-" : "initial-") + appearance; preview.lifetime = .keepAlways; add(preview)
            XCTAssertTrue(bounds.contains(app.buttons["Save diagnostics…"].frame))
            XCTAssertEqual(bounds, app.windows.firstMatch.frame)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 600)
        }
        app.buttons["Save diagnostics…"].click()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3)); cancel.click()
        XCTAssertTrue(app.staticTexts["diagnosticsStatus"].waitForExistence(timeout: 3))
        XCTAssertEqual(payload.value as? String ?? payload.label, text)
        XCTAssertTrue(app.buttons["Save diagnostics…"].isEnabled)
        XCTAssertEqual(bounds, app.windows.firstMatch.frame)
        app.terminate()
        XCTAssertEqual(try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"), readOnly: true).records().map(\.state), [.intent])
        XCTAssertEqual(try Data(contentsOf: original), Data([9]))
    }
}
