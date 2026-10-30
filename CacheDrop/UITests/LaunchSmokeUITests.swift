import XCTest
import Darwin
import CacheDropCore

/// A fresh, owned state root so a launch never reads or writes the user's real app state.
/// #299: the fixture folders a UI test makes in the runner's temp folder are removed after every test, whether it passed,
/// failed or stopped early, with locked fixtures (0555 apps, 0311 or 0 folders) made writable first. The first fixture of a
/// run also removes any left over from an earlier run that are more than a day old.
@MainActor enum FixtureFolders {
    static let prefixes = ["CacheDropTestHome-", "CacheDropTestState-", "CacheDropPicked-"]
    private static var made: [URL] = []
    private static var observer: Observer?

    /// Registers a fixture folder for removal when the current test finishes.
    static func track(_ folder: URL) {
        if observer == nil {
            let new = Observer()
            XCTestObservationCenter.shared.addTestObserver(new)
            observer = new
            removeStale(in: FileManager.default.temporaryDirectory.resolvingSymlinksInPath())
        }
        made.append(folder)
    }
    static func removeMade() {
        made.forEach(remove)
        made = []
    }
    /// Fixture folders older than `age` in `temp`, from runs that ended before cleaning up.
    static func removeStale(in temp: URL, olderThan age: TimeInterval = 24 * 60 * 60) {
        let entries = (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for entry in entries where prefixes.contains(where: entry.lastPathComponent.hasPrefix) {
            guard let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  Date().timeIntervalSince(modified) > age else { continue }
            remove(entry)
        }
    }
    /// Gives the owner full access to every folder in it, never following links, then removes it.
    static func remove(_ folder: URL) {
        func unlock(_ url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return }
            chmod(url.path, (info.st_mode & 0o7777) | 0o700)
            for child in (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] { unlock(url.appendingPathComponent(child)) }
        }
        unlock(folder)
        try? FileManager.default.removeItem(at: folder)
    }

    private final class Observer: NSObject, XCTestObservation {
        func testCaseDidFinish(_ testCase: XCTestCase) {
            MainActor.assumeIsolated { FixtureFolders.removeMade() }
        }
    }
}

