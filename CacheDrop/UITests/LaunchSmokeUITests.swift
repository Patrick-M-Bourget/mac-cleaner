import XCTest
import Darwin

/// A fresh, owned state root so a launch never reads or writes the user's real app state.
@MainActor func configureIsolatedState(_ app: XCUIApplication) throws -> URL {
    let token = UUID().uuidString
    let state = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropTestState-" + token)
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let marker = state.appendingPathComponent(".cachedrop-owned-test-state")
    try Data(token.utf8).write(to: marker)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    var info = stat()
    guard lstat(state.path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
    app.launchEnvironment["CACHEDROP_TEST_STATE_ROOT"] = state.path
    app.launchEnvironment["CACHEDROP_TEST_STATE_ID"] = "\(info.st_dev):\(info.st_ino)"
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
        // #149, #162: the app is CacheDrop. The sidebar header shows the name; the window keeps it as its title for
        // accessibility and the Window menu, but the title bar doesn't show it again.
        XCTAssertEqual(app.windows.firstMatch.title, "CacheDrop")
        XCTAssertTrue(app.staticTexts["CacheDrop"].exists, "The sidebar header names CacheDrop")
        XCTAssertEqual(app.windows.firstMatch.staticTexts.matching(NSPredicate(format: "value == 'CacheDrop' OR label == 'CacheDrop'")).count, 1,
                       "Only the sidebar header shows CacheDrop, not the title bar")
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
        // The sidebar header already names CacheDrop, so the panel shows up as one more name and one more image.
        let names = app.staticTexts.matching(NSPredicate(format: "value == 'CacheDrop' OR label == 'CacheDrop'"))
        let namesBefore = names.count, imagesBefore = app.images.count
        app.menuBars.menuBarItems["CacheDrop"].click()
        app.menuItems["About CacheDrop"].click()
        let version = NSPredicate(format: "value MATCHES %@ OR label MATCHES %@", "^Version [0-9.]+ \\([0-9]+\\)$", "^Version [0-9.]+ \\([0-9]+\\)$")
        XCTAssertTrue(app.staticTexts.matching(version).firstMatch.waitForExistence(timeout: 5), "The About panel shows Version x (build)")
        XCTAssertGreaterThan(names.count, namesBefore, "The About panel names CacheDrop")
        XCTAssertGreaterThan(app.images.count, imagesBefore, "The About panel shows the app icon")
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

        // #161: the calm sheet: title, two-line explanation, coverage table, one note, two buttons.
        revealAndClick(app.links["fullDiskAccessLink"].firstMatch, in: app)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Broader access is optional"].waitForExistence(timeout: 5))
        let summary = sheet.staticTexts["fullDiskAccessSummary"]
        XCTAssertTrue((summary.value as? String ?? summary.label).contains("It’s broad authority, not read-only. CacheDrop’s scans stay read-only either way."))
        XCTAssertTrue(sheet.staticTexts["Your folders and known locations"].exists)
        let protected = sheet.staticTexts["fullDiskAccessSheetStatus"]
        XCTAssertEqual(protected.value as? String ?? protected.label, "Not included")
        let howTo = sheet.staticTexts["fullDiskAccessHowTo"]
        XCTAssertTrue((howTo.value as? String ?? howTo.label).contains("Privacy & Security › Full Disk Access"))
        XCTAssertEqual(sheet.buttons["closeFullDiskAccess"].label, "Not now")
        XCTAssertTrue(sheet.buttons["openFullDiskAccessSettings"].isHittable) // Not pressed: tests never open System Settings.
        XCTAssertFalse(sheet.buttons["Check again"].exists, "Coming back rescans by itself (#124)")
        sheet.buttons["dismissFullDiskAccess"].click()
        XCTAssertFalse(sheet.staticTexts["Broader access is optional"].waitForExistence(timeout: 2))

        // Granted: the same sheet shows a single Done. The fixture's Safari folder opening stands in for the grant.
        app.terminate()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.launch()
        app.buttons["Locations & access"].click()
        XCTAssertTrue(app.staticTexts["fullDiskAccessStatus"].waitForExistence(timeout: 5))
        revealAndClick(app.links["fullDiskAccessLink"].firstMatch, in: app)
        let done = sheet.buttons["closeFullDiskAccess"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Done'"), object: done)], timeout: 10), .completed)
        XCTAssertFalse(sheet.buttons["openFullDiskAccessSettings"].exists)
        XCTAssertEqual(protected.value as? String ?? protected.label, "Included")
        XCTAssertFalse(sheet.staticTexts["fullDiskAccessHowTo"].exists)
        done.click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
    }

    /// #124: Full Disk Access granted while CacheDrop was away: coming back rescans once, and the "needs Full Disk Access"
    /// line goes away without Scan again. The fixture's Safari folder opening again stands in for the grant.
    @MainActor func testGrantingFullDiskAccessRescansWhenCacheDropBecomesActive() throws {
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
        app.launchEnvironment["CACHEDROP_TEST_TRENDS_BASELINE_AGE"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.buttons["Storage trends"].click()
        XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 15))
        // Each change row reads as one element: its title, the rules that grew and the change.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Developer caches and build files'")).firstMatch.exists)

        app.radioButtons["Locations"].firstMatch.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '~/.npm/_cacache'")).firstMatch.waitForExistence(timeout: 5))

        // #221: the button names where it goes.
        XCTAssertEqual(app.buttons["growthReviewOptions"].label, "Review plan")
        app.buttons["growthReviewOptions"].click()
        // #222: the quiet back button sits above the page title, and returns to Storage trends.
        let back = app.buttons["Back to Storage trends"]
        assertBackButton(back, isAbove: "Cleanup plan", in: app)
        back.click()
        XCTAssertTrue(app.buttons["growthReviewOptions"].waitForExistence(timeout: 5))
    }
}

