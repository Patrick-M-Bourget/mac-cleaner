import XCTest
import Darwin

/// A fresh, owned state root so a launch never reads or writes the user's real app state.
@MainActor func configureIsolatedState(_ app: XCUIApplication) throws -> URL {
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

final class LaunchSmokeUITests: XCTestCase {
    @MainActor func testLaunchShowsOverviewAndWhatGrewWithoutStorageAlerts() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cleanup plan"].exists || app.staticTexts["Cleanup plan"].exists)
        XCTAssertTrue(app.staticTexts["What grew"].exists || app.buttons["What grew"].exists, "What grew is in the sidebar (#119)")
        XCTAssertFalse(app.staticTexts["Storage alerts"].exists)
    }

    /// A relaunch after a previous session must still open the main window, whatever state macOS saved.
    @MainActor func testRelaunchShowsMainWindow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
    }

    /// #115: launch never asks for access; Locations & access shows the state in one row and the shared explanation.
    /// The fixture home's Safari folder refuses to open, which is how the probe sees missing Full Disk Access.
    @MainActor func testFullDiskAccessIsExplainedOnlyWhenAsked() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let safari = home.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: safari.path)
        defer {
            app.terminate(); try? FileManager.default.removeItem(at: state)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path); try? FileManager.default.removeItem(at: home)
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.exists, "Nothing asks for access at launch")

        app.buttons["Locations & access"].click()
        let status = app.staticTexts["fullDiskAccessStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue((status.value as? String ?? status.label).contains("Not granted"))

        revealAndClick(app.links["fullDiskAccessLink"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["Full Disk Access is optional"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Still’s scans stay read-only. Nothing protected becomes eligible for cleanup, and Still only changes what you choose and review."].exists)
        XCTAssertTrue(app.buttons["openFullDiskAccessSettings"].exists) // Not pressed: tests never open System Settings.
        app.buttons["closeFullDiskAccess"].click()
        XCTAssertFalse(app.staticTexts["Full Disk Access is optional"].waitForExistence(timeout: 2))
    }

    /// #124: Full Disk Access granted while Still was away: coming back rescans once, and the "needs Full Disk Access"
    /// line goes away without Scan again. The fixture's Safari folder opening again stands in for the grant.
    @MainActor func testGrantingFullDiskAccessRescansWhenStillBecomesActive() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let safari = home.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: safari.path)
        defer {
            app.terminate(); try? FileManager.default.removeItem(at: state)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path); try? FileManager.default.removeItem(at: home)
        }
        app.launch()
        let denied = app.descendants(matching: .any)["overviewNotAccessible"]
        XCTAssertTrue(denied.waitForExistence(timeout: 10))

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.activate()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: denied)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed, "Becoming active after the grant rescanned")
    }
}

/// #119: the first catalog scan records a baseline; the next shows growth per category and location.
final class WhatGrewUITests: XCTestCase {
    @MainActor func testFirstScanRecordsABaselineAndTheNextShowsWhatGrew() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        app.buttons["What grew"].click()
        XCTAssertTrue(app.staticTexts["Baseline recorded"].waitForExistence(timeout: 15))

        let grown = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/cd/blob")
        try FileManager.default.createDirectory(at: grown.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 9, count: 5_000_000).write(to: grown)
        app.buttons["growthScanAgain"].click()
        XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 15))
        // Each change row reads as one element: its title, the rules that grew and the change.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Developer caches and build files'")).firstMatch.exists)

        app.radioButtons["Locations"].firstMatch.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '~/.npm/_cacache'")).firstMatch.waitForExistence(timeout: 5))

        app.buttons["growthReviewOptions"].click()
        XCTAssertTrue(app.buttons["Back to What grew"].waitForExistence(timeout: 5))
    }
}

/// Decision 25: appearance follows the system; the override lives in the Settings window (⌘,).
final class AppearanceSettingsUITests: XCTestCase {
    @MainActor func testAppearanceOverrideLivesInTheSettingsWindow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.popUpButtons["Appearance"].exists, "No appearance picker in the toolbar")
        app.typeKey(",", modifierFlags: .command)
        let picker = app.popUpButtons["Appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "System")
    }
}