@MainActor func configureIsolatedState(_ app: XCUIApplication) throws -> URL {
    let token = UUID().uuidString
    let state = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropTestState-" + token)
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    FixtureFolders.track(state)
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
    /// #299: locked fixtures are unlocked and removed; only fixture folders more than a day old are swept at start. No app launch.
    @MainActor func testFixtureFoldersAreRemovedEvenWhenLockedAndOnlyStaleOnesAreSwept() throws {
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FixtureSweep-" + UUID().uuidString)
        defer { FixtureFolders.remove(temp) }
        let stale = temp.appendingPathComponent("CacheDropTestHome-" + UUID().uuidString), fresh = temp.appendingPathComponent("CacheDropTestState-" + UUID().uuidString)
        let other = temp.appendingPathComponent("Unrelated-" + UUID().uuidString)
        let app = stale.appendingPathComponent("Applications/Locked Suite.app"), folder = stale.appendingPathComponent("Library/Caches/Locked")
        for url in [app.appendingPathComponent("Contents"), folder.appendingPathComponent("inner"), fresh, other] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        chmod(app.path, 0o555); chmod(folder.path, 0o311)
        let old = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
        for url in [stale, other] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path) }

        FixtureFolders.removeStale(in: temp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "A locked fixture home more than a day old is removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "A recent one may be another run's")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "Only fixture folders")
        FixtureFolders.remove(fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
    }

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
        XCTAssertTrue(sheet.staticTexts["Your folders and app caches"].exists)
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
        XCTAssertTrue(app.staticTexts["No trends yet"].waitForExistence(timeout: 15))

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

        // #221, #351, #461: the growth card's Review link names the category that grew and opens it in the plan; it's in the
        // card, not the bottom bar, whose only button is Scan again.
        XCTAssertEqual(app.links["growthReviewOptions"].label, "Review developer caches and build files in the Cleanup plan")
        XCTAssertFalse(actionStrip(app).frame.contains(app.links["growthReviewOptions"].frame))
        XCTAssertEqual(actionStrip(app).buttons.count, 1)
        XCTAssertFalse(app.staticTexts["Review plan shows what can be cleaned there now."].exists)
        app.links["growthReviewOptions"].click()
        XCTAssertTrue(app.checkBoxes["planCategory-developer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["planCategory-developer"].isHittable, "Scrolled to the category that grew")
        // #222: the quiet back button sits above the page title, and returns to Storage trends.
        let back = app.buttons["Back to Storage trends"]
        assertBackButton(back, isAbove: "Cleanup plan", in: app)
        back.click()
        XCTAssertTrue(app.links["growthReviewOptions"].waitForExistence(timeout: 5))
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

        app.typeKey("7", modifierFlags: .command)
        let manage = app.descendants(matching: .any)["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        revealAndClick(manage, in: app)
        let back = app.buttons["Back to Locations & access"]
        assertBackButton(back, isAbove: "Saved data", in: app)
        XCTAssertTrue(actionStrip(app).exists, "The bottom bar stays, empty")
        back.click()
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
    }
}

/// #313: custom exclusions are reached from Locations & access, as its Protected items row.
final class ProtectedItemsUITests: XCTestCase {
    @MainActor func testProtectedItemsOpensExclusionsFromLocationsAndReturns() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        app.typeKey("7", modifierFlags: .command)
        let open = app.descendants(matching: .any)["openProtectedItems"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        revealAndClick(open, in: app)
        let back = app.buttons["Back to Locations & access"]
        assertBackButton(back, isAbove: "Protected items", in: app)
        XCTAssertTrue(app.buttons["chooseExclusion"].waitForExistence(timeout: 5), "The page offers adding an exclusion")
        back.click()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
    }
}

/// Overview keeps its scroll position across pages, and scrolling it never re-renders the workspace: the position is
/// remembered without being observed (Overview scroll lag, owner's smoke test 2026-10-29).
final class ScrollPositionUITests: XCTestCase {
    @MainActor func testOverviewComesBackWhereItWasScrolled() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn", "Library/Caches/pip", ".gradle/caches", "Library/Caches/CocoaPods"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        let title = app.staticTexts["Storage overview"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let top = title.frame.minY
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        let scrolled = title.frame.minY
        XCTAssertLessThan(scrolled, top - 50, "Overview scrolled")

        app.typeKey("6", modifierFlags: .command)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let back = NSPredicate { _, _ in abs(title.frame.minY - scrolled) < 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)], timeout: 5), .completed,
                       "Overview came back at \(title.frame.minY), scrolled to \(scrolled)")
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

/// #127, #141, #270: ⌘1–⌘7 follow the sidebar order, Applications just above History, and ⌘R scans again from any screen.
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

        let sidebar = ["Overview", "Smart clean", "Cleanup plan", "Storage trends", "Applications", "History", "Locations & access"]
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
        XCTAssertTrue(app.staticTexts["No trends yet"].waitForExistence(timeout: 15))
        let grown = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/cd/blob")
        try FileManager.default.createDirectory(at: grown.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 9, count: 5_000_000).write(to: grown)
        app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(app.menuBars.menuItems["Scan again"].exists, "Scan again is a menu command")
        app.typeKey("r", modifierFlags: .command)
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["growthNetChange"].waitForExistence(timeout: 15), "⌘R from History scanned again")
    }
}

/// #310: Scan again is disabled while a scan runs, on Overview and as the ⌘R menu command, never a silent no-op; it is
/// enabled again once the scan ends. Its tooltip says "A scan is already running".
final class ScanAgainUITests: XCTestCase {
    @MainActor func testScanAgainIsDisabledWhileAScanRuns() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.3"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let button = app.buttons["overviewScanAgain"], command = app.menuBars.menuBarItems["View"].menuItems["Scan again"]
        // #311: Overview's Scan again sits in the bottom bar, as on Storage trends.
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(actionStrip(app).frame.contains(button.frame), "Overview's Scan again is in the bottom bar")
        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForExistence(timeout: 10), "The launch scan is running")
        XCTAssertFalse(button.isEnabled, "Overview's Scan again waits for the running scan")
        XCTAssertFalse(command.isEnabled, "⌘R waits for the running scan")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: button)], timeout: 120), .completed)
        // The menu item's enabled state is validated separately from the button, so it may follow a moment later.
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: command)], timeout: 10), .completed, "⌘R is enabled again")
    }
}

