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
        XCTAssertTrue(app.staticTexts["Storage trends"].exists || app.buttons["Storage trends"].exists, "Storage trends is in the sidebar (#119, #127)")
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

        app.buttons["Storage trends"].click()
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
        XCTAssertTrue(app.buttons["Back to Storage trends"].waitForExistence(timeout: 5))
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

/// #127: ⌘1–⌘5 follow the sidebar order, and ⌘R scans again from any screen.
final class KeyboardShortcutsUITests: XCTestCase {
    @MainActor func testShortcutsFollowTheSidebarAndCommandRScansAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        let sidebar = ["Overview", "Cleanup plan", "Storage trends", "History", "Locations & access"]
        let rows = sidebar.map { app.buttons[$0].frame.minY }
        XCTAssertEqual(rows, rows.sorted(), "The sidebar lists \(sidebar.joined(separator: ", ")) from the top")
        for (index, title) in sidebar.enumerated().reversed() {
            app.typeKey(String(index + 1), modifierFlags: .command)
            let row = app.buttons[title]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let selected = NSPredicate(format: "isSelected == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: row)], timeout: 5), .completed, "⌘\(index + 1) opens \(title)")
        }

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Baseline recorded"].waitForExistence(timeout: 15))
        let grown = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/cd/blob")
        try FileManager.default.createDirectory(at: grown.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 9, count: 5_000_000).write(to: grown)
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.menuBars.menuItems["Scan again"].exists, "Scan again is a menu command")
        app.typeKey("r", modifierFlags: .command)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 15), "⌘R from History scanned again")
    }
}