/// #222: a page reached from another keeps its back button above the title; its bottom bar stays, without it.
final class BackButtonUITests: XCTestCase {
    @MainActor func testLocalRecordsBackButtonSitsAboveTheTitleAndReturns() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        app.typeKey("6", modifierFlags: .command)
        let manage = app.buttons["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        revealAndClick(manage, in: app)
        let back = app.buttons["Back to Locations & access"]
        assertBackButton(back, isAbove: "Local records", in: app)
        XCTAssertTrue(actionStrip(app).exists, "The bottom bar stays, empty")
        back.click()
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
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

/// #127, #141, #267: ⌘1–⌘7 follow the sidebar order, Applications last, and ⌘R scans again from any screen.
final class KeyboardShortcutsUITests: XCTestCase {
    @MainActor func testShortcutsFollowTheSidebarAndCommandRScansAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_TRENDS_BASELINE_AGE"] = "0"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        let sidebar = ["Overview", "Smart clean", "Cleanup plan", "Storage trends", "History", "Locations & access", "Applications"]
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

/// #158: the welcome shows on a first launch, never again once finished, and the Help menu opens it again.
/// Other journeys never see it: disposable test runs treat it as seen unless `CACHEDROP_TEST_SHOW_WELCOME` asks for it.
final class FirstRunWelcomeUITests: XCTestCase {
    @MainActor func testWelcomeShowsOnceStartsTheScanAndOpensFromHelp() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        // The fixture's Safari folder refuses to open, as without Full Disk Access; opening it before step 3 shows
        // that Start scan scanned again.
        let safari = home.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: safari.path)
        app.launchEnvironment["CACHEDROP_TEST_SHOW_WELCOME"] = "1"
        defer {
            app.terminate(); try? FileManager.default.removeItem(at: state)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path); try? FileManager.default.removeItem(at: home)
        }
        app.launch()
        let welcome = app.sheets.staticTexts["Welcome to CacheDrop"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10), "A first launch shows the welcome")
        XCTAssertTrue(app.staticTexts["welcomeNeverTouches"].exists)
        app.buttons["welcomeContinue"].click()

        // Step 2 is the shared Full Disk Access explanation.
        XCTAssertTrue(app.sheets.staticTexts["Broader access is optional"].waitForExistence(timeout: 5))
        app.sheets.links["fullDiskAccessLink"].firstMatch.click()
        XCTAssertTrue(app.buttons["openFullDiskAccessSettings"].waitForExistence(timeout: 5)) // Not pressed: tests never open System Settings.
        app.buttons["closeFullDiskAccess"].click()
        XCTAssertFalse(app.buttons["openFullDiskAccessSettings"].waitForExistence(timeout: 2))