/// #158: the welcome shows on a first launch, never again once finished, and the Help menu opens it again.
/// #310: the launch scan runs behind it from the start, so its last step shows that scan's progress and ends with Done; Full
/// Disk Access granted while that scan runs is picked up by one rescan when it ends, without CacheDrop becoming active again.
/// Other journeys never see it: disposable test runs treat it as seen unless `CACHEDROP_TEST_SHOW_WELCOME` asks for it.
final class FirstRunWelcomeUITests: XCTestCase {
    @MainActor func testWelcomeShowsTheRunningScanPicksUpAGrantAndOpensFromHelp() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        // The fixture's Safari folder refuses to open, as without Full Disk Access, until the test grants it mid-scan.
        let safari = home.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: safari.path)
        app.launchEnvironment["CACHEDROP_TEST_SHOW_WELCOME"] = "1"
        // Slow enough that the launch scan is still running at the last step.
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.4"
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
        app.buttons["welcomeContinue"].click()

        // Step 3: the launch scan is already running; there is no second scan to start.
        XCTAssertTrue(app.descendants(matching: .any)["welcomeScanProgress"].waitForExistence(timeout: 5), "The last step shows the running scan")
        XCTAssertTrue(app.sheets.staticTexts["Your first scan is running"].exists)
        XCTAssertFalse(app.buttons["welcomeStartScan"].exists)
        // Granted while the scan runs, as from step 2's System Settings link.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.buttons["welcomeDone"].click()
        XCTAssertFalse(welcome.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 5))
        // The scan that began without access ends without Safari, sees the grant and scans once more, by itself.
        let denied = app.descendants(matching: .any)["overviewNotAccessible"]
        XCTAssertTrue(denied.waitForExistence(timeout: 60), "The launch scan began without access")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: denied)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 60), .completed, "The grant during the launch scan was picked up when it ended")

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
        // A remembered fixture folder whose bookmark no longer resolves, as after the app was renamed. Not Downloads, which is
        // built in (#342).
        let folder = home.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scopes = state.appendingPathComponent("Scopes")
        try FileManager.default.createDirectory(at: scopes, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let record: [String: Any] = ["version": 1, "scopes": [["id": UUID().uuidString, "path": folder.path, "isIncluded": true,
                                                               "kind": "inspection", "bookmark": Data("stale".utf8).base64EncodedString()]]]
        try JSONSerialization.data(withJSONObject: record).write(to: scopes.appendingPathComponent("scopes-v1.json"))
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "Present but unreadable, not deleted")
        // One message for one problem: the row names the folder and the reason, and carries the fix.
        let row = app.staticTexts["overviewLocationRecovery"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.value as? String, "Projects · Access unavailable")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'can’t be reached'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'since you included it'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Choose the folder again'")).firstMatch.exists)

        let chooseAgain = app.links["overviewChooseAgain"]
        XCTAssertEqual(chooseAgain.label, "Choose again…")
        revealAndClick(chooseAgain, in: app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Remember folder"].click()

        // Renewed and scanned in place: the row is gone and the folder shows on Overview.
        waitForScannedFolder(app)
        XCTAssertFalse(row.exists)
    }

    /// #254: a scanned folder deleted since its scan says, as in the explorer, "Folder not found · last scanned <time>",
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
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)

        // Deleted, then Scan again can't find it.
        try FileManager.default.removeItem(at: folder)
        app.typeKey("r", modifierFlags: .command)
        let row = app.staticTexts["overviewLocationRecovery"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let text = row.value as? String ?? ""
        XCTAssertTrue(text.hasPrefix(folder.lastPathComponent + " · Folder not found · last scanned "), text)
        XCTAssertFalse(text.contains("Access unavailable"), text)
        XCTAssertEqual(app.links["overviewChooseAgain"].label, "Choose again…")
    }

    /// #345, #358: a scanned folder is a row in Overview's Scanned locations group, under the recommended categories, with its
    /// size and an Explore link; a subfolder it couldn't read gives that row its own reason and Full Disk Access, and the generic
    /// "couldn't be read in full" line is gone.
    @MainActor func testAScannedFolderIsARowWithItsOwnReasonAndExploreLink() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        let locked = folder.appendingPathComponent("Locked")
        // Removed when the test ends, locked subfolder and all, and swept after a killed run (`FixtureFolders`).
        FixtureFolders.track(folder)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("entry.zip"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        // Downloads is built in (#342): listed and scanned with no picking, and says so.
        let downloads = element(identifier: "overviewLocation:" + home.appendingPathComponent("Downloads").path, in: app)
        XCTAssertTrue(downloads.waitForExistence(timeout: 20))
        XCTAssertTrue((downloads.value as? String ?? "").contains("Built in"), downloads.value as? String ?? "")
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)

        let row = element(identifier: "overviewLocation:" + folder.path, in: app)
        XCTAssertTrue((row.value as? String ?? "").contains(folder.lastPathComponent), row.value as? String ?? "")
        let problem = element(identifier: "overviewLocationProblem:" + folder.path, in: app)
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertEqual(problem.value as? String, "1 folder couldn’t be read")
        XCTAssertEqual(app.links["fullDiskAccessLink"].label, "Grant Full Disk Access")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'couldn’t be read in full'")).firstMatch.exists)

        // The row is one button, labelled for what it does (#358).
        revealAndClick(app.buttons["Explore " + folder.lastPathComponent], in: app)
        // The explorer's own action; its mode toggle shows only once large or old files were found, and this folder has none.
        XCTAssertTrue(app.buttons["Add to cleanup plan"].waitForExistence(timeout: 10), "Explore opens the explorer at that folder")
    }

    /// #231: two stale folders get a row each, each with its own Choose again…, and no grey "Scanned now" row.
    @MainActor func testTwoStaleFoldersShowARowEach() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let projects = home.appendingPathComponent("Projects"), work = home.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let scopes = state.appendingPathComponent("Scopes")
        try FileManager.default.createDirectory(at: scopes, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let stale = Data("stale".utf8).base64EncodedString()
        let record: [String: Any] = ["version": 1, "scopes": [
            ["id": UUID().uuidString, "path": home.appendingPathComponent("Downloads").path, "isIncluded": true, "kind": "downloads", "bookmark": stale],
            ["id": UUID().uuidString, "path": projects.path, "isIncluded": true, "kind": "inspection", "bookmark": stale],
            ["id": UUID().uuidString, "path": work.path, "isIncluded": true, "kind": "inspection", "bookmark": stale]]]
        try JSONSerialization.data(withJSONObject: record).write(to: scopes.appendingPathComponent("scopes-v1.json"))
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        let rows = app.staticTexts.matching(identifier: "overviewLocationRecovery")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        let texts = Set(rows.allElementsBoundByIndex.compactMap { $0.value as? String })
        // #342: a Downloads picked in an earlier version is quietly forgotten; the built-in one replaces it, with no row.
        XCTAssertEqual(texts, ["Projects · Access unavailable", "Work · Access unavailable"])
        XCTAssertEqual(app.links.matching(identifier: "overviewChooseAgain").count, 2)
        XCTAssertTrue(element(identifier: "overviewLocation:" + home.appendingPathComponent("Downloads").path, in: app).waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'can’t be reached'")).firstMatch.exists)
    }
}

