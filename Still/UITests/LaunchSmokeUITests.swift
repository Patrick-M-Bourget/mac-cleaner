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
        // #149: the app is CacheDrop, in the window title and the sidebar header.
        XCTAssertEqual(app.windows.firstMatch.title, "CacheDrop")
        XCTAssertTrue(app.staticTexts["CacheDrop"].exists, "The sidebar header names CacheDrop")
        XCTAssertFalse(app.staticTexts["Still"].exists)
    }

    /// #156: the standard About panel shows the app icon, CacheDrop, its version and its build.
    @MainActor func testAboutPanelShowsIconNameVersionAndBuild() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["CacheDrop"].click()
        app.menuItems["About CacheDrop"].click()
        let version = NSPredicate(format: "value MATCHES %@ OR label MATCHES %@", "^Version [0-9.]+ \\([0-9]+\\)$", "^Version [0-9.]+ \\([0-9]+\\)$")
        let line = app.staticTexts.matching(version).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5), "The About panel shows Version x (build)")
        let panel = app.windows.allElementsBoundByIndex.first { $0.staticTexts.matching(version).firstMatch.exists }
        let about = try XCTUnwrap(panel, "The version line is in its own panel")
        XCTAssertTrue(about.staticTexts["CacheDrop"].exists, "The About panel names CacheDrop")
        XCTAssertTrue(about.images.firstMatch.exists, "The About panel shows the app icon")
    }

    /// #131: the menu bar item shows free space and keeps CacheDrop running after its window closes.
    /// Low-space alerts are off by default, in the Settings window. Nothing here changes either preference.
    @MainActor func testMenuBarItemShowsFreeSpaceAndAlertsStartOff() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertTrue(NSPredicate(format: "SELF MATCHES %@", "^[0-9.,]+ (GB|TB) free$").evaluate(with: item.title), "Got \(item.title)")

        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(app.staticTexts["Storage overview"].waitForExistence(timeout: 2))
        // The menu is checked, not clicked: on a crowded menu bar (the notch, or a menu bar manager) the item can be
        // hidden, and XCUITest can't open it. Open CacheDrop from the menu is a hand smoke test.
        for title in ["Open CacheDrop", "Scan again", "Settings…", "Quit CacheDrop"] { XCTAssertTrue(app.menuItems[title].exists, title) }
        XCTAssertEqual(app.state, .runningForeground, "Closing the window keeps CacheDrop running with its menu bar item")

        app.typeKey(",", modifierFlags: .command)
        let alerts = app.descendants(matching: .any)["lowSpaceAlertsToggle"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 5))
        XCTAssertEqual(alerts.value as? Int, 0, "Alerts are off by default")
        XCTAssertEqual(app.descendants(matching: .any)["menuBarItemToggle"].value as? Int, 1, "The menu bar item is shown by default")
        XCTAssertFalse(app.descendants(matching: .any)["lowSpaceThreshold"].exists, "The threshold appears only once alerts are on")
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
        // Over XCUITest's 128-character subscript limit, so matched by label.
        let readOnly = "CacheDrop’s scans stay read-only. Nothing protected becomes eligible for cleanup, and CacheDrop only changes what you choose and review."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", readOnly, readOnly)).firstMatch.exists)
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

/// #119: the first catalog scan records a baseline; a later one shows growth per category and location.
/// #126: a scan minutes after the baseline waits for a day-old one ("Check back tomorrow").
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

        func grow(_ name: String) throws {
            let grown = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/" + name + "/blob")
            try FileManager.default.createDirectory(at: grown.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 9, count: 5_000_000).write(to: grown)
        }
        try grow("cd")
        app.buttons["growthScanAgain"].click()
        let checkBack = app.staticTexts["Check back tomorrow to see trends."]
        XCTAssertTrue(checkBack.waitForExistence(timeout: 15), "A scan minutes after the baseline isn't compared")
        XCTAssertFalse(app.staticTexts["growthNetChange"].exists)

        // A day later (the test shortens the baseline age), the launch scan compares with the earlier one.
        app.terminate()
        try grow("ef")
        app.launchEnvironment["STILL_TEST_TRENDS_BASELINE_AGE"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.buttons["Storage trends"].click()
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

/// #127, #141: ⌘1–⌘6 follow the sidebar order, and ⌘R scans again from any screen.
final class KeyboardShortcutsUITests: XCTestCase {
    @MainActor func testShortcutsFollowTheSidebarAndCommandRScansAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["STILL_TEST_TRENDS_BASELINE_AGE"] = "0"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        let sidebar = ["Overview", "Smart clean", "Cleanup plan", "Storage trends", "History", "Locations & access"]
        let rows = sidebar.map { app.buttons[$0].frame.minY }
        XCTAssertEqual(rows, rows.sorted(), "The sidebar lists \(sidebar.joined(separator: ", ")) from the top")
        for (index, title) in sidebar.enumerated().reversed() {
            app.typeKey(String(index + 1), modifierFlags: .command)
            let row = app.buttons[title]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let selected = NSPredicate(format: "isSelected == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: row)], timeout: 5), .completed, "⌘\(index + 1) opens \(title)")
        }

        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Baseline recorded"].waitForExistence(timeout: 15))
        let grown = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/cd/blob")
        try FileManager.default.createDirectory(at: grown.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 9, count: 5_000_000).write(to: grown)
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.menuBars.menuItems["Scan again"].exists, "Scan again is a menu command")
        app.typeKey("r", modifierFlags: .command)
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 15), "⌘R from History scanned again")
    }
}