        let denied = app.descendants(matching: .any)["overviewNotAccessible"]
        XCTAssertTrue(denied.waitForExistence(timeout: 15), "The launch scan finished without Safari")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.buttons["welcomeContinue"].click()
        app.buttons["welcomeStartScan"].click()
        XCTAssertFalse(welcome.waitForExistence(timeout: 2))
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: denied)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed, "Start scan scanned again")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertFalse(welcome.waitForExistence(timeout: 3), "Finished, it never shows again")

        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Welcome to CacheDrop"].click()
        XCTAssertTrue(welcome.waitForExistence(timeout: 5), "The Help menu opens it again")
        app.buttons["welcomeSkip"].click()
        XCTAssertFalse(welcome.waitForExistence(timeout: 2))
    }
}

/// #223: a remembered folder whose access went stale shows one row on Overview, and its Choose again… fixes it there.
final class ScannedLocationsUITests: XCTestCase {
    /// #254: the folder is still there but can't be read, so the row says "Access unavailable", not "Folder not found".
    @MainActor func testAStaleFolderShowsOneRowAndChooseAgainRenewsIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // A remembered fixture Downloads folder whose bookmark no longer resolves, as after the app was renamed.
        let folder = home.appendingPathComponent("Downloads")
        let scopes = state.appendingPathComponent("Scopes")
        try FileManager.default.createDirectory(at: scopes, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let record: [String: Any] = ["version": 1, "scopes": [["id": UUID().uuidString, "path": folder.path, "isIncluded": true,
                                                               "kind": "downloads", "bookmark": Data("stale".utf8).base64EncodedString()]]]
        try JSONSerialization.data(withJSONObject: record).write(to: scopes.appendingPathComponent("scopes-v1.json"))
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "Present but unreadable, not deleted")
        // One message for one problem: the row names the folder and the reason, and carries the fix.
        let row = app.staticTexts["overviewLocationRecovery"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.value as? String, "Downloads · Access unavailable")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Current coverage'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Recheck required'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Choose again to renew'")).firstMatch.exists)

        let chooseAgain = app.buttons["overviewChooseAgain"]
        XCTAssertEqual(chooseAgain.label, "Choose again…")
        revealAndClick(chooseAgain, in: app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Remember folder"].click()

        // Renewed and scanned in place: the row is gone and the folder can be explored.
        XCTAssertTrue(app.links["Explore storage"].waitForExistence(timeout: 20))
        XCTAssertFalse(row.exists)
    }

    /// #254: a scanned folder deleted since its scan says, as in the explorer, "Folder not found · last observed <time>",
    /// with Choose again…, rather than "Access unavailable".
    @MainActor func testADeletedFolderSaysFolderNotFoundWithItsLastObservation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("entry.zip"))
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.buttons["overviewScanFolder"].click()
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        XCTAssertTrue(app.links["Explore storage"].waitForExistence(timeout: 20))

        // Deleted, then Scan again can't find it.
        try FileManager.default.removeItem(at: folder)
        app.typeKey("r", modifierFlags: .command)
        let row = app.staticTexts["overviewLocationRecovery"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let text = row.value as? String ?? ""
        XCTAssertTrue(text.hasPrefix(folder.lastPathComponent + " · Folder not found · last observed "), text)
        XCTAssertFalse(text.contains("Access unavailable"), text)
        XCTAssertEqual(app.buttons["overviewChooseAgain"].label, "Choose again…")
    }

    /// #231: two stale folders get a row each, each with its own Choose again…, and no grey "Current coverage" row.
    @MainActor func testTwoStaleFoldersShowARowEach() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let projects = home.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let scopes = state.appendingPathComponent("Scopes")
        try FileManager.default.createDirectory(at: scopes, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let stale = Data("stale".utf8).base64EncodedString()
        let record: [String: Any] = ["version": 1, "scopes": [
            ["id": UUID().uuidString, "path": home.appendingPathComponent("Downloads").path, "isIncluded": true, "kind": "downloads", "bookmark": stale],
            ["id": UUID().uuidString, "path": projects.path, "isIncluded": true, "kind": "inspection", "bookmark": stale]]]
        try JSONSerialization.data(withJSONObject: record).write(to: scopes.appendingPathComponent("scopes-v1.json"))
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        let rows = app.staticTexts.matching(identifier: "overviewLocationRecovery")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        let texts = Set(rows.allElementsBoundByIndex.compactMap { $0.value as? String })
        XCTAssertEqual(texts, ["Downloads · Access unavailable", "Projects · Access unavailable"])
        XCTAssertEqual(app.buttons.matching(identifier: "overviewChooseAgain").count, 2)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Current coverage'")).firstMatch.exists)
    }
}