/// #309: an interrupted cleanup is checked against disk when Recovery opens, then marked reviewed. Launch stays on Overview.
final class RecoveryReviewUITests: XCTestCase {
    /// A pending record for `file`, as a run claims it, then `state`, as a run left it.
    private func record(_ file: URL, batch: UUID, state: String) throws -> CleanupRecord {
        var info = stat(), folder = stat()
        guard lstat(file.path, &info) == 0, lstat(file.deletingLastPathComponent().path, &folder) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let json: [String: Any] = [
            "id": batch.uuidString + "|" + file.path, "batchID": batch.uuidString, "originalURL": file.absoluteString, "resourceID": "\(info.st_dev):\(info.st_ino)",
            "logicalBytes": 3, "state": state, "message": "Started; outcome not yet recorded", "observedAt": 0, "approvedAt": 0,
            "scopeURL": file.deletingLastPathComponent().absoluteString, "scopeResourceID": "\(folder.st_dev):\(folder.st_ino)",
            "modifiedSeconds": Int64(info.st_mtimespec.tv_sec), "modifiedNanoseconds": Int64(info.st_mtimespec.tv_nsec),
            "action": "moveToTrash", "policyVersion": 2, "ruleID": "downloads-installers",
        ]
        return try JSONDecoder().decode(CleanupRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @MainActor func testInterruptedCleanupIsCheckedAgainstDiskAndMarkedReviewed() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropTestHome-" + UUID().uuidString)
        FixtureFolders.track(home)
        let downloads = home.appendingPathComponent("Downloads"), trash = home.appendingPathComponent(".Trash")
        for folder in [downloads, trash] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let files = ["Kept.dmg", "Trashed.dmg", "Gone.dmg"].map { downloads.appendingPathComponent($0) }
        for file in files { try Data([1, 2, 3]).write(to: file) }
        let batch = UUID()
        let records = try files.map { try record($0, batch: batch, state: "intent") }
        let journal = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"))
        XCTAssertTrue(try journal.claim(batchID: batch, records: records))
        // The run quit after starting each item: one stayed, one reached the Trash, one is gone.
        try FileManager.default.moveItem(at: files[1], to: trash.appendingPathComponent("Trashed.dmg"))
        try FileManager.default.removeItem(at: files[2])
        app.launchEnvironment["CACHEDROP_TEST_CATALOG_HOME"] = home.path
        defer { app.terminate() }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10), "Launch opens on Overview, never on Recovery")
        let review = app.buttons["Review interrupted cleanup"]
        XCTAssertTrue(review.waitForExistence(timeout: 10), "Overview shows the interrupted cleanup banner")
        review.click()
        let expected = ["Kept.dmg": "Not removed", "Trashed.dmg": "Moved to Trash", "Gone.dmg": "Removed"]
        for (name, title) in expected {
            let row = app.staticTexts["recoveryState-" + name]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) shows its finding")
            XCTAssertTrue((row.value as? String ?? row.label).hasPrefix(title + " · "), "\(name): \(row.value ?? row.label)")
        }
        // #436: the page says once that nothing restarts, in its subtitle; its bottom bar has no note.
        let restarts = NSPredicate(format: "label CONTAINS 'Nothing restarts by itself' OR value CONTAINS 'Nothing restarts by itself'")
        XCTAssertEqual(app.staticTexts.matching(restarts).count, 1)
        XCTAssertEqual(actionStrip(app).staticTexts.matching(restarts).count, 0)
        app.buttons["recoveryMarkReviewed"].click()
        XCTAssertTrue(app.staticTexts["recoveryMessage"].waitForExistence(timeout: 10))

        // The banner is gone, and the journal holds the reviewed records beside the unchanged originals.
        app.buttons["Overview"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Review interrupted cleanup"].exists)
        let reader = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"), readOnly: true)
        XCTAssertTrue(try CleanupRecoverySnapshot(journal: reader).interruptedBatches.isEmpty)
        XCTAssertEqual(try reader.records().filter { $0.reviewOf == nil }.map(\.state), [.intent, .intent, .intent])
        XCTAssertEqual(try reader.completedHistory().completedRuns.first?.records.map(\.outcomeTitle), ["Not removed", "Moved to Trash", "Removed"])
    }
}
