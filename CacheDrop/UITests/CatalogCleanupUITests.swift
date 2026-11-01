import XCTest

/// A fixture home with an npm cache and a Downloads installer, inside the runner's temp folder. The app reads it only through
/// the DEBUG-only CACHEDROP_TEST_CATALOG_HOME seam, so the journey never touches real user paths.
@MainActor func configureCatalogHome(_ app: XCUIApplication) throws -> URL {
    let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropTestHome-" + UUID().uuidString)
    FixtureFolders.track(home)
    let file = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/ab/blob")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: 200_000).write(to: file)
    let installer = home.appendingPathComponent("Downloads/Setup.dmg")
    try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: 120_000).write(to: installer)
    app.launchEnvironment["CACHEDROP_TEST_CATALOG_HOME"] = home.path
    return home
}

/// Turns on the Settings dry run for this launch through the DEBUG-only test seam, for journeys that assert nothing changed.
@MainActor func turnOnDryRun(_ app: XCUIApplication) {
    app.launchEnvironment["CACHEDROP_TEST_DRY_RUN"] = "1"
}

/// #255: waits, on Overview, for the launch's catalog scan to finish rather than for a fixed time, so a slow cold launch
/// can't fail a journey. The scan has started once Overview's total is measured, and finished once the bottom bar's
/// progress line is gone; checking both means a scan that has not started yet never counts as done.
@MainActor func waitForCatalogScan(_ app: XCUIApplication, timeout: TimeInterval = 120, file: StaticString = #filePath, line: UInt = #line) {
    let measured = NSPredicate(format: "exists == true AND NOT (value IN %@)", ["—"])
    let total = app.staticTexts["overviewRecommendedTotal"]
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: measured, object: total)], timeout: timeout), .completed,
                   "The catalog scan measured the known locations", file: file, line: line)
    XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForNonExistence(timeout: timeout), "The catalog scan finished", file: file, line: line)
}

/// #320: Overview's Explore storage link is always there, so a journey waits for the scanned folder to show in Overview's
/// Scanned locations group (#345), with its size rather than "Not scanned", before it uses the link to open the explorer, which
/// with no scanned folder opens Locations.
@MainActor func waitForScannedFolder(_ app: XCUIApplication, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
    // Built-in Downloads (#342) is scanned at launch on its own, so it never counts as the folder a journey picked.
    let scanned = NSPredicate(format: "identifier BEGINSWITH 'overviewLocation:' AND NOT (identifier ENDSWITH '/Downloads') AND NOT (value CONTAINS 'Not scanned')")
    XCTAssertTrue(app.descendants(matching: .any).matching(scanned).firstMatch.waitForExistence(timeout: timeout),
                  "Overview shows the scanned folder", file: file, line: line)
}

/// The explorer's quiet Large and old files toggle (#320), a text link.
@MainActor func explorerMode(_ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["explorerMode"]
}

/// The review sheet has two buttons, Cancel and Clean up, and no preview mode. Its footer is right-aligned, Cancel then
/// Clean up (#311).
@MainActor func cleanUpFromReview(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let footer = app.descendants(matching: .any).matching(identifier: "sheetFooter").firstMatch
    XCTAssertTrue(footer.waitForExistence(timeout: 5), "The review sheet has the one sheet footer", file: file, line: line)
    let cancel = footer.buttons["Cancel"], cleanUp = footer.buttons["Clean up"]
    XCTAssertTrue(cancel.exists, file: file, line: line)
    XCTAssertFalse(app.buttons["Run preview"].exists, file: file, line: line)
    XCTAssertLessThan(cancel.frame.maxX, cleanUp.frame.minX, "Cancel comes before Clean up", file: file, line: line)
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(sheet.exists, "The review is a sheet", file: file, line: line)
    XCTAssertGreaterThan(cancel.frame.minX, sheet.frame.midX, "The footer's buttons are right-aligned", file: file, line: line)
    // The sheet opens at the click; Clean up is available once its checks finish (#463).
    let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: cleanUp)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, "The review's checks finished", file: file, line: line)
    cleanUp.click()
}

/// Writes an executable stand-in tool into the fixture home's `.cachedrop-test-tools`. The sandboxed runner quarantines every
/// file it writes and can't clear that; the app clears it on stand-ins it finds there (debug test seam), so they can run.
@MainActor func writeStandInTool(_ script: String, to tool: URL) throws {
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try script.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
}

/// Adds developer caches and a stand-in `brew` that would leave a marker if it ever ran a cleanup. Asked `brew --cache`
/// at discovery (#170), it names the usual folder and leaves no marker.
@MainActor func addDeveloperCaches(_ home: URL, folders: [String]) throws -> URL {
    for folder in folders {
        let file = home.appendingPathComponent(folder + "/entry")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 50_000).write(to: file)
    }
    let marker = home.appendingPathComponent("brew-ran")
    let brew = home.appendingPathComponent(".cachedrop-test-tools/brew")
    try writeStandInTool("#!/bin/sh\n[ \"$*\" = --cache ] && { echo '\(home.path)/Library/Caches/Homebrew'; exit 0; }\ntouch '\(marker.path)'\n", to: brew)
    return marker
}

/// Writes an installer receipt under the fixture home's `var/db/receipts`, installed at `/` (so under the home, which stands in
/// for the system root in a test run), listing `paths`: its plist, and a BOM `mkbom` builds from a skeleton of those paths.
@MainActor func writeFixtureReceipt(_ id: String, listing paths: [String], in home: URL) throws {
    let receipts = home.appendingPathComponent("var/db/receipts")
    try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(fromPropertyList: ["PackageIdentifier": id, "InstallPrefixPath": "/"], format: .xml, options: 0)
    try plist.write(to: receipts.appendingPathComponent(id + ".plist"))
    let skeleton = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropReceipt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: skeleton) }
    for path in paths {
        let url = skeleton.appendingPathComponent(path)
        if url.pathExtension == "app" { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); continue }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }
    let mkbom = Process()
    mkbom.executableURL = URL(fileURLWithPath: "/usr/bin/mkbom")
    mkbom.arguments = [skeleton.path, receipts.appendingPathComponent(id + ".bom").path]
    try mkbom.run(); mkbom.waitUntilExit()
    XCTAssertEqual(mkbom.terminationStatus, 0, "mkbom built the receipt's BOM")
}

/// Scrolls `element` fully into view before a click. CacheDrop's window may open at its 900×640 minimum (the saved frame is
/// shared with the user's own runs). Overview rows and plan rules then sit below the visible area or on the window's bottom
/// resize edge, where a synthesized click does nothing. `nearTop` leaves room below it, e.g. for a disclosure group's
/// lazily drawn items.
@MainActor func reveal(_ element: XCUIElement, in app: XCUIApplication, nearTop: Bool = false) {
    guard element.waitForExistence(timeout: 5) else { return }
    // The innermost scroll view across the element: a sheet's is narrower than the page's.
    let views = app.scrollViews.allElementsBoundByIndex.filter { $0.frame.minX <= element.frame.midX && element.frame.midX <= $0.frame.maxX }
    guard let scroll = views.min(by: { $0.frame.width < $1.frame.width }) else { return }
    var step: CGFloat = -60, stalled = 0
    for _ in 0..<60 {
        let visible = scroll.frame.insetBy(dx: 0, dy: 24), frame = element.frame
        let inView = frame.minY >= visible.minY && frame.maxY <= visible.maxY
        if inView && (!nearTop || frame.minY <= visible.minY + 120) { return }
        let down = frame.maxY > visible.maxY || (nearTop && frame.minY > visible.minY + 120)
        let before = frame.midY
        scroll.scroll(byDeltaX: 0, deltaY: down ? step : -step)
        let moved = element.frame.midY - before
        if moved == 0 { stalled += 1; if stalled > 2 { return } } else { stalled = 0 }
        // Content must move up when scrolling down; flip the wheel direction if it moved the other way.
        if (down && moved > 0) || (!down && moved < 0) { step = -step }
    }
}

/// Reveals and clicks an element inside a scrolling page.
/// Overview's Scan a folder link: it waits while a folder scan runs (Downloads is scanned at launch, Decision 83) and sits
/// below the categories (#345), so wait for it to be enabled and scroll to it before clicking.
@MainActor func chooseFolderToScan(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let link = app.links["overviewScanFolder"]
    let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: link)
    XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 30), .completed, "Scan a folder stayed disabled", file: file, line: line)
    revealAndClick(link, in: app)
}

/// An element by an identifier longer than XCUITest's 128-character limit for identifier queries: a fixture folder's
/// path makes `overviewLocation:` identifiers that long.
@MainActor func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
}

@MainActor func revealAndClick(_ element: XCUIElement, in app: XCUIApplication) {
    reveal(element, in: app)
    element.click()
}

/// #349: ticks a checkbox the journey wants chosen. Recommended items arrive ticked, and whether one is recommended can
/// depend on what runs on this Mac (an owner running leaves it out), so a plain click could untick it instead.
@MainActor func tick(_ box: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    if box.value as? Int != 1 { revealAndClick(box, in: app) }
    XCTAssertEqual(box.value as? Int, 1, box.identifier, file: file, line: line)
}

/// Reveals and opens a disclosure group, then waits until it reports open. A synthesized click on a sheet is sometimes
/// routed to the window behind it: macOS shakes the sheet and the group stays closed (#152), so a rejected click is retried.
@MainActor func openDisclosure(_ triangle: XCUIElement, in app: XCUIApplication) {
    reveal(triangle, in: app)
    let open = NSPredicate(format: "value == 1")
    for _ in 0..<3 where (triangle.value as? Int) != 1 {
        triangle.click()
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: open, object: triangle)], timeout: 2)
    }
    XCTAssertEqual(triangle.value as? Int, 1, "\(triangle.label) opened")
}

/// The window's bottom bar (#220); every screen has exactly one.
@MainActor func actionStrip(_ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "actionStrip").firstMatch
}

/// Decision 47: a back button sits just above its page's title, never in the bottom bar.
@MainActor func assertBackButton(_ back: XCUIElement, isAbove title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button exists", file: file, line: line)
    let frame = back.frame
    let titles = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", title, title)).allElementsBoundByIndex
    XCTAssertTrue(titles.contains { abs($0.frame.minX - frame.minX) < 20 && $0.frame.minY >= frame.maxY - 1 && $0.frame.minY - frame.maxY < 40 },
                  "\(back.label) sits above \(title)", file: file, line: line)
    XCTAssertFalse(actionStrip(app).frame.intersects(frame), "\(back.label) is not in the bottom bar", file: file, line: line)
}

/// The review sheet's line for a catalog category in a consequence group, e.g. `reviewLine(app, "permanentlyRemoved", "developer")`.
@MainActor func reviewLine(_ app: XCUIApplication, _ group: String, _ category: String) -> XCUIElement {
    app.descendants(matching: .any)["reviewLine-\(group)-\(category)"]
}

/// Expands every collapsed disclosure group in the plan, so items a rule found one by one are drawn.
@MainActor func expandDisclosures(in app: XCUIApplication) {
    for triangle in app.disclosureTriangles.allElementsBoundByIndex where triangle.exists && (triangle.value as? Int) != 1 {
        reveal(triangle, in: app, nearTop: true)
        triangle.click()
    }
}

final class CatalogCleanupUITests: XCTestCase {
    /// #128: the first scan names the location it is checking with a count, and Overview fills in as each one finishes.
    /// Discovery is slowed through a DEBUG-only seam so the fixture scan is still running when the rows appear.
    @MainActor func testFirstScanNamesEachLocationAndFillsOverviewAsItGoes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.25"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        let progress = app.staticTexts["catalogScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        let counted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value MATCHES %@", "Checking .+… [0-9]+ of [0-9]+"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [counted], timeout: 10), .completed, progress.debugDescription)
        // #220: the progress line sits in the bottom bar, not at the top of the page.
        let strip = actionStrip(app)
        XCTAssertTrue(strip.frame.contains(progress.frame), "The progress line is in the bottom bar")
        let stripHeight = strip.frame.height
        // The npm cache is among the first locations, Downloads comes later: its row and the total show up mid-scan.
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.exists, "The developer row appeared before the scan finished")
        let rowTop = developer.frame.minY
        let total = app.staticTexts["overviewRecommendedTotal"]
        XCTAssertTrue((total.value as? String)?.hasPrefix("Up to ") == true, total.debugDescription)
        XCTAssertFalse(app.staticTexts["overviewEmpty"].exists)

        XCTAssertTrue(progress.waitForNonExistence(timeout: 60))
        let downloads = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(downloads.exists)
        // Nothing shifts when the scan ends: the rows stay put and the bar keeps its height.
        XCTAssertEqual(developer.frame.minY, rowTop, accuracy: 0.5)
        XCTAssertEqual(actionStrip(app).frame.height, stripHeight, accuracy: 0.5)
        // #372: a category that found nothing stays listed below the ones that did, as "Empty", with no Review link.
        let updaters = app.descendants(matching: .any)["overviewCategory-updaters"]
        XCTAssertTrue(updaters.exists, "An empty category is still listed")
        XCTAssertFalse(app.buttons["overviewCategory-updaters"].exists, "An empty category has no Review link")
        XCTAssertTrue((updaters.value as? String)?.contains("Empty") == true, updaters.debugDescription)
        XCTAssertGreaterThan(updaters.frame.minY, downloads.frame.minY, "Empty categories sort below the ones that found something")
        XCTAssertFalse(app.descendants(matching: .any)["overviewEmpty"].exists, "Something was found, so no empty-state line")
        // "Show N more" still folds the rest of the list.
        let more = app.links["overviewShowMore"]
        XCTAssertTrue(more.exists)
        XCTAssertFalse(app.descendants(matching: .any)["overviewCategory-leftovers"].exists, "Folded under Show N more")
        more.click()
        XCTAssertTrue(app.descendants(matching: .any)["overviewCategory-leftovers"].waitForExistence(timeout: 5))
    }

    /// #308: while the first scan runs, Smart clean and the plan show skeleton rows rather than a blank page, and their
    /// actions say to wait; after discovery the bar names the phase it is in. When it ends, the rows replace the skeleton.
    @MainActor func testPlanAndSmartCleanShowSkeletonRowsAndTheBarNamesEachPhase() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.5"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        let progress = app.staticTexts["catalogScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["smartCleanSkeleton"].waitForExistence(timeout: 5), "Smart clean shows skeleton rows")
        let cleanUp = app.buttons["smartCleanCleanUp"]
        XCTAssertFalse(cleanUp.isEnabled)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["planSkeleton"].waitForExistence(timeout: 5), "The plan shows skeleton rows")
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["planCategory-developer"].exists, "No live rows while nothing is known")

        // After its last location the scan names what it is doing, never "… N of N" while it reads apps and plug-ins.
        let phases = ["Checking files from deleted apps…", "Checking apps and plug-ins…", "Checking which apps are open…",
                      "Recording storage trends…", "Checking app-managed storage…"]
        let phase = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value IN %@", phases), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [phase], timeout: 60), .completed, progress.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["planSkeleton"].exists, "Still waiting during the later phases")

        XCTAssertTrue(progress.waitForNonExistence(timeout: 60))
        XCTAssertTrue(app.descendants(matching: .any)["planCategory-developer"].waitForExistence(timeout: 5), "The rows replace the skeleton")
        XCTAssertFalse(app.descendants(matching: .any)["planSkeleton"].exists)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["smartCleanCategory-developer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["smartCleanSkeleton"].exists)
    }

    /// #220, #234: every screen has the same bottom bar at the same height, even at the minimum window width, and the
    /// catalog scan's progress shows in it on whichever screen is open. A long note stays on one line.
    @MainActor func testEveryScreenHasTheSameBottomBarAndShowsScanProgress() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("entry.zip"))
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.5"
        app.launchEnvironment["CACHEDROP_TEST_MINIMUM_WINDOW"] = "1"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        app.launch()

        let progress = app.staticTexts["catalogScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        // #234: at the minimum window width, a bar is its one row (Size.actionStripRow, 32) plus its padding and divider.
        XCTAssertEqual(app.windows.firstMatch.frame.width, 900, accuracy: 1, "The window is at its minimum width")
        let height = actionStrip(app).frame.height
        XCTAssertEqual(height, 32 + 2 * 16 + 1, accuracy: 1)
        // History and Locations did not start the scan; their bars show it.
        for (key, screen) in [("6", "History"), ("7", "Locations"), ("8", "System access")] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(progress.waitForExistence(timeout: 5), "Scan progress shows on \(screen)")
            XCTAssertTrue(actionStrip(app).frame.contains(progress.frame), screen)
            XCTAssertEqual(actionStrip(app).frame.height, height, accuracy: 0.5, screen)
        }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(progress.waitForNonExistence(timeout: 60))
        // With and without buttons, the bar is the same height once the scan is done.
        for (key, screen) in [("1", "Overview"), ("2", "Smart clean"), ("3", "Cleanup plan"), ("4", "Applications"), ("5", "Storage trends"), ("6", "History"), ("7", "Locations"), ("8", "System access")] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(app.buttons[screen].waitForExistence(timeout: 5))
            let strip = actionStrip(app)
            XCTAssertTrue(strip.waitForExistence(timeout: 5), screen)
            XCTAssertEqual(strip.frame.height, height, accuracy: 0.5, screen)
        }
        // #234: the explorer's bar is the same height too. It carries no note by design (617288f).
        app.typeKey("1", modifierFlags: .command)
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        XCTAssertTrue(app.buttons["Open folder " + folder.lastPathComponent].waitForExistence(timeout: 10))
        XCTAssertTrue(actionStrip(app).waitForExistence(timeout: 5))
        XCTAssertEqual(actionStrip(app).frame.height, height, accuracy: 0.5, "Explore storage")
    }

    @MainActor func testDeveloperCachesShowOnlyWhenPresentAndADryRunNeverRunsTheTool() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let marker = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn", ".cargo/registry", ".gradle/caches", "Library/Caches/Homebrew", "Library/Caches/ccache"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        // Overview has one row per category; the plan lists the rules that found something.
        waitForCatalogScan(app)
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ccache'")).firstMatch.exists)
        revealAndClick(developer, in: app)

        XCTAssertTrue(app.descendants(matching: .any)["planRule-homebrew"].waitForExistence(timeout: 5))
        for present in ["npm-cache", "yarn-cache", "cargo-cache", "gradle-cache"] { XCTAssertTrue(app.descendants(matching: .any)["planRule-" + present].exists, present) }
        for absent in ["pnpm-store", "uv-cache", "pip-cache", "cocoapods-cache"] { XCTAssertFalse(app.descendants(matching: .any)["planRule-" + absent].exists, absent) }
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ccache'")).firstMatch.exists)
        // Homebrew's own cleanup is recommended, so it is ticked unless brew is running (#349).
        tick(app.checkBoxes["planRule-homebrew"], in: app)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would run"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
    }


    /// Xcode build data in a fixture home. The journey itself runs under xcodebuild or Xcode, so
    /// DerivedData must show as refused with its reason; the stand-in simctl must never run in a dry run.
    @MainActor func testXcodeBuildDataIsRefusedWhileXcodeRunsAndADryRunNeverRunsSimctl() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Developer/Xcode/DerivedData/CacheDrop-abc/Build/Products/Debug/CacheDrop.app",
                                                   "Library/Developer/Xcode/Archives/2026-10-01/CacheDrop.xcarchive",
                                                   "Library/Developer/Xcode/iOS DeviceSupport/16.4 (20E247)",
                                                   "Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)",
                                                   "Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)",
                                                   "Library/Developer/CoreSimulator/Devices/0A1B2C3D-0000-0000-0000-000000000000",
                                                   "Library/Developer/CoreSimulator/Devices/0E0E0E0E-0000-0000-0000-000000000000",
                                                   ".android/avd/Pixel.avd"])
        let marker = home.appendingPathComponent("simctl-ran")
        let simctl = home.appendingPathComponent(".cachedrop-test-tools/simctl")
        // Lists one shut-down simulator, one unavailable simulator that takes space (#209: otherwise "Unavailable simulators"
        // isn't offered) and one unused runtime (#134); any other call leaves the marker.
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"0A1B2C3D-0000-0000-0000-000000000000","name":"iPhone 16","state":"Shutdown","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-16-0":[{"udid":"0E0E0E0E-0000-0000-0000-000000000000","name":"iPhone 14","state":"Shutdown","isAvailable":false}]}}"#
        let runtimes = #"{"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB":{"identifier":"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB","deletable":true,"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.watchOS-11-0","version":"11.0","build":"22R349","sizeBytes":4500000000}}"#
        try writeStandInTool("#!/bin/sh\ncase \"$*\" in\n\"list devices -j\") echo '\(devices)' ;;\n\"runtime list -j\") echo '\(runtimes)' ;;\n*) touch '\(marker.path)' ;;\nesac\n", to: simctl)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'Archives'")).firstMatch.exists)
        revealAndClick(developer, in: app)
        XCTAssertTrue(app.checkBoxes["planRule-xcode-device-support"].waitForExistence(timeout: 5))
        // Simulators, runtimes and Android emulators are each listed on their own, and none is preselected (#134).
        for (rule, name) in [("simulator-runtimes", "watchOS 11.0 (22R349)"), ("android-virtual-devices", "Pixel"), ("simulator-devices", "iPhone 16 (iOS 18.0)")] {
            // Items are drawn lazily: bring the rule's list into view first.
            reveal(app.checkBoxes["planRule-" + rule], in: app, nearTop: true)
            let item = app.checkBoxes["planItem-" + name]
            if !item.waitForExistence(timeout: 2) { expandDisclosures(in: app) }
            XCTAssertTrue(item.waitForExistence(timeout: 5), name)
            XCTAssertEqual(item.value as? Int, 0, name)
        }
        revealAndClick(app.checkBoxes["planItem-iPhone 16 (iOS 18.0)"], in: app)

        for rule in ["xcode-derived-data", "xcode-simulators"] {
            let box = app.checkBoxes["planRule-" + rule]
            XCTAssertTrue(box.waitForExistence(timeout: 5), rule)
            tick(box, in: app)
        }
        // The plan says why DerivedData will be refused: this journey runs under xcodebuild or Xcode.
        let running = app.staticTexts["planRunning-xcode-derived-data"]
        XCTAssertTrue(running.waitForExistence(timeout: 5))
        // "Xcode is running" with Quit Xcode when the app is open, "Quit Xcode to include this" when only its tools run.
        XCTAssertTrue((running.value as? String ?? "").contains("Xcode"), running.debugDescription)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would run"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/CacheDrop-abc/Build/Products/Debug/CacheDrop.app/entry").path))
    }


    /// #138: a running command-line owner reads "Quit npm to include this" with Check again, and the check clears the line
    /// once npm is gone. The stand-in npm is a shell running a script named npm-cli.js; no real app is ever quit here.
    @MainActor func testARunningCommandLineOwnerClearsAfterCheckAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        let script = home.appendingPathComponent(".cachedrop-test-npm/npm-cli.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "while :; do sleep 1; done\n".write(to: script, atomically: true, encoding: .utf8)
        let npm = Process()
        npm.executableURL = URL(fileURLWithPath: "/bin/sh")
        npm.arguments = [script.path]
        try npm.run()
        defer { if npm.isRunning { npm.terminate(); npm.waitUntilExit() }; app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        expandDisclosures(in: app)
        XCTAssertTrue(app.checkBoxes["smartCleanLine-yarn-cache|"].waitForExistence(timeout: 5), "The free rule keeps its original identifier")
        let held = app.checkBoxes["smartCleanLine-npm-cache||held-1"]
        XCTAssertTrue(held.waitForExistence(timeout: 5), "Held numbering starts at one beside free items")
        XCTAssertEqual(held.value as? Int, 0)
        XCTAssertFalse(app.checkBoxes["smartCleanLine-npm-cache||held-2"].exists)
        app.typeKey("1", modifierFlags: .command)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        let running = app.staticTexts["planRunning-npm-cache"]
        XCTAssertTrue(running.waitForExistence(timeout: 5))
        XCTAssertTrue((running.value as? String ?? "").contains("Quit npm to include this"), running.debugDescription)
        XCTAssertFalse(app.links["planRunningQuit-npm-cache"].exists)

        npm.terminate(); npm.waitUntilExit()
        revealAndClick(app.links["planRunningCheck-npm-cache"], in: app)
        XCTAssertTrue(running.waitForNonExistence(timeout: 5))
    }

    /// Dry run is off by default, so Clean up really deletes the fixture npm cache. It lives in a temp fixture home, never the real disk.
    @MainActor func testCleanUpOfAFixtureCategoryDeletesItAndReachesResults() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["0 bytes"].exists)
        revealAndClick(row, in: app)

        // One rule with one item: the category checkbox is the choice. The npm cache is recommended, so it arrives ticked (#349).
        let category = app.checkBoxes["planCategory-developer"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 1)

        // The plan's bottom bar has only Review cleanup.
        XCTAssertFalse(app.descendants(matching: .any)["dryRunToggle"].exists)
        let review = app.buttons["Review cleanup"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        review.click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        XCTAssertFalse(reviewLine(app, "commandsRun", "developer").exists)
        XCTAssertFalse(app.staticTexts["reviewPreviewNotice"].exists)
        // #574: one group, so the sheet fits it rather than standing at its full 520-point height (after its resize settles).
        Thread.sleep(forTimeInterval: 1)
        let sheet = app.sheets.firstMatch
        XCTAssertLessThan(sheet.frame.height, 480, sheet.debugDescription)
        let footer = sheet.descendants(matching: .any)["sheetFooter"]
        XCTAssertLessThan(footer.frame.minY - reviewLine(app, "permanentlyRemoved", "developer").frame.maxY, 200, "The footer sits close under the list")
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["Deleted"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["catalogPreviewNotice"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache").path))

        // #433, #569: History's row leads with the run's measured freed space, the figure Results leads with, never an
        // unknown "Free space change"; the estimate is inside the row.
        let freed = app.staticTexts["resultsMeasuredFreed"]
        XCTAssertTrue(freed.waitForExistence(timeout: 5))
        let freedText = freed.value as? String ?? freed.label
        XCTAssertFalse(freedText.contains("Unknown"), freed.debugDescription)
        // #577: one headline. The estimate is said once, in the line under it, never as a second figure.
        let estimateLine = app.staticTexts["resultsEstimate"]
        XCTAssertTrue((estimateLine.value as? String ?? estimateLine.label).hasPrefix("Estimated before cleanup: "), estimateLine.debugDescription)
        XCTAssertTrue((estimateLine.value as? String ?? estimateLine.label).hasSuffix(" · measured from the change in free space around each item"))
        XCTAssertFalse(app.staticTexts["Estimated before cleanup"].exists, "No second figure for the estimate")
        app.typeKey("6", modifierFlags: .command)
        let run = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupRun:'")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        XCTAssertTrue(run.label.contains(freedText) && run.label.contains("Freed"), run.debugDescription)
        XCTAssertFalse(run.label.contains("Estimated"), "The row leads with what was freed, not the estimate")
        revealAndClick(run, in: app)
        let estimate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Estimated before cleanup: ' OR value BEGINSWITH 'Estimated before cleanup: '")).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Measured freed space: '")).firstMatch.exists, "Said once, on the row")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Free space change'")).firstMatch.exists)
    }

    /// #123: after a cleanup, an Overview category opens a fresh plan, not the last run's results.
    @MainActor func testOverviewCategoryAfterACleanupOpensAFreshPlanWithThatCategoryOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        // One rule with one item: the category checkbox is the choice.
        let rule = app.checkBoxes["planCategory-developer"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        tick(rule, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // A fresh plan: the category is open, and the dry run's npm cache, found again by the rescan, is ticked as
        // recommended again (#349).
        XCTAssertTrue(rule.waitForExistence(timeout: 5), "The category opened from Overview shows its items")
        XCTAssertFalse(app.staticTexts["catalogPreviewNotice"].exists, "The last run's results are gone")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: rule)], timeout: 15), .completed)
    }

    /// The dry run lives in Settings, off by default. Turned on there, the whole flow runs and the installer stays in place.
    @MainActor func testDryRunFromSettingsLeavesTheChosenDownloadsInstallerInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // A second installer, so the plan lists the items to choose from.
        try Data(repeating: 5, count: 90_000).write(to: home.appendingPathComponent("Downloads/Other.pkg"))
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        let dryRun = app.descendants(matching: .any)["dryRunToggle"]
        XCTAssertTrue(dryRun.waitForExistence(timeout: 5))
        XCTAssertEqual(dryRun.value as? Int, 0)
        dryRun.click()
        XCTAssertEqual(dryRun.value as? Int, 1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(dryRun.waitForNonExistence(timeout: 5))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // A new installer isn't recommended, so nothing here starts ticked; the installer is chosen on its own.
        let category = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        let item = app.checkBoxes["planItem-Setup.dmg"]
        if !item.waitForExistence(timeout: 2) { expandDisclosures(in: app) }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? Int, 0)
        // #350: the installer goes to the Trash, so the total doesn't count it, and nothing on the page moves.
        let total = app.staticTexts["liveSelectionSummaryValue"], before = total.value as? String
        // #481: nothing is selected on Applications, so the count stands alone.
        XCTAssertFalse(element(identifier: "liveSelectionSummaryElsewhere", in: app).exists)
        // #484, Decision 92: the card's title is "Ready to clean", as on Smart clean.
        XCTAssertTrue(app.staticTexts["Ready to clean"].exists)
        XCTAssertFalse(app.staticTexts["Potential space released"].exists)
        let below = app.checkBoxes["planCategory-developer"], top = below.frame.minY
        revealAndClick(item, in: app)
        XCTAssertEqual(item.value as? Int, 1)
        XCTAssertEqual(app.checkBoxes["planItem-Other.pkg"].value as? Int, 0)
        // The installer goes to Trash, so the summary says how much of the total does.
        XCTAssertEqual(total.value as? String, before, "The Trash-bound installer releases nothing until the Trash is emptied")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value ENDSWITH 'of this goes to Trash'")).firstMatch.exists)
        XCTAssertEqual(below.frame.minY, top, "The rows stay where they were")
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "movedToTrash", "downloads").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reviewPreviewNotice"].exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would move to Trash"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Downloads/Setup.dmg").path))
    }

    @MainActor func testChromeCodeSignCopiesAreOfferedAsAnUpperBoundAndTheNewestIsKept() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // A stand-in for the user's /private/var/folders entry, read through the same DEBUG-only home seam.
        let clones = home.appendingPathComponent(".cachedrop-test-user-folder/X/com.google.Chrome.code_sign_clone")
        for (name, age) in [("code_sign_clone.old", -86_400.0), ("code_sign_clone.new", 0)] {
            let executable = clones.appendingPathComponent(name + "/Google Chrome.app/Contents/MacOS/Google Chrome")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 150_000).write(to: executable)
            try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(age)], ofItemAtPath: clones.appendingPathComponent(name).path)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // One copy is offered (the newest is kept), so the category checkbox is the choice.
        let rule = app.checkBoxes["planCategory-browser"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Up to '")).firstMatch.exists)
        tick(rule, in: app)
        // Only the copies: the fixture's npm cache arrives ticked as recommended too (#349).
        let developer = app.checkBoxes["planCategory-developer"]
        if developer.value as? Int != 0 { revealAndClick(developer, in: app) }
        XCTAssertEqual(developer.value as? Int, 0)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "browser").waitForExistence(timeout: 5))
        // The review lists each copy in a collapsed file list.
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label ENDSWITH 'Show files'")).firstMatch, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'code_sign_clone.old'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'code_sign_clone.new'")).firstMatch.exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists)
        // A dry run reports one line; the copies share disk space, so it is an upper bound.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Dry run · Nothing changed · Up to '")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Measured freed space"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clones.appendingPathComponent("code_sign_clone.old").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clones.appendingPathComponent("code_sign_clone.new").path))
    }

    /// Chrome's caches are listed per profile with sizes; its profile data never appears and is never touched.
    /// A Chrome running on this Mac makes the review skip the caches, which the journey also accepts.
    @MainActor func testBrowserCachesShowPerProfileSizesAndADryRunLeavesProfilesAlone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let cookies = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
        var files = [cookies, home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Local Storage/leveldb/LOG")]
        for (profile, bytes) in [("Default", 300_000), ("Profile 1", 80_000)] {
            files.append(home.appendingPathComponent("Library/Caches/Google/Chrome/\(profile)/Cache/Cache_Data/index"))
            files.append(home.appendingPathComponent("Library/Caches/Google/Chrome/\(profile)/Code Cache/js/index"))
            for file in files.suffix(2) {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 5, count: bytes).write(to: file)
            }
        }
        for file in files.prefix(2) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 9, count: 1_000).write(to: file)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // One rule with several items: its profiles are listed without a rule row.
        XCTAssertTrue(app.checkBoxes["planCategory-browser"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planRule-chrome-cache"].exists)
        let profile = app.checkBoxes["planProfile-chrome-cache-Default"]
        XCTAssertTrue(profile.exists)
        XCTAssertTrue(app.checkBoxes["planProfile-chrome-cache-Profile 1"].exists)
        let profileRow = app.buttons["Select Default"]
        XCTAssertTrue(profileRow.exists)
        XCTAssertTrue((profileRow.value as? String)?.range(of: #", [0-9.,]+ (bytes|KB|MB|GB|TB)$"#, options: .regularExpression) != nil,
                      "An exact profile has the same unhedged decimal size as its category: \(profileRow.value ?? "")")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Cookies' OR label CONTAINS 'Local Storage' OR value CONTAINS 'Cookies' OR value CONTAINS 'Local Storage'")).firstMatch.exists)
        tick(profile, in: app)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "browser").waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists || app.staticTexts["Skipped"].exists)
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// #117: without Full Disk Access (the fixture's Safari folder refuses to open), Safari's cache is listed as not
    /// accessible with the explanation, never sized as 0. With access, only its cache folder is offered, and a dry run
    /// leaves the cache and Safari's history in place.
    @MainActor func testSafariCacheIsNotAccessibleWithoutFullDiskAccessAndOfferedWithIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let safari = home.appendingPathComponent("Library/Safari")
        let history = safari.appendingPathComponent("History.db")
        let cache = home.appendingPathComponent("Library/Caches/com.apple.Safari/WebKit/NetworkCache/Version 17/Records/AB/Resource/0123")
        for (file, bytes) in [(history, 1_000), (cache, 250_000)] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: bytes).write(to: file)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: safari.path)
        defer {
            app.terminate(); try? FileManager.default.removeItem(at: state)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path); try? FileManager.default.removeItem(at: home)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        let denied = app.descendants(matching: .any)["overviewNotAccessible"]
        XCTAssertTrue(denied.waitForExistence(timeout: 10))
        // Safari's cache is one of the places named; others that need access too (sandboxed app caches, #133) add to the count.
        XCTAssertTrue(denied.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Full Disk Access ·' AND value CONTAINS 'Safari cache'")).firstMatch.exists)
        // #372 and Decision 62: Safari's cache couldn't be read, so the browser row says "Needs access", never "Empty", and has
        // no Review link.
        XCTAssertFalse(app.buttons["overviewCategory-browser"].exists, "Nothing found, so no browser row to review")
        let browser = app.descendants(matching: .any)["overviewCategory-browser"]
        XCTAssertTrue(browser.exists, "The browser row is still listed")
        XCTAssertTrue((browser.value as? String)?.contains("Needs Full Disk Access") == true, browser.debugDescription)
        revealAndClick(denied.links["fullDiskAccessLink"], in: app)
        XCTAssertTrue(app.staticTexts["Broader access is optional"].waitForExistence(timeout: 5))
        app.buttons["closeFullDiskAccess"].click() // "Not now", never "Open System Settings".

        // #435: the Cleanup plan says it the way Overview does, plural-correct, with the places in its value.
        app.typeKey("3", modifierFlags: .command)
        let planDenied = app.descendants(matching: .any)["planNotAccessible"]
        XCTAssertTrue(planDenied.waitForExistence(timeout: 10))
        let planLine = planDenied.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Full Disk Access ·' AND value CONTAINS 'Safari cache'")).firstMatch
        XCTAssertTrue(planLine.exists, planDenied.debugDescription)
        XCTAssertTrue(planLine.label.hasPrefix("1 location needs") || planLine.label.range(of: #"^\d+ locations need"#, options: .regularExpression) != nil, planLine.label)
        app.terminate()

        // Granted: the Safari folder opens.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.launch()
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["overviewNotAccessible"].exists)
        revealAndClick(row, in: app)
        let rule = app.checkBoxes["planCategory-browser"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        tick(rule, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "browser").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in [history, cache] { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// Updater downloads and logs show as their own Overview categories. A log folder holding a git checkout never appears,
    /// and a dry run leaves every fixture file in place. Per-app caches need an installed app, so unit tests cover them.
    @MainActor func testUpdaterDownloadsAndLogsAreTheirOwnCategoriesAndADryRunLeavesThemInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let files = ["Library/Caches/com.example.CacheDropFixture/org.sparkle-project.Sparkle/Installation/a/Fixture.tar.xz",
                     "Library/Logs/DiagnosticReports/Fixture-2026-10-26.ips", "Library/Logs/FixtureApp/main.log",
                     "Library/Logs/FixtureAgent/checkout/.git/HEAD"].map(home.appendingPathComponent)
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let updaters = app.buttons["overviewCategory-updaters"]
        XCTAssertTrue(updaters.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["overviewCategory-logs"].exists)
        revealAndClick(updaters, in: app)

        let update = app.checkBoxes["planCategory-updaters"]
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        // Overview opened Updates; Logs is its own category, still closed.
        XCTAssertFalse(app.checkBoxes["planRule-crash-reports"].exists)
        expandDisclosures(in: app)
        XCTAssertTrue(app.checkBoxes["planRule-crash-reports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["planRule-app-logs"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'FixtureAgent' OR value CONTAINS 'FixtureAgent' OR identifier CONTAINS 'FixtureAgent'")).firstMatch.exists)
        // Updater downloads and logs are recommended, so they arrive ticked (#349).
        XCTAssertEqual(update.value as? Int, 1)
        XCTAssertEqual(app.checkBoxes["planRule-crash-reports"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "updaters").waitForExistence(timeout: 5))
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "logs").exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// A stand-in `docker` in the fixture: `system df` prints `df` (or fails, as with no daemon); anything else leaves a marker.
    @MainActor private func addDocker(_ home: URL, daemonAnswers: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".docker"), withIntermediateDirectories: true)
        let marker = home.appendingPathComponent("docker-pruned")
        let docker = home.appendingPathComponent(".cachedrop-test-tools/docker")
        let df = daemonAnswers
            ? #"echo '{"Active":"1","Reclaimable":"2.5GB (62%)","Size":"4GB","TotalCount":"5","Type":"Images"}'; echo '{"Active":"0","Reclaimable":"1.2GB","Size":"1.2GB","TotalCount":"9","Type":"Build Cache"}'"#
            : "echo 'Cannot connect to the Docker daemon' >&2; exit 1"
        try writeStandInTool("#!/bin/sh\nif test \"$*\" = 'system df --format json'; then \(df); else touch '\(marker.path)'; fi\n", to: docker)
        return marker
    }

    @MainActor func testDockerPruneKindsAreSeparateChoicesAndADryRunNeverPrunes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let marker = try addDocker(home, daemonAnswers: true)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // Each prune kind is its own choice, none preselected; nothing is offered for volumes.
        for rule in ["docker-images", "docker-build-cache"] {
            let header = app.checkBoxes["planRule-" + rule]
            XCTAssertTrue(header.waitForExistence(timeout: 5), rule)
            XCTAssertEqual(header.value as? Int, 0, rule)
        }
        XCTAssertFalse(app.checkBoxes["planRule-docker-containers"].exists)
        // Only Docker in the review: the fixture's npm cache arrives ticked as recommended (#349).
        let npm = app.checkBoxes["planRule-npm-cache"]
        if npm.value as? Int != 0 { revealAndClick(npm, in: app) }
        XCTAssertEqual(npm.value as? Int, 0)
        revealAndClick(app.checkBoxes["planRule-docker-build-cache"], in: app)
        XCTAssertEqual(app.checkBoxes["planRule-docker-images"].value as? Int, 0)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").waitForExistence(timeout: 5))
        // The exact command shows with the files; only the chosen kind is there.
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label ENDSWITH 'Show files'")).firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["docker builder prune -a -f"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["docker image prune -a -f"].exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        // Messages show on demand.
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'would run docker builder prune -a -f'")).firstMatch.exists)
        app.descendants(matching: .any)["resultsDetailsToggle"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'would run docker builder prune -a -f'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    /// #411: the review sheet says Docker's space reaches macOS after the prune; Results say a check is coming, then show
    /// what more was free under the measured freed space. The wait is shortened for the journey.
    @MainActor func testADockerRunSaysItWillCheckAgainThenShowsWhatMoreWasFree() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_LATER_WAIT"] = "3"
        let marker = try addDocker(home, daemonAnswers: true)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        let npm = app.checkBoxes["planRule-npm-cache"]
        XCTAssertTrue(npm.waitForExistence(timeout: 5))
        if npm.value as? Int != 0 { revealAndClick(npm, in: app) }
        // Docker's folder only anchors its rules: nothing to reveal (#420).
        XCTAssertFalse(app.descendants(matching: .any)["planRuleReveal-docker-build-cache"].exists)
        revealAndClick(app.checkBoxes["planRule-docker-build-cache"], in: app)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["reviewDockerSettles"].waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["resultsSettling"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let settled = app.staticTexts["resultsSettled"]
        XCTAssertTrue(settled.waitForExistence(timeout: 15))
        XCTAssertTrue((settled.value as? String)?.hasSuffix("a minute later") == true)
        XCTAssertFalse(app.staticTexts["resultsSettling"].exists)
    }

    @MainActor func testDockerShowsANoticeInsteadOfRowsWhenItsDaemonIsntRunning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDocker(home, daemonAnswers: false)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // The notice sits on the first Docker rule: stopped containers, since they're pruned first (Decision 85).
        XCTAssertTrue(app.staticTexts["planNote-docker-containers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Docker isn’t running'")).firstMatch.exists)
        XCTAssertFalse(app.checkBoxes["planRule-docker-images"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}

final class ICloudCleanupUITests: XCTestCase {
    /// Two iCloud Drive files in the fixture home, one set to Keep Downloaded. Their iCloud states come from the
    /// debug fixture file, so the test never reads or evicts anything in real iCloud Drive.
    @MainActor private func addICloudFiles(_ home: URL) throws {
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        for name in ["Report.pdf", "Notes.pdf", "Pinned.pdf"] {
            let file = home.appendingPathComponent(drive + "/" + name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 150_000).write(to: file)
        }
        let states = [drive + "/Report.pdf": "ready", drive + "/Notes.pdf": "ready", drive + "/Pinned.pdf": "pinned"]
        try JSONEncoder().encode(states).write(to: home.appendingPathComponent(".cachedrop-test-icloud.json"))
    }

    @MainActor func testLocalCopiesAreChosenAndADryRunEvictsNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        try addICloudFiles(home)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-icloud"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["overviewCloudFinding"].exists, "The catalog row replaces the inventory row")
        revealAndClick(row, in: app)

        // Two local copies are offered, so they are listed without a rule row.
        let header = app.checkBoxes["planCategory-icloud"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? Int, 0)
        let item = app.checkBoxes["planItem-Report.pdf"]
        if !item.waitForExistence(timeout: 2) { expandDisclosures(in: app) }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planItem-Pinned.pdf"].exists, "Keep Downloaded files are never offered")
        XCTAssertFalse(app.checkBoxes["planRule-icloud-local-copies"].exists)
        revealAndClick(item, in: app)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "localCopiesRemoved", "icloud").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'stay in iCloud and download again when you open them'")).firstMatch.exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would remove local copy"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cachedrop-test-icloud-evicted").path))
    }
}

/// Large and old files explorer (#113): a picked fixture folder, chosen file by file, dry-run, left in place.
extension CatalogCleanupUITests {
    @MainActor func testPickedFolderListsOldFilesUnchosenAndADryRunLeavesThemInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Not .txt: Spotlight reads new text files in the runner's container to index them, which makes the old one recent.
        let old = folder.appendingPathComponent("old-archive.zip"), recent = folder.appendingPathComponent("recent.zip")
        try Data(repeating: 1, count: 4_000).write(to: old)
        try Data(repeating: 2, count: 4_000).write(to: recent)
        let then = Date().addingTimeInterval(-200 * 86_400)
        try FileManager.default.setAttributes([.creationDate: then, .modificationDate: then], ofItemAtPath: old.path)
        var times = [timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0)]
        XCTAssertEqual(utimes(old.path, &times), 0)
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        // #125: a clear Scan a folder action on Overview picks the folder and scans it right away.
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()

        waitForScannedFolder(app)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        // #222: inside a folder, back names where it goes, then leaves the explorer.
        let back = app.buttons["explorerBack"]
        assertBackButton(back, isAbove: "Explore storage", in: app)
        XCTAssertEqual(back.label, "Back to Overview")
        app.buttons["Open folder " + folder.lastPathComponent].click()
        XCTAssertTrue(app.textFields["explorerSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, "Back to Scanned folders")
        back.click()
        XCTAssertTrue(app.buttons["Open folder " + folder.lastPathComponent].waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, "Back to Overview")
        let mode = explorerMode(app)
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()

        // Only the old file is listed, and nothing is preselected.
        let item = app.checkBoxes["explorerChoose-old-archive.zip"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["explorerChoose-recent.zip"].exists)
        XCTAssertEqual(item.value as? Int, 0)
        item.click()
        XCTAssertEqual(item.value as? Int, 1)
        actionStrip(app).buttons["Add to cleanup plan"].click()

        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "files").waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would move to Trash"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))

        // #125: the cleanup run doesn't wipe the folder's large and old files.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(openLargeAndOld(app).waitForExistence(timeout: 20))

        // #125: the remembered folder is scanned again at launch, with no folder picked.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(openLargeAndOld(app).waitForExistence(timeout: 30))
    }

    /// #373: Explore storage sorts its folder list and its large and old files from the column header, On disk largest
    /// first by default, by Name with folders first; clicking the active column flips it, and the choice holds across lists.
    /// #544: switching to a list without the inspected file closes its inspector.
    @MainActor func testExplorerSortsByNameOrOnDiskAndSearches() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Zeta"), withIntermediateDirectories: true)
        // Both files are old, so both are also large and old files; Zeta holds a size between theirs.
        let big = folder.appendingPathComponent("a-big.bin"), small = folder.appendingPathComponent("b-small.bin")
        try Data(repeating: 1, count: 40_000).write(to: big)
        try Data(repeating: 2, count: 4_000).write(to: small)
        try Data(repeating: 3, count: 12_000).write(to: folder.appendingPathComponent("Zeta/inner.bin"))
        let then = Date().addingTimeInterval(-200 * 86_400)
        for file in [big, small] {
            try FileManager.default.setAttributes([.creationDate: then, .modificationDate: then], ofItemAtPath: file.path)
            var times = [timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0)]
            XCTAssertEqual(utimes(file.path, &times), 0)
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        app.buttons["Open folder " + folder.lastPathComponent].click()

        let rows = [app.buttons["Inspect a-big.bin"].firstMatch, app.buttons["Open folder Zeta"].firstMatch, app.buttons["Inspect b-small.bin"].firstMatch]
        XCTAssertTrue(rows[0].waitForExistence(timeout: 5))
        // #544: All files' hint is one sentence and mentions no checkbox, since most files have none.
        let hint = app.staticTexts["explorerHint"]
        XCTAssertEqual(hint.value as? String ?? hint.label, "Click a name to open or inspect it.")
        func order() -> [CGFloat] { rows.map(\.frame.minY) }
        let byName = app.buttons["explorerSort-name"], bySize = app.buttons["explorerSort-size"]
        XCTAssertEqual(bySize.value as? String, "Largest first")
        XCTAssertTrue(order()[0] < order()[1] && order()[1] < order()[2], "On disk, largest first: a-big, Zeta, b-small")
        byName.click()
        XCTAssertEqual(byName.value as? String, "A to Z")
        XCTAssertTrue(order()[1] < order()[0] && order()[0] < order()[2], "Name, folders first: Zeta, a-big, b-small")
        byName.click()
        XCTAssertEqual(byName.value as? String, "Z to A")
        XCTAssertTrue(order()[1] < order()[2] && order()[2] < order()[0], "Flipped, folders still first: Zeta, b-small, a-big")

        // The rounded search field filters the folder; clearing it lists everything again.
        let search = app.textFields["explorerSearch"]
        search.click(); search.typeText("big")
        XCTAssertTrue(rows[2].waitForNonExistence(timeout: 5))
        XCTAssertTrue(rows[0].exists)
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(rows[2].waitForExistence(timeout: 5))

        // Large and old files keep the chosen sort, and follow the header too.
        bySize.click()
        let mode = explorerMode(app)
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        let files = [app.checkBoxes["explorerChoose-a-big.bin"], app.checkBoxes["explorerChoose-b-small.bin"]]
        XCTAssertTrue(files[0].waitForExistence(timeout: 5))
        XCTAssertEqual(bySize.value as? String, "Largest first")
        XCTAssertTrue(files[0].frame.minY < files[1].frame.minY, "Largest first")
        bySize.click()
        XCTAssertEqual(bySize.value as? String, "Smallest first")
        XCTAssertTrue(files[1].frame.minY < files[0].frame.minY, "Smallest first")

        // #544: a file inspected in All files that Large and old files doesn't list closes the inspector on the switch;
        // the folder on show takes its place.
        mode.click()
        XCTAssertEqual(hint.value as? String ?? hint.label, "Click a name to open or inspect it.")
        app.buttons["Open folder Zeta"].firstMatch.click()
        let inner = app.buttons["Inspect inner.bin"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 5))
        inner.click()
        let inspector = app.descendants(matching: .any)["explorerInspector"]
        XCTAssertTrue(inspector.staticTexts["inner.bin"].waitForExistence(timeout: 5))
        mode.click()
        XCTAssertTrue(app.staticTexts["No large or old files here"].waitForExistence(timeout: 5))
        XCTAssertEqual(hint.value as? String ?? hint.label, "Files of 500 MB or more, or not opened in 90 days.")
        XCTAssertTrue(inspector.staticTexts["inner.bin"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(inspector.staticTexts["Zeta"].exists)
    }

    /// #227, #228: the explorer's back buttons name their destination. The Cleanup plan opened from the explorer goes back to
    /// "Explore storage", and a folder that went away leaves only the back button to the list of locations.
    @MainActor func testExplorerBackButtonsNameTheirDestination() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("Inner/entry.zip"))
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        app.buttons["Open folder " + folder.lastPathComponent].click()
        XCTAssertTrue(app.textFields["explorerSearch"].waitForExistence(timeout: 5))

        // #228's plan back button ("‹ Explore storage") is checked from Add to cleanup plan (#320) in
        // testExploreFromLocationsAddsALargeFileToThePlan; nothing here can be ticked.

        // #227: a subfolder is gone after a recheck; only the shared back button leads to the list of locations.
        // (Removing the scanned folder itself keeps its last observation, so the subfolder is what goes away.)
        app.buttons["Open folder Inner"].click()
        XCTAssertTrue(app.buttons["Inspect entry.zip"].firstMatch.waitForExistence(timeout: 5))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Inner"))
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["This folder is no longer there"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Return to selected locations"].exists)
        let explorerBack = app.buttons["explorerBack"]
        XCTAssertEqual(explorerBack.label, "Back to Scanned folders")
        assertBackButton(explorerBack, isAbove: "Explore storage", in: app)
        explorerBack.click()
        XCTAssertFalse(app.staticTexts["This folder is no longer there"].waitForExistence(timeout: 2))
        XCTAssertEqual(explorerBack.label, "Back to Overview")
    }

    /// #365: a folder with 5,000 direct children opens within a few seconds and builds only the rows on screen.
    @MainActor func testExplorerOpensAFolderWithThousandsOfFilesQuickly() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let crowded = folder.appendingPathComponent("Crowded")
        try FileManager.default.createDirectory(at: crowded, withIntermediateDirectories: true)
        for number in 0..<5_000 { try Data(repeating: 1, count: 16).write(to: crowded.appendingPathComponent(String(format: "file-%04d.txt", number))) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app, timeout: 60)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        app.buttons["Open folder " + folder.lastPathComponent].click()
        XCTAssertTrue(app.buttons["Open folder Crowded"].waitForExistence(timeout: 5))
        app.buttons["Open folder Crowded"].click()
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inspect file-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3), "The crowded folder shows its rows within a few seconds")
        XCTAssertLessThan(rows.count, 5_000, "Only the rows on screen are built")
    }

    /// #249: the scanned folder itself is deleted and Scan again can't find it. The explorer keeps its last observation
    /// but marks it as gone, with Overview's orange row and Choose again…, and never lists its old contents as current.
    @MainActor func testExplorerMarksADeletedScannedFolderAsNotFound() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("Inner/entry.zip"))
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        app.buttons["Open folder " + folder.lastPathComponent].click()
        XCTAssertTrue(app.buttons["Open folder Inner"].waitForExistence(timeout: 5))

        try FileManager.default.removeItem(at: folder)
        app.typeKey("r", modifierFlags: .command)
        let row = app.staticTexts["explorerLocationRecovery"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue((row.value as? String ?? "").hasPrefix("Folder not found · last scanned "), "\(String(describing: row.value))")
        XCTAssertEqual(app.links["explorerChooseAgain"].label, "Choose again…")
        XCTAssertFalse(app.buttons["Open folder Inner"].exists)
        XCTAssertFalse(app.staticTexts["This folder is no longer there"].exists)

        // The list of locations marks it the same way and doesn't offer to open its old contents.
        let explorerBack = app.buttons["explorerBack"]
        XCTAssertEqual(explorerBack.label, "Back to Scanned folders")
        explorerBack.click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open folder " + folder.lastPathComponent].exists)
    }

    /// #320: Explore storage's home is Locations. A scanned folder's Explore link opens it at that folder; ticking
    /// a large file enables Add to cleanup plan, which lands on the plan with the file ticked and "‹ Explore storage".
    @MainActor func testExploreFromLocationsAddsALargeFileToThePlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // 600 MB on disk, so it is large (#394: a sparse file isn't), preallocated rather than written; removed with the folder.
        let large = folder.appendingPathComponent("large-video.mov")
        try Data(repeating: 1, count: 4_000).write(to: large)
        let fd = open(large.path, O_RDWR)
        var store = fstore_t(fst_flags: UInt32(F_ALLOCATEALL), fst_posmode: F_PEOFPOSMODE, fst_offset: 0, fst_length: 600_000_000, fst_bytesalloc: 0)
        XCTAssertEqual(fcntl(fd, F_PREALLOCATE, &store), 0); XCTAssertEqual(ftruncate(fd, 600_000_000), 0); close(fd)
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))

        // Downloads is always a scanned location (Decision 83), so folders are added from Locations in the sidebar.
        app.buttons["Locations"].click()
        XCTAssertTrue(app.staticTexts["Locations"].waitForExistence(timeout: 5))
        app.buttons["Add folder…"].click()
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()

        // A predicate: the identifier is longer than a subscript query allows.
        let explore = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "locationExplore:" + folder.path)).firstMatch
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        revealAndClick(explore, in: app)
        let back = app.buttons["explorerBack"]
        assertBackButton(back, isAbove: "Explore storage", in: app)
        XCTAssertEqual(back.label, "Back to Locations")
        // The folder on show has an inspector as tall as its content (#371), and the bar's button waits for a tick.
        let inspector = app.descendants(matching: .any)["explorerInspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertLessThan(inspector.frame.height, app.windows.firstMatch.frame.height / 3, "the inspector sizes to its content")
        let add = actionStrip(app).buttons["Add to cleanup plan"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)

        let item = app.checkBoxes["explorerChoose-large-video.mov"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertEqual(item.value as? Int, 0)
        item.click()
        XCTAssertTrue(actionStrip(app).staticTexts["1 selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        add.click()

        let planBack = app.buttons["Back to Explore storage"]
        assertBackButton(planBack, isAbove: "Cleanup plan", in: app)
        // One file in its category: the category's checkbox is the file's (Decision 25).
        let planned = app.checkBoxes["planCategory-files"]
        XCTAssertTrue(planned.waitForExistence(timeout: 5))
        XCTAssertEqual(planned.value as? Int, 1)
        planBack.click()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, "Back to Locations")

        // A file's name shows it in the inspector. At the list of locations nothing is picked, so there is
        // no inspector and the list takes the width (#371); back returns to the folder and its picked file.
        app.buttons["Inspect large-video.mov"].firstMatch.click()
        XCTAssertTrue(inspector.staticTexts["large-video.mov"].waitForExistence(timeout: 5))
        app.links["Scanned folders"].click()
        XCTAssertTrue(app.buttons["Open folder " + folder.lastPathComponent].waitForExistence(timeout: 5))
        XCTAssertFalse(inspector.exists)
        back.click()
        XCTAssertTrue(inspector.staticTexts["large-video.mov"].waitForExistence(timeout: 5))
    }

    /// Opens Explore storage from Overview in its Large and old files mode; returns the fixture's old file toggle.
    @MainActor private func openLargeAndOld(_ app: XCUIApplication) -> XCUIElement {
        waitForScannedFolder(app, timeout: 30)
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 30))
        revealAndClick(explore, in: app)
        let mode = explorerMode(app)
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        // The explorer keeps its mode within a run; turn it on only when it's off.
        if mode.label == "Large and old files" { mode.click() }
        return app.checkBoxes["explorerChoose-old-archive.zip"]
    }
}

final class AppManagedStorageUITests: XCTestCase {
    /// Three Photos libraries, Xcode archives, unreadable Messages attachments and two local snapshots in the fixture home.
    /// The snapshot count comes from a debug fixture file, so tmutil never runs, and opening is a debug no-op.
    @MainActor private func addAppManagedData(_ home: URL) throws -> URL {
        // Photos libraries (#180): the default one, a renamed one and one on a connected volume (`<home>/Volumes` here).
        for path in ["Pictures/Photos Library.photoslibrary/originals/a.heic", "Pictures/Trip 2019.photoslibrary/originals/b.heic",
                     "Volumes/External/Family.photoslibrary/originals/c.heic", "Library/Developer/Xcode/Archives/2026-10-26/App.xcarchive/Info.plist",
                     "Library/Messages/Attachments/ab/photo.jpg"] {
            let file = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 5, count: 90_000).write(to: file)
        }
        try "2".write(to: home.appendingPathComponent(".cachedrop-test-snapshots"), atomically: true, encoding: .utf8)
        // An agent workspace (#140): a fixture git repository, written by hand since the test runner can't run git,
        // with no commit yet and one file not committed.
        let workspace = home.appendingPathComponent(".codex/worktrees/a1b2/app")
        for folder in [".git/objects", ".git/refs/heads"] {
            try FileManager.default.createDirectory(at: workspace.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try "ref: refs/heads/main\n".write(to: workspace.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "[core]\n\trepositoryformatversion = 0\n\tbare = false\n".write(to: workspace.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        try "draft".write(to: workspace.appendingPathComponent("draft.swift"), atomically: true, encoding: .utf8)
        let locked = home.appendingPathComponent("Library/Messages/Attachments")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        return locked
    }

    @MainActor func testAppManagedCategoriesShowSizeOrNotAccessibleAndNeverJoinThePlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let locked = try addAppManagedData(home)
        defer {
            app.terminate(); try? FileManager.default.removeItem(at: state)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        // One Overview row leads to the App-managed storage page.
        let entry = app.buttons["overviewAppManaged"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["guidance-photos-library"].exists)
        revealAndClick(entry, in: app)
        let photos = app.buttons["guidance-photos-library"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        XCTAssertEqual(photos.label, "Open Photos")
        XCTAssertTrue((photos.value as? String)?.contains("3 libraries") == true, String(describing: photos.value))
        // Each library with its volume and size, revealed in Finder, never offered (#180).
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Show libraries · 3'")).firstMatch, in: app)
        let external = app.links["Reveal Family in Finder"]
        XCTAssertTrue(external.waitForExistence(timeout: 5))
        XCTAssertTrue((external.value as? String)?.hasPrefix("External") == true, String(describing: external.value))
        XCTAssertTrue(app.links["Reveal Trip 2019 in Finder"].exists)
        XCTAssertTrue(app.links["guidanceLearnMore-photos-library"].exists)
        revealAndClick(external, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would reveal Family.")
        XCTAssertTrue((app.buttons["guidance-messages-attachments"].value as? String)?.contains("Needs Full Disk Access") == true)
        // One access note for the page, never a link per row.
        XCTAssertTrue(app.descendants(matching: .any)["guidanceAccess"].exists)
        XCTAssertEqual(app.links.matching(identifier: "fullDiskAccessLink").count, 1)
        XCTAssertTrue((app.buttons["guidance-time-machine-snapshots"].value as? String)?.contains("2 snapshots · Unknown") == true)
        XCTAssertTrue(app.buttons["guidance-xcode-archives"].exists)
        let workspaces = app.buttons["guidance-agent-workspaces"]
        XCTAssertEqual(workspaces.label, "Open in Finder")
        XCTAssertTrue((workspaces.value as? String)?.contains("1 workspace · 1 has uncommitted changes") == true,
                      String(describing: workspaces.value))
        revealAndClick(photos, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would open Photos.")

        assertBackButton(app.buttons["appManagedBack"], isAbove: "App-managed storage", in: app)
        XCTAssertEqual(app.buttons["appManagedBack"].label, "Back to Overview")
        app.buttons["appManagedBack"].click()
        revealAndClick(app.buttons["overviewCategory-developer"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["planCategory-developer"].waitForExistence(timeout: 5))
        for id in ["photos-library", "xcode-archives", "messages-attachments", "time-machine-snapshots", "agent-workspaces"] {
            XCTAssertFalse(app.descendants(matching: .any)["planRule-" + id].exists, id)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Pictures/Photos Library.photoslibrary/originals/a.heic").path))
    }

    /// #178: Final Cut Pro libraries, renamed and external, are listed with Final Cut's own steps; opening it reports
    /// only that it would open, never cleanup done, and nothing in a library changes.
    @MainActor func testFinalCutLibrariesAreListedAndOpeningFinalCutCleansNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let render = home.appendingPathComponent("Movies/Untitled.fcpbundle/Event 1/Render Files/a.mov")
        for file in [render, home.appendingPathComponent("Volumes/Shuttle/Client Cut.fcpbundle/Event 1/Transcoded Media/b.mov")] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()

        let entry = app.buttons["overviewAppManaged"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        revealAndClick(entry, in: app)
        let row = app.buttons["guidance-final-cut-libraries"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.label, "Open Final Cut Pro")
        XCTAssertTrue((row.value as? String)?.contains("2 libraries") == true, String(describing: row.value))
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Show libraries · 2'")).firstMatch, in: app)
        let external = app.links["Reveal Client Cut in Finder"]
        XCTAssertTrue(external.waitForExistence(timeout: 5))
        XCTAssertTrue((external.value as? String)?.hasPrefix("Shuttle") == true, String(describing: external.value))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Delete Generated Library Files'")).firstMatch.exists)
        XCTAssertTrue(app.links["guidanceLearnMore-final-cut-libraries"].exists)
        revealAndClick(row, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would open Final Cut Pro.")
        XCTAssertFalse(app.descendants(matching: .any)["planRule-final-cut-libraries"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: render.path))
    }

    /// #179: Lightroom Classic's previews and Smart Previews are separate rows, counted by catalog, each with its own
    /// steps; the catalog is never listed or offered, and opening Lightroom changes nothing.
    @MainActor func testLightroomPreviewsAreSeparateFromSmartPreviewsAndNoCatalogIsOffered() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Pictures/Lightroom")
        let catalog = folder.appendingPathComponent("Lightroom Catalog.lrcat")
        for file in [catalog, folder.appendingPathComponent("Lightroom Catalog Previews.lrdata/root/a.lrprev"),
                     folder.appendingPathComponent("Lightroom Catalog Smart Previews.lrdata/b.dng")] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()

        let entry = app.buttons["overviewAppManaged"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        revealAndClick(entry, in: app)
        let previews = app.buttons["guidance-lightroom-previews"], smart = app.buttons["guidance-lightroom-smart-previews"]
        XCTAssertTrue(previews.waitForExistence(timeout: 10))
        XCTAssertTrue(smart.exists)
        XCTAssertEqual(previews.label, "Open Lightroom Classic")
        XCTAssertTrue((previews.value as? String)?.contains("1 catalog") == true, String(describing: previews.value))
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Show catalogs · 1'")).firstMatch, in: app)
        XCTAssertTrue(app.links["Reveal Lightroom Catalog Previews in Finder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Discard 1:1 Previews'")).firstMatch.exists)
        XCTAssertTrue(app.links["guidanceLearnMore-lightroom-previews"].exists)
        XCTAssertFalse(app.links["Reveal Lightroom Catalog in Finder"].exists)
        revealAndClick(smart, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would open Lightroom Classic.")
        for id in ["lightroom-previews", "lightroom-smart-previews"] { XCTAssertFalse(app.descendants(matching: .any)["planRule-" + id].exists) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: catalog.path))
    }

    /// #174: plug-ins are listed by product, with Reveal in Finder, and nothing is offered or changed.
    @MainActor func testAudioPlugInsAreListedByProductAndLeftAsIs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // The fixture home stands in for the system root too, so these are the only plug-ins the app sees.
        var bundles: [URL] = []
        for (folder, ext, id) in [("Components", "component", "com.maker.prosynth.au"), ("VST3", "vst3", "com.maker.vst3.prosynth")] {
            let bundle = home.appendingPathComponent("Library/Audio/Plug-Ins/\(folder)/Pro Synth.\(ext)")
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": "2.1", "CFBundleExecutable": "Pro Synth"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            try Data(repeating: 1, count: 50_000).write(to: bundle.appendingPathComponent("Contents/MacOS/Pro Synth"))
            bundles.append(bundle)
        }
        app.launch()

        let entry = app.buttons["overviewAppManaged"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        revealAndClick(entry, in: app)
        let row = app.buttons["guidance-audio-plug-ins"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue((row.value as? String)?.contains("1 product · AU, VST3") == true, String(describing: row.value))
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Show products · 1'")).firstMatch, in: app)
        // #207: the label says what the click does, and the line is short: the place is in the tooltip.
        let product = app.links["Reveal Pro Synth in Finder"]
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        XCTAssertTrue((product.value as? String)?.hasPrefix("2.1 · AU, VST3,") == true, String(describing: product.value))
        revealAndClick(product, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would reveal Pro Synth.")
        for bundle in bundles { XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/MacOS/Pro Synth").path)) }
    }
}

final class TrashSpaceUITests: XCTestCase {
    /// #129: Overview says what the fixture Trash holds, and Open Trash opens it (the debug opener records it instead of Finder).
    @MainActor func testOverviewShowsWhatTheTrashHoldsAndOpenTrashOpensIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let trashed = home.appendingPathComponent(".Trash/Old installer.dmg")
        try FileManager.default.createDirectory(at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: 300_000).write(to: trashed)
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        let line = app.staticTexts["overviewTrash"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        let text = [line.label, line.value as? String ?? ""].first { !$0.isEmpty } ?? ""
        XCTAssertTrue(text.hasPrefix("Trash holds "), "label: \(line.label), value: \(String(describing: line.value))")
        revealAndClick(app.links["overviewTrashOpen"], in: app)
        let marker = home.appendingPathComponent(".cachedrop-test-opened-trash")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), home.appendingPathComponent(".Trash").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path), "Opening the Trash changes nothing in it")
    }

    /// #164: Overview's disk bar shows what was found inside the used space: a segment per category with an "up to" label for
    /// VoiceOver and the tooltip, the Trash as its own segment that opens nothing, and a click that opens the category in the
    /// plan. A fixture disk (`CACHEDROP_TEST_CAPACITY`) makes the fixture home's few hundred kilobytes a visible part of it.
    @MainActor func testOverviewBarShowsWhatWasFoundAndASegmentOpensItsCategory() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let trashed = home.appendingPathComponent(".Trash/Old installer.dmg")
        try FileManager.default.createDirectory(at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: 100_000).write(to: trashed)
        app.launchEnvironment["CACHEDROP_TEST_CAPACITY"] = "400000,1000000"
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        let developer = app.buttons["meterSegment-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 15))
        // #344: the label says what the tooltip says.
        XCTAssertTrue(developer.label.hasPrefix("Developer caches and build files · Up to "), developer.label)
        XCTAssertTrue(app.buttons["meterSegment-downloads"].exists)
        let trash = app.descendants(matching: .any)["meterSegment-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 10))
        XCTAssertTrue(trash.label.hasPrefix("In Trash · "), trash.label)
        XCTAssertGreaterThan(trash.frame.minX, developer.frame.maxX, "#343: the Trash ends what was found, at the tip")
        XCTAssertFalse(app.buttons["meterSegment-trash"].exists, "The Trash segment opens nothing")
        XCTAssertTrue(app.descendants(matching: .any)["sidebarMeterSegments"].exists, "The sidebar meter shows one reclaimable segment")

        developer.click()
        XCTAssertTrue(app.checkBoxes["planCategory-developer"].waitForExistence(timeout: 5), "The segment opens its category in the plan")
    }

    /// #159: an installer a run moved to the (fixture) Trash is put back from Results; History records it and Overview's
    /// Trash line is measured again. Debug test runs trash into the fixture home's `.Trash`, never the real one.
    @MainActor func testPutBackReturnsATrashedInstallerAndHistoryRecordsIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let older = home.appendingPathComponent(".Trash/Old installer.dmg")
        try FileManager.default.createDirectory(at: older.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: 300_000).write(to: older)
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        let line = app.staticTexts["overviewTrash"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        func lineText() -> String { [line.label, line.value as? String ?? ""].first { !$0.isEmpty } ?? "" }
        let before = lineText()
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        let category = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        revealAndClick(category, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "downloads").waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        let original = home.appendingPathComponent("Downloads/Setup.dmg"), inTrash = home.appendingPathComponent(".Trash/Setup.dmg")
        let putBack = app.descendants(matching: .any)["putBack-Setup.dmg"]
        XCTAssertTrue(putBack.waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inTrash.path))
        revealAndClick(putBack, in: app)
        XCTAssertTrue(app.staticTexts["putBackDone-Setup.dmg"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inTrash.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.path), "Put back moves only its own item")

        app.typeKey("6", modifierFlags: .command)
        // The run's row is one button whose label holds its title.
        let run = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Put back from the Trash' OR value CONTAINS 'Put back from the Trash'")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(lineText(), before, "The Trash holds what it held before the run")
    }

    /// #359, Decision 68: an installer a run moved to the (fixture) Trash is deleted from it from Results: Empty from Trash…,
    /// the review sheet, Empty. Only that item goes; History shows "Emptied from the Trash · 1 item" and the item has no
    /// Put back. Debug test runs trash into, and empty from, the fixture home's `.Trash`, never the real one.
    @MainActor func testEmptyFromTrashDeletesWhatARunMovedThereAndHistoryRecordsIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // The user's own trashed file, which emptying never touches.
        let mine = home.appendingPathComponent(".Trash/Old installer.dmg")
        try FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: 300_000).write(to: mine)
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        let category = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        revealAndClick(category, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "downloads").waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        let inTrash = home.appendingPathComponent(".Trash/Setup.dmg")
        XCTAssertTrue(app.descendants(matching: .any)["putBack-Setup.dmg"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inTrash.path))
        let line = app.staticTexts["resultsTrash"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        let text = [line.label, line.value as? String ?? ""].first { !$0.isEmpty } ?? ""
        XCTAssertTrue(text.hasSuffix("is in the Trash. Empty it to free the space. ·"), text)
        let empty = app.descendants(matching: .any)["resultsTrashEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        revealAndClick(empty, in: app)

        XCTAssertTrue(app.staticTexts["Empty from the Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Deleted permanently. They can’t be put back."].exists)
        XCTAssertTrue(app.descendants(matching: .any)["emptyItem-Setup.dmg"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["emptyItem-Old installer.dmg"].exists, "The user's own trashed file isn't offered")
        app.buttons["emptyFromTrashConfirm"].click()
        let done = app.buttons["emptyFromTrashDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inTrash.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path), "Emptying deletes only what CacheDrop moved there")
        done.click()
        XCTAssertFalse(app.descendants(matching: .any)["putBack-Setup.dmg"].exists, "An emptied item can't be put back")
        XCTAssertFalse(empty.exists, "Nothing of CacheDrop's is left to empty")

        app.typeKey("6", modifierFlags: .command)
        func run(_ title: String) -> XCUIElement {
            // Ignoring case: a run that also deleted reads "Deleted and moved to Trash".
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", title, title)).firstMatch
        }
        XCTAssertTrue(run("Emptied from the Trash · 1 item").waitForExistence(timeout: 10))
        let cleanup = run("Moved to Trash")
        XCTAssertTrue(cleanup.waitForExistence(timeout: 10))
        revealAndClick(cleanup, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Setup.dmg' OR value BEGINSWITH 'Setup.dmg'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["putBack-Setup.dmg"].exists, "History drops the emptied item's Put back")
    }
}

extension CatalogCleanupUITests {
    /// #229: "Choose items · N" counts the lines Smart clean lists, not the items behind them. Yarn's two cache folders
    /// are one line, so the developer category's three items show as two lines.
    @MainActor func testSmartCleanChooseItemsCountsItsLines() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn", ".yarn/berry/cache"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["smartCleanCategory-developer"].waitForExistence(timeout: 10))
        let choose = app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH 'Choose items'")).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertEqual(choose.label, "Choose items · 2")
        openDisclosure(choose, in: app)
        XCTAssertTrue(app.checkBoxes["smartCleanLine-yarn-cache|"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["smartCleanLine-npm-cache|"].exists)
    }

    /// #137, #349: Smart clean, opened from Overview's link, lists what it recommends, all ticked and each untickable.
    /// Its Clean up opens the review; a new installer stays out (#319). The Cleanup plan keeps its own selection.
    @MainActor func testSmartCleanReviewsOnlyRebuildableItemsAndKeepsThePlanSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let marker = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))

        // The Cleanup plan's own choice: the installer.
        app.typeKey("3", modifierFlags: .command)
        let installer = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(installer.waitForExistence(timeout: 10))
        revealAndClick(installer, in: app)
        XCTAssertEqual(installer.value as? Int, 1)

        app.typeKey("1", modifierFlags: .command)
        let link = app.links["overviewSmartClean"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertEqual(link.label, "Smart clean ›")
        revealAndClick(link, in: app)

        // All ticked; the new installer is not in it, and Yarn can be unticked.
        let developer = app.checkBoxes["smartCleanCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertEqual(developer.value as? Int, 1)
        XCTAssertFalse(app.checkBoxes["smartCleanCategory-downloads"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["smartCleanNotIncluded-downloads"].exists)
        // #219: the plan's category row; it starts collapsed and "Choose items" opens it.
        let yarn = app.checkBoxes["smartCleanLine-yarn-cache|"]
        XCTAssertFalse(yarn.exists)
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH 'Choose items'")).firstMatch, in: app)
        XCTAssertTrue(yarn.waitForExistence(timeout: 5))
        XCTAssertEqual(app.checkBoxes["smartCleanLine-npm-cache|"].value as? Int, 1)
        revealAndClick(yarn, in: app)
        XCTAssertEqual(yarn.value as? Int, 0)
        // It stays open after leaving Smart clean and coming back.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(yarn.waitForExistence(timeout: 10))
        XCTAssertEqual(yarn.value as? Int, 0)
        app.buttons["smartCleanCleanUp"].click()

        // The review lists only the npm cache.
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 10))
        XCTAssertFalse(reviewLine(app, "movedToTrash", "downloads").exists)
        XCTAssertFalse(reviewLine(app, "commandsRun", "developer").exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == '1 item · Show files'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons.matching(NSPredicate(format: "label == 'Clean up' AND identifier != 'smartCleanCleanUp'")).firstMatch.click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        for kept in [".npm/_cacache/content-v2/sha512/ab/blob", "Downloads/Setup.dmg", "Library/Caches/Yarn/entry"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(kept).path), kept)
        }

        // The Smart clean run took only its own ticked items and left the plan's installer ticked (#349).
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(installer.waitForExistence(timeout: 15))
        let chosen = NSPredicate(format: "value == 1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chosen, object: installer)], timeout: 15), .completed, "The installer is still chosen")
    }

    /// #343, #344: what CacheDrop found ends at the right tip of the used space and each segment's label names it (the
    /// tooltip carries the same text; this journey reads the label). #370: Smart clean shows the Cleanup plan's summary
    /// card, "Ready to clean", not Overview's volume card, and its title is just "Smart clean".
    @MainActor func testStorageBarsPutWhatWasFoundAtTheTipAndSmartCleanShowsThePlansSummaryCard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)

        let meter = app.descendants(matching: .any)["meterSegments"].firstMatch
        let developer = app.descendants(matching: .any)["meterSegment-developer"].firstMatch
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(developer.frame.minX, meter.frame.minX + 10, "The rest of the used space comes first; what was found sits at the tip")
        XCTAssertTrue(developer.label.hasPrefix("Developer caches and build files · Up to "), developer.label)

        app.typeKey("2", modifierFlags: .command)
        let header = app.descendants(matching: .any)["smartCleanHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        // The header combines its texts into one element, so the window is searched: only the card says "Ready to clean".
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ready to clean' OR value CONTAINS 'ready to clean'")).count, 0,
                       "The card says it, so the title doesn't repeat it")
        let detail = app.staticTexts["smartCleanSummary"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let selected = NSPredicate(format: "value MATCHES %@ OR label MATCHES %@", "[1-9][0-9]* items? selected", "[1-9][0-9]* items? selected")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: detail)], timeout: 10), .completed, detail.debugDescription)
        XCTAssertTrue(app.staticTexts["Ready to clean"].exists)
        let value = app.staticTexts["smartCleanSummaryValue"]
        XCTAssertTrue(value.exists)
        XCTAssertNotEqual(value.value as? String ?? value.label, "—", "The ticked caches release space")
        XCTAssertFalse(app.descendants(matching: .any)["meterSegments"].exists, "No storage bar on Smart clean")
        XCTAssertFalse(app.staticTexts["startupCapacityAmount"].exists, "Overview's volume card stays on Overview")
    }

    /// #355: while a cleanup runs, Cleaning up shows Overview's card with an "X freed" tag at the bar's tip and the run's
    /// categories ticking off, then the results. A dry run, held a moment per item, so every file stays.
    @MainActor func testCleaningUpShowsTheCardAndTicksCategoriesOff() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        app.launchEnvironment["CACHEDROP_TEST_CLEANUP_PAUSE"] = "5"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["smartCleanCleanUp"].waitForExistence(timeout: 10))
        app.buttons["smartCleanCleanUp"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 10))
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["Cleaning up…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["cleaningUpCard"].waitForExistence(timeout: 5), "Overview's card")
        // Each item is held 5 s, since every check here takes about a second; the core tests cover each step of the count.
        XCTAssertTrue(app.staticTexts["cleaningUpCategory-developer"].waitForExistence(timeout: 5), "The run's categories")
        let tag = app.descendants(matching: .any)["meterTipTag"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5), "The freed tag rides the tip once an item is done")
        XCTAssertTrue((tag.value as? String ?? tag.label).hasSuffix("would be freed"), tag.debugDescription)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 15), "Then the results")
        for kept in [".npm/_cacache/content-v2/sha512/ab/blob", "Library/Caches/Yarn/entry"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(kept).path), kept)
        }
    }

    /// #463, Decision 126: Clean up opens the review sheet at once with its checks running and its Clean up unavailable; the
    /// review fills in when they finish. Cancel while they run closes it for good. Checks held 4 s; a dry run, nothing is cleaned.
    @MainActor func testReviewSheetOpensAtOnceWhileItsChecksRun() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        app.launchEnvironment["CACHEDROP_TEST_REVIEW_PAUSE"] = "4"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)

        app.typeKey("2", modifierFlags: .command)
        let open = app.buttons["smartCleanCleanUp"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        let checking = app.descendants(matching: .any)["reviewChecking"]
        XCTAssertTrue(checking.waitForExistence(timeout: 2), "The sheet shows its checks running")
        let footer = app.descendants(matching: .any).matching(identifier: "sheetFooter").firstMatch
        XCTAssertFalse(footer.buttons["Clean up"].isEnabled, "Clean up waits for the checks")
        XCTAssertFalse(reviewLine(app, "permanentlyRemoved", "developer").exists)
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 15), "Then the review")
        XCTAssertFalse(checking.exists)
        XCTAssertTrue(footer.buttons["Clean up"].isEnabled)
        footer.buttons["Cancel"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))

        // Cancelled while checking: the sheet stays closed when the held checks would have ended.
        open.click()
        XCTAssertTrue(checking.waitForExistence(timeout: 2))
        footer.buttons["Cancel"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 6), "Its checks were dropped")
        XCTAssertFalse(app.staticTexts["smartCleanError"].exists, "Cancel isn't a change of choices")
        for kept in [".npm/_cacache/content-v2/sha512/ab/blob", "Library/Caches/Yarn/entry"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(kept).path), kept)
        }
    }

    /// #348: a click anywhere on a category row toggles it as its checkbox does, on Smart clean and the plan: all on when any
    /// are off, and a partly ticked category shows mixed. A dry run; nothing is cleaned.
    @MainActor func testClickingACategoryRowTogglesItOnSmartCleanAndThePlan() throws {
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            let state = try configureIsolatedState(app)
            let home = try configureCatalogHome(app)
            turnOnDryRun(app)
            _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
            defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
            let updater = home.appendingPathComponent("Library/Caches/com.example.CacheDropFixture/org.sparkle-project.Sparkle/Installation/a/Fixture.tar.xz")
            try FileManager.default.createDirectory(at: updater.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: updater)
            try Data(appearance.utf8).write(to: state.appendingPathComponent("appearance-preference.txt"))
            app.launch()
            XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
            waitForCatalogScan(app)
            let badge = app.buttons["Cleanup plan"]
            XCTAssertEqual(badge.label, "Cleanup plan, 2 categories selected",
                           "npm and Yarn count once, plus App update downloads (#531)")
            let title = "Developer caches and build files"

            app.typeKey("2", modifierFlags: .command)
            let smart = app.checkBoxes["smartCleanCategory-developer"]
            XCTAssertTrue(smart.waitForExistence(timeout: 10))
            XCTAssertEqual(smart.value as? Int, 1)
            XCTAssertTrue(smart.isEnabled)
            revealAndClick(smart, in: app)
            XCTAssertEqual(smart.value as? Int, 0, "The native checkbox unticks the category")
            XCTAssertEqual(badge.label, "Cleanup plan, 1 category selected")
            revealAndClick(smart, in: app)
            XCTAssertEqual(smart.value as? Int, 1, "The native checkbox ticks the category again")
            revealAndClick(app.staticTexts[title].firstMatch, in: app)
            XCTAssertEqual(smart.value as? Int, 0, "The row's title unticks it")
            openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH 'Choose items'")).firstMatch, in: app)
            let yarn = app.checkBoxes["smartCleanLine-yarn-cache|"]
            XCTAssertTrue(yarn.waitForExistence(timeout: 5))
            revealAndClick(yarn, in: app)
            XCTAssertFalse([0, 1].contains(smart.value as? Int), "One of two ticked reads as mixed: \(String(describing: smart.value))")
            XCTAssertEqual(badge.label, "Cleanup plan, 2 categories selected", "Partial selection still counts the category once")
            revealAndClick(app.staticTexts[title].firstMatch, in: app)
            XCTAssertEqual(smart.value as? Int, 1, "All on when any are off")

            app.typeKey("3", modifierFlags: .command)
            let plan = app.checkBoxes["planCategory-developer"]
            XCTAssertTrue(plan.waitForExistence(timeout: 10))
            XCTAssertEqual(plan.value as? Int, 1)
            XCTAssertTrue(plan.isEnabled)
            revealAndClick(plan, in: app)
            XCTAssertEqual(plan.value as? Int, 0, "The plan's native checkbox shares the same action")
            revealAndClick(plan, in: app)
            XCTAssertEqual(plan.value as? Int, 1)
            revealAndClick(app.staticTexts[title].firstMatch, in: app)
            XCTAssertEqual(plan.value as? Int, 0, "The same on the plan")
            revealAndClick(app.staticTexts[title].firstMatch, in: app)
            XCTAssertEqual(plan.value as? Int, 1)
            XCTAssertEqual(badge.label, "Cleanup plan, 2 categories selected")
            let downloads = app.checkBoxes["planCategory-downloads"]
            revealAndClick(downloads, in: app)
            XCTAssertEqual(badge.label, "Cleanup plan, 3 categories selected", "A newly selected category adds one")
            let updates = app.checkBoxes["planCategory-updaters"]
            revealAndClick(updates, in: app)
            XCTAssertEqual(badge.label, "Cleanup plan, 2 categories selected")
            app.typeKey("2", modifierFlags: .command)
            let smartUpdates = app.checkBoxes["smartCleanCategory-updaters"]
            XCTAssertTrue(smartUpdates.waitForExistence(timeout: 5))
            XCTAssertEqual(smartUpdates.value as? Int, 0, "Updater selection is shared")
            revealAndClick(smartUpdates, in: app)
            XCTAssertEqual(badge.label, "Cleanup plan, 3 categories selected", "Restoring the updater restores the count")
            app.typeKey("3", modifierFlags: .command)
            revealAndClick(app.buttons["planSort-name"], in: app)
            XCTAssertEqual(badge.label, "Cleanup plan, 3 categories selected", "Sorting preserves selection and its count")
            revealAndClick(plan, in: app)
            revealAndClick(downloads, in: app)
            XCTAssertEqual(badge.label, "Cleanup plan, 1 category selected")
            revealAndClick(updates, in: app)
            XCTAssertEqual(badge.label, "Cleanup plan", "No selected categories omits the badge's count")
        }

    }

    /// #349: one selection. What is unticked in Smart clean is unticked in the plan, the plan adds to it and cleans it, and
    /// the untick outlives the run's rescan. A dry run, so every fixture file stays.
    @MainActor func testSmartCleansTicksCarryIntoThePlanWhichAddsMoreAndCleans() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)

        // Smart clean: untick Yarn.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["smartCleanCategory-developer"].waitForExistence(timeout: 10))
        let yarnInSmartClean = app.checkBoxes["smartCleanLine-yarn-cache|"]
        openDisclosure(app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH 'Choose items'")).firstMatch, in: app)
        XCTAssertTrue(yarnInSmartClean.waitForExistence(timeout: 5))
        revealAndClick(yarnInSmartClean, in: app)
        XCTAssertEqual(yarnInSmartClean.value as? Int, 0)

        // Overview says the category no longer matches the recommended default, and opens it in the plan.
        app.typeKey("1", modifierFlags: .command)
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue((row.value as? String ?? "").contains("Selected"), String(describing: row.value))
        revealAndClick(row, in: app)
        let yarn = app.checkBoxes["planRule-yarn-cache"], npm = app.checkBoxes["planRule-npm-cache"]
        XCTAssertTrue(yarn.waitForExistence(timeout: 5))
        XCTAssertEqual(yarn.value as? Int, 0, "Unticked in Smart clean, unticked here")
        XCTAssertEqual(npm.value as? Int, 1, "Ticked in Smart clean, ticked here")

        // The plan adds the installer, which Smart clean never takes, and cleans both.
        let installer = app.checkBoxes["planCategory-downloads"]
        XCTAssertEqual(installer.value as? Int, 0)
        revealAndClick(installer, in: app)
        XCTAssertEqual(installer.value as? Int, 1)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 10))
        XCTAssertTrue(reviewLine(app, "movedToTrash", "downloads").exists)
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for kept in [".npm/_cacache/content-v2/sha512/ab/blob", "Downloads/Setup.dmg", "Library/Caches/Yarn/entry"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(kept).path), kept)
        }

        // The run's rescan keeps Yarn unticked in Smart clean.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(yarnInSmartClean.waitForExistence(timeout: 30))
        let npmInSmartClean = app.checkBoxes["smartCleanLine-npm-cache|"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: npmInSmartClean)], timeout: 30),
                       .completed, "The npm cache, found again, is ticked as recommended")
        XCTAssertEqual(yarnInSmartClean.value as? Int, 0, "The untick outlives the rescan")
    }

    /// #310: unreadable Protected items settings read as one error line with Try again, on Overview and on the page the user
    /// is on, never "Nothing to review" or "Nothing to clean"; once they can be read, Try again scans and the line goes.
    @MainActor func testUnreadableSettingsSayWhyWithTryAgainNeverNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let rules = state.appendingPathComponent("Exclusions/rules-v1.json")
        try FileManager.default.createDirectory(at: rules.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("not settings".utf8).write(to: rules)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        let notice = app.staticTexts["settingsUnreadable"]
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "Overview says the settings couldn't be read")
        XCTAssertFalse(app.descendants(matching: .any)["overviewEmpty"].exists, "Never \"nothing to clean\"")
        XCTAssertFalse(app.descendants(matching: .any)["overviewSkeleton"].exists, "Never still loading")
        XCTAssertTrue(app.links["settingsUnreadableTryAgain"].exists)

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Smart clean says it too")
        XCTAssertFalse(app.descendants(matching: .any)["smartCleanEmpty"].exists)
        XCTAssertFalse(app.staticTexts["smartCleanError"].exists)

        try FileManager.default.removeItem(at: rules)
        app.links["settingsUnreadableTryAgain"].click()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 30), "Try again scanned with the settings readable")
        XCTAssertTrue(app.checkBoxes["smartCleanCategory-developer"].waitForExistence(timeout: 30))
    }

    /// #310: an item Smart clean lists that the check at Clean up refuses is in its review as "will be skipped: <reason>", as
    /// in the plan's, never dropped without a word. The stand-in npm (a shell running npm-cli.js) starts after the scan.
    @MainActor func testSmartCleanReviewSaysWhyAnItemRefusedAtTheClickWillBeSkipped() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let script = home.appendingPathComponent(".cachedrop-test-npm/npm-cli.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "while :; do sleep 1; done\n".write(to: script, atomically: true, encoding: .utf8)
        let npm = Process()
        npm.executableURL = URL(fileURLWithPath: "/bin/sh")
        npm.arguments = [script.path]
        defer { if npm.isRunning { npm.terminate(); npm.waitUntilExit() }; app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        let developer = app.checkBoxes["smartCleanCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10), "The npm cache is listed: npm wasn't running at the scan")

        try npm.run()
        app.buttons["smartCleanCleanUp"].click()
        let skipped = app.staticTexts["reviewSkipped-npm-cache"]
        XCTAssertTrue(skipped.waitForExistence(timeout: 10), "The review says the npm cache will be skipped")
        XCTAssertTrue((skipped.value as? String ?? skipped.label).hasPrefix("npm is open, so its caches will be skipped · "), skipped.debugDescription)
        XCTAssertFalse(app.links.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reviewQuit-npm-cache|")).firstMatch.exists,
                       "A command-line tool isn't an app: no Quit, only the reason (#377)")
        app.buttons["Cancel"].click()
    }

    /// #319, #342: Smart clean's wider plan. A download not opened or changed in 7 days, under "Old downloads", Homebrew's cache and a leftover an installer receipt
    /// ties to its removed app all start ticked, each category with its consequence line. Unticking the installer leaves the
    /// rest, which the review groups by consequence. A dry run, so nothing changes and the stand-in `brew` never runs.
    @MainActor func testSmartCleanTicksAnOldInstallerAHomebrewCacheAndAReceiptTiedLeftover() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let marker = try addDeveloperCaches(home, folders: ["Library/Caches/Homebrew"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // An installer nothing has opened or changed for 200 days. Spotlight imports a .dmg the runner writes, again after every
        // change to its dates, and each import reads it, so its access time is now and the app rightly finds it recent (#335).
        // Spotlight skips a .noindex folder, and the Downloads rule looks inside Downloads' folders. The fixture home's new
        // Setup.dmg is younger than 7 days, so it stays unticked.
        let installer = home.appendingPathComponent("Downloads/Fixture.noindex/Old Setup.dmg")
        try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: 90_000).write(to: installer)
        let old = Date().addingTimeInterval(-200 * 86_400)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: installer.path)
        var times = [timeval(tv_sec: Int(old.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(old.timeIntervalSince1970), tv_usec: 0)]
        XCTAssertEqual(utimes(installer.path, &times), 0)
        // A leftover the receipt of a removed app lists. A debug test run reads receipts under the fixture home (#318).
        let leftover = home.appendingPathComponent("Library/Application Support/FooData/presets.db")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: leftover)
        try writeFixtureReceipt("com.foocorp.foo.pkg", listing: ["Applications/Foo.app", "Library/Application Support/FooData/presets.db"], in: home)
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)

        let downloads = app.checkBoxes["smartCleanCategory-downloads"], developer = app.checkBoxes["smartCleanCategory-developer"]
        let leftovers = app.checkBoxes["smartCleanCategory-leftovers"]
        XCTAssertTrue(app.descendants(matching: .any)["smartCleanHeader"].waitForExistence(timeout: 10), "Smart clean is open")
        XCTAssertTrue(downloads.waitForExistence(timeout: 30))
        for category in [downloads, developer, leftovers] { XCTAssertEqual(category.value as? Int, 1, category.identifier) }
        func text(_ line: String) -> XCUIElementQuery { app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", line, line)) }
        XCTAssertEqual(text("Old downloads").count, 1, "Smart clean names its Downloads category by what it takes (#342)")
        XCTAssertEqual(text("Goes to the Trash; Put back works").count, 2, "Installers and leftovers")
        XCTAssertEqual(text("Comes back on its own when your tools and Xcode need it; some tools clean their own").count, 1)
        // #350, #370: "Ready to clean" counts only what is released, so unticking the Trash-bound installers leaves its
        // total as it is; the item count drops by the installer.
        let total = app.staticTexts["smartCleanSummaryValue"], count = app.staticTexts["smartCleanSummary"]
        let read = { (element: XCUIElement) in element.value as? String ?? element.label }
        let totalBefore = read(total), countBefore = read(count)

        let developerTop = developer.frame.minY
        revealAndClick(downloads, in: app)
        XCTAssertEqual(downloads.value as? Int, 0)
        XCTAssertEqual(developer.value as? Int, 1)
        XCTAssertEqual(developer.frame.minY, developerTop, "Nothing above the categories moved")
        XCTAssertEqual(read(total), totalBefore, "Installers go to the Trash and were never in the total")
        XCTAssertNotEqual(read(count), countBefore, "The unticked installer leaves the count")
        app.buttons["smartCleanCleanUp"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 10), "The npm cache")
        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").exists, "Homebrew's cache")
        XCTAssertTrue(reviewLine(app, "movedToTrash", "leftovers").exists, "The receipt-tied leftover")
        XCTAssertFalse(reviewLine(app, "movedToTrash", "downloads").exists, "The unticked installer")
        app.buttons.matching(NSPredicate(format: "label == 'Clean up' AND identifier != 'smartCleanCleanUp'")).firstMatch.click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        for kept in [installer, leftover, home.appendingPathComponent("Library/Caches/Homebrew/entry")] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), kept.path)
        }
    }

    /// #306, #375: a Smart clean run rescans by itself. While that scan runs, with its progress in the bar, the page keeps
    /// the rows the run left, dimmed (#308), never skeleton rows, and what the run cleaned is gone at once; then the page
    /// fills again and can be cleaned once more.
    @MainActor func testSmartCleanKeepsItsRowsDimmedDuringTheRescanAfterARun() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        let log = home.appendingPathComponent("Library/Logs/FixtureApp/main.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: log)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.5"
        // The rescan after the run reads only the Yarn cache's rule (Decision 133): hold it, so its waiting state shows.
        app.launchEnvironment["CACHEDROP_TEST_RESCAN_PAUSE"] = "10"
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        let developer = app.checkBoxes["smartCleanCategory-developer"], logs = app.checkBoxes["smartCleanCategory-logs"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertTrue(logs.exists)
        // Logs stay: only the developer cache is cleaned.
        if logs.value as? Int != 0 { revealAndClick(logs, in: app) }
        XCTAssertEqual(logs.value as? Int, 0)
        app.buttons["smartCleanCleanUp"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label == 'Clean up' AND identifier != 'smartCleanCleanUp'")).firstMatch.click()

        let done = app.buttons["smartCleanDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        done.click()
        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForExistence(timeout: 10), "The run rescans, and the bar shows its progress")
        XCTAssertTrue(logs.waitForExistence(timeout: 5), "The row the run left stays during the rescan")
        XCTAssertFalse(logs.isEnabled, "Dimmed: it can't be clicked until the scan ends")
        XCTAssertFalse(developer.exists, "What the run cleaned never shows as still there")
        XCTAssertFalse(app.descendants(matching: .any)["smartCleanSkeleton"].exists, "Never skeleton rows over content already known")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: logs)], timeout: 120), .completed,
                       "The page fills again after the scan")
        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForNonExistence(timeout: 120))
        XCTAssertFalse(developer.exists, "The cleaned cache is gone after the scan too")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Yarn/entry").path))
        tick(logs, in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: app.buttons["smartCleanCleanUp"])], timeout: 10), .completed,
                       "Clean up works again")
    }
}

/// #235: a folder scan's status lives in the bottom bar on every screen, never in the toolbar.
final class FolderScanProgressUITests: XCTestCase {
    @MainActor func testFolderScanShowsInTheBottomBarWithStopAndReturnAndLeavesTheToolbarAlone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<5 { try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("entry-\(index).zip")) }
        // The scan holds until Stop scan, so a slow, loaded run can't finish it before the journey ends (#284).
        app.launchEnvironment["CACHEDROP_TEST_FOLDER_SCAN_PAUSE"] = "hold"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let toolbar = app.toolbars.firstMatch
        let toolbarItems = { toolbar.descendants(matching: .any).allElementsBoundByIndex.map { $0.identifier + "|" + $0.label } }
        // Downloads is scanned at launch (Decision 83) and this journey holds every scan, so stop that one first.
        let launchScan = app.buttons["Stop scan"]
        if launchScan.waitForExistence(timeout: 10) { launchScan.click() }
        XCTAssertTrue(launchScan.waitForNonExistence(timeout: 10))
        let before = toolbarItems()
        let height = actionStrip(app).frame.height

        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()

        // On the screen that started it: the folder, phase and count, and Stop scan's quiet x, in the bar; no Return to scan.
        let line = app.staticTexts["folderScanProgress"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(line.value as? String, "Scanning " + folder.lastPathComponent)
        let strip = actionStrip(app)
        for element in [line, app.staticTexts["scanPhase"], app.staticTexts["scanProgressSummary"], strip.buttons["Stop scan"]] {
            XCTAssertTrue(element.waitForExistence(timeout: 5), element.debugDescription)
            XCTAssertTrue(strip.frame.contains(element.frame), element.debugDescription)
        }
        XCTAssertTrue((app.staticTexts["scanProgressSummary"].value as? String)?.hasSuffix(" read") == true)
        assertStopScanIsTheQuietX(strip)
        XCTAssertFalse(strip.links["Return to scan"].exists)
        XCTAssertEqual(strip.frame.height, height, accuracy: 0.5)
        XCTAssertEqual(toolbarItems(), before, "The toolbar is unchanged during the scan")

        // Away from it, on Storage trends and History: Stop scan and Return to scan.
        for key in ["4", "6"] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(actionStrip(app).links["Return to scan"].waitForExistence(timeout: 5), key)
            XCTAssertTrue(actionStrip(app).buttons["Stop scan"].exists, key)
            XCTAssertTrue(app.staticTexts["scanPhase"].exists, key)
            XCTAssertEqual(actionStrip(app).frame.height, height, accuracy: 0.5, key)
        }
        // Back where it started: the link goes, so a failure here says whether the click landed or the screen was slow (#422).
        let returnToScan = actionStrip(app).links["Return to scan"]
        returnToScan.click()
        XCTAssertTrue(returnToScan.waitForNonExistence(timeout: 10), "Return to scan is still offered")
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        actionStrip(app).buttons["Stop scan"].click()
        XCTAssertTrue(line.waitForNonExistence(timeout: 10))
        XCTAssertEqual(actionStrip(app).frame.height, height, accuracy: 0.5)
        XCTAssertEqual(toolbarItems(), before, "The toolbar is unchanged after the scan")
    }

    /// #364: the recheck CacheDrop starts by itself (here Scan again's; launch and after a cleanup run the same one) reads
    /// "Checking for changes…", with no phase or count, can be stopped with the same quiet x, and offers no Return to scan on
    /// Explore storage, the screen it belongs to.
    @MainActor func testAutomaticRecheckSaysCheckingForChangesAndStopsWithTheX() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<5 { try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("entry-\(index).zip")) }
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        // Every folder scan holds 8 seconds after reading, long enough to see the recheck; a remembered folder is only
        // rechecked once it has been scanned in this run, so the first scan runs before it.
        app.launchEnvironment["CACHEDROP_TEST_FOLDER_SCAN_PAUSE"] = "8"
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)
        waitForCatalogScan(app)

        // Scan again rechecks the remembered folder.
        app.typeKey("r", modifierFlags: .command)
        let line = app.staticTexts["folderRecheckProgress"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(line.value as? String, "Checking for changes…")
        XCTAssertFalse(app.staticTexts["scanPhase"].exists)
        XCTAssertFalse(app.staticTexts["scanProgressSummary"].exists)
        assertStopScanIsTheQuietX(actionStrip(app))

        // On Explore storage: still the x, and no Return to scan.
        revealAndClick(app.links["Explore storage"], in: app)
        XCTAssertTrue(app.buttons["explorerBack"].waitForExistence(timeout: 5))
        XCTAssertTrue(line.exists)
        let strip = actionStrip(app)
        assertStopScanIsTheQuietX(strip)
        XCTAssertFalse(strip.links["Return to scan"].exists)
        strip.buttons["Stop scan"].click()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))
    }
}

/// #364: a scan's Stop in the bar's work line is the design-system x, a button (not a link) labelled and tooltipped
/// "Stop scan", inside the bar.
@MainActor func assertStopScanIsTheQuietX(_ strip: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    let stop = strip.buttons["Stop scan"]
    XCTAssertTrue(stop.waitForExistence(timeout: 5), "Stop scan is a button", file: file, line: line)
    XCTAssertFalse(strip.links["Stop scan"].exists, "Stop scan is no longer a link", file: file, line: line)
    XCTAssertTrue(strip.frame.contains(stop.frame), file: file, line: line)
    XCTAssertLessThan(stop.frame.width, 40, "A small x, not a labelled button", file: file, line: line)
}

/// #307: a review sheet closes only when the choices it was built from changed, never because background work finished.
final class ReviewSheetUITests: XCTestCase {
    @MainActor func testSmartCleanReviewStaysOpenWhenAFolderScanFinishes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_000).write(to: folder.appendingPathComponent("entry.zip"))
        // The folder scan is held a few seconds after reading the folder, long enough to open the review under it.
        app.launchEnvironment["CACHEDROP_TEST_FOLDER_SCAN_PAUSE"] = "8"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)

        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        let progress = app.staticTexts["folderScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))

        // Smart clean's review opens while the folder scan is still held.
        let link = app.links["overviewSmartClean"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        revealAndClick(link, in: app)
        let cleanUp = app.buttons["smartCleanCleanUp"]
        XCTAssertTrue(cleanUp.waitForExistence(timeout: 10))
        cleanUp.click()
        let line = reviewLine(app, "permanentlyRemoved", "developer")
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.exists, "The review opened before the folder scan finished")

        // The folder scan finishes and lists the folder's files; the review stays open, with nothing said on the page.
        XCTAssertTrue(progress.waitForNonExistence(timeout: 30))
        XCTAssertFalse(line.waitForNonExistence(timeout: 3), "The review is still open")
        XCTAssertFalse(app.staticTexts["smartCleanError"].exists)
        app.buttons["Cancel"].click()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))
    }
}

/// #321: an empty state says what's true and offers one action that leads where the user can act.
final class EmptyStateUITests: XCTestCase {
    /// A fixture home with nothing in it, read only through the DEBUG-only CACHEDROP_TEST_CATALOG_HOME seam.
    @MainActor private func configureEmptyCatalogHome(_ app: XCUIApplication) throws -> URL {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropTestHome-" + UUID().uuidString)
        FixtureFolders.track(home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        app.launchEnvironment["CACHEDROP_TEST_CATALOG_HOME"] = home.path
        return home
    }

    /// The plan on an empty home says there's nothing to clean up, and Explore storage leads to Locations,
    /// where a folder can be added, since no folder is scanned yet.
    @MainActor func testThePlanOnAnEmptyHomeSaysNothingToCleanUpAndLeadsToExploreStorage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureEmptyCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))

        app.typeKey("3", modifierFlags: .command)
        let empty = app.descendants(matching: .any)["planEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 60), "The plan says nothing was found")
        XCTAssertTrue(empty.staticTexts["Nothing to clean up right now"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["planSkeleton"].exists, "Never a skeleton and an empty state together")
        let explore = empty.buttons["planEmptyAction"]
        XCTAssertEqual(explore.label, "Explore storage")
        revealAndClick(explore, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["manageLocalRecords"].waitForExistence(timeout: 5), "With no scanned folder, it opens Locations")
    }

    /// #372: Overview on an empty home keeps every category listed as "Empty", with no Review link, and says there's
    /// nothing to clean up in one line above the list, whose Explore storage leads to Locations.
    @MainActor func testOverviewOnAnEmptyHomeListsEveryCategoryAsEmptyUnderOneLine() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureEmptyCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)

        let empty = app.descendants(matching: .any)["overviewEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Overview says nothing was found")
        XCTAssertTrue(empty.staticTexts["Nothing to clean up right now"].exists)
        // #568: nothing recommended reads "Empty", never "Up to Zero KB".
        let total = app.staticTexts["overviewRecommendedTotal"]
        XCTAssertEqual(total.value as? String ?? total.label, "Empty")
        let developer = app.descendants(matching: .any)["overviewCategory-developer"]
        XCTAssertTrue(developer.exists, "The list stays")
        XCTAssertFalse(app.buttons["overviewCategory-developer"].exists, "An empty category has no Review link")
        XCTAssertTrue((developer.value as? String)?.contains("Empty") == true, developer.debugDescription)
        XCTAssertLessThanOrEqual(empty.frame.maxY, developer.frame.minY, "The one line sits above the list")
        XCTAssertLessThan(empty.frame.height, developer.frame.height, "The empty state is one line, shorter than a row")

        // "Show N more" still folds the list.
        XCTAssertFalse(app.descendants(matching: .any)["overviewCategory-leftovers"].exists)
        app.links["overviewShowMore"].click()
        XCTAssertTrue(app.descendants(matching: .any)["overviewCategory-leftovers"].waitForExistence(timeout: 5))

        let explore = empty.links["overviewEmptyAction"]
        XCTAssertEqual(explore.label, "Explore storage")
        revealAndClick(explore, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["manageLocalRecords"].waitForExistence(timeout: 5), "With no scanned folder, it opens Locations")
    }

    /// Storage trends with no recorded scan says so and offers Scan now, which records the first baseline.
    @MainActor func testStorageTrendsWithNoScanOffersScanNowWhichRecordsABaseline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureEmptyCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No trends yet"].waitForExistence(timeout: 60), "The launch scan recorded a baseline")

        // Clearing completed history forgets the baseline, so no scan is recorded.
        app.typeKey("7", modifierFlags: .command)
        let manage = app.descendants(matching: .any)["manageLocalRecords"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        revealAndClick(manage, in: app)
        app.buttons["clearHistory"].click()
        let confirm = app.windows.firstMatch.sheets.buttons["Clear completed history"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))

        app.typeKey("5", modifierFlags: .command)
        let empty = app.descendants(matching: .any)["growthEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Storage trends says no scan is recorded")
        XCTAssertTrue(empty.staticTexts["No scans yet"].exists)
        let scanNow = empty.buttons["growthEmptyAction"]
        XCTAssertEqual(scanNow.label, "Scan again")
        scanNow.click()
        XCTAssertTrue(app.staticTexts["No trends yet"].waitForExistence(timeout: 60), "Scan now records a new baseline")
        XCTAssertFalse(empty.exists)
    }
}

/// #374: build folders of a project being worked on stay on the plan, unticked, saying why; ticked, the recently edited one
/// is cleaned (ticking is the override) and the open one is skipped, never forced, and Results say what wasn't cleaned.
extension CatalogCleanupUITests {
    @MainActor func testHeldProjectBuildsStayUntickedAndResultsSayWhatWasntCleaned() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropPicked-" + UUID().uuidString)
        // Two projects edited just now; this runner keeps a file open in one of them, as an editor would.
        for project in ["busy", "recent"] {
            let module = folder.appendingPathComponent(project + "/node_modules/dep/index.js")
            try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 50_000).write(to: module)
            try Data("{}".utf8).write(to: folder.appendingPathComponent(project + "/package.json"))
        }
        let open = try FileHandle(forReadingFrom: folder.appendingPathComponent("busy/package.json"))
        defer { try? open.close(); app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        app.launch()

        XCTAssertTrue(app.staticTexts["overviewTitle"].waitForExistence(timeout: 10))
        chooseFolderToScan(app)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()
        waitForScannedFolder(app)

        app.typeKey("3", modifierFlags: .command)
        let busy = app.checkBoxes["planProfile-project-builds-busy"], recent = app.checkBoxes["planProfile-project-builds-recent"]
        if !busy.waitForExistence(timeout: 10) { expandDisclosures(in: app) }
        XCTAssertTrue(busy.waitForExistence(timeout: 5))
        XCTAssertEqual(busy.value as? Int, 0, "Held, never ticked by default")
        XCTAssertEqual(recent.value as? Int, 0)
        XCTAssertTrue((app.buttons["Select busy"].value as? String ?? "").contains("Its project is open in an app or tool."))
        XCTAssertTrue((app.buttons["Select recent"].value as? String ?? "").contains("Its project changed in the last 7 days."))
        // Only the held build folders: untick what arrived ticked as recommended (the fixture's npm cache).
        let npm = app.checkBoxes["planRule-npm-cache"]
        if npm.exists && npm.value as? Int != 0 { revealAndClick(npm, in: app) }
        tick(busy, in: app)
        tick(recent, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "developer").waitForExistence(timeout: 5))
        cleanUpFromReview(app)

        let notCleaned = app.links["resultsNotCleaned"]
        XCTAssertTrue(notCleaned.waitForExistence(timeout: 20))
        XCTAssertTrue(notCleaned.label.hasPrefix("Not cleaned · 1 item · "), notCleaned.label)
        notCleaned.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("busy/node_modules").path), "Still in use: skipped, never forced")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("recent/node_modules").path), "Ticking overrides a recent edit")
    }
}

extension CatalogCleanupUITests {
    /// #521: sizes and names deliberately disagree at the category, rule and item levels.
    @MainActor private func addSortingFixture(in home: URL) throws {
        _ = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn"])
        try Data(repeating: 3, count: 400_000).write(to: home.appendingPathComponent("Library/Caches/Yarn/entry"))
        let old = Date().addingTimeInterval(-200 * 86_400)
        for (name, bytes) in [("Alpha.dmg", 400_000), ("Zulu.dmg", 800_000)] {
            let file = home.appendingPathComponent("Downloads/Fixture.noindex/" + name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 5, count: bytes).write(to: file)
            try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: file.path)
            var times = [timeval(tv_sec: Int(old.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(old.timeIntervalSince1970), tv_usec: 0)]
            XCTAssertEqual(utimes(file.path, &times), 0)
        }
    }

    @MainActor func testSmartCleanSortsCategoriesAndLinesAndKeepsEachPagesChoice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app), home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try addSortingFixture(in: home)
        app.launch(); waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        let name = app.buttons["smartCleanSort-name"], size = app.buttons["smartCleanSort-size"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        XCTAssertEqual(size.value as? String, "Largest first")
        expandDisclosures(in: app)
        let developer = app.checkBoxes["smartCleanCategory-developer"], downloads = app.checkBoxes["smartCleanCategory-downloads"]
        let npm = app.checkBoxes["smartCleanLine-npm-cache|"], yarn = app.checkBoxes["smartCleanLine-yarn-cache|"]
        XCTAssertTrue(npm.exists && yarn.exists)
        XCTAssertLessThan(downloads.frame.minY, developer.frame.minY)
        XCTAssertLessThan(yarn.frame.minY, npm.frame.minY)
        revealAndClick(npm, in: app)
        for (button, developerFirst, npmFirst) in [(name, true, true), (name, false, false), (size, false, false), (size, true, true)] {
            revealAndClick(button, in: app)
            XCTAssertEqual(developer.frame.minY < downloads.frame.minY, developerFirst)
            XCTAssertEqual(npm.frame.minY < yarn.frame.minY, npmFirst)
            XCTAssertEqual(npm.value as? Int, 0, "Sorting preserves an untick")
            XCTAssertEqual(yarn.value as? Int, 1)
        }
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(app.buttons["planSort-size"].value as? String, "Largest first", "Each page starts with its own default")
        app.buttons["planSort-name"].click()
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planRule-npm-cache"].value as? Int, 0, "The selection is shared across pages")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(size.value as? String, "Smallest first", "Navigation preserves Smart clean's choice")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(app.buttons["planSort-name"].value as? String, "A to Z", "Navigation preserves the plan's separate choice")
        app.terminate(); app.launch(); waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(size.value as? String, "Largest first")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(app.buttons["planSort-size"].value as? String, "Largest first", "A new launch resets both sorts")
    }

    @MainActor func testCleanupPlanSortsRulesAndItemsWithinTheirCategoriesWithoutChangingTicks() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app), home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try addSortingFixture(in: home)
        app.launch(); waitForCatalogScan(app)
        app.typeKey("3", modifierFlags: .command)
        let name = app.buttons["planSort-name"], size = app.buttons["planSort-size"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        expandDisclosures(in: app)
        let npm = app.checkBoxes["planRule-npm-cache"], yarn = app.checkBoxes["planRule-yarn-cache"]
        let alpha = app.checkBoxes["planItem-Alpha.dmg"], zulu = app.checkBoxes["planItem-Zulu.dmg"]
        let developer = app.checkBoxes["planCategory-developer"], downloads = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(npm.exists && yarn.exists && alpha.exists && zulu.exists)
        XCTAssertLessThan(downloads.frame.minY, developer.frame.minY)
        XCTAssertLessThan(yarn.frame.minY, npm.frame.minY)
        XCTAssertLessThan(zulu.frame.minY, alpha.frame.minY)
        revealAndClick(alpha, in: app)
        let ticked = alpha.value as? Int
        for (button, developerFirst, smallerFirst) in [(name, true, true), (name, false, false), (size, false, false), (size, true, true)] {
            revealAndClick(button, in: app)
            XCTAssertEqual(developer.frame.minY < downloads.frame.minY, developerFirst)
            XCTAssertEqual(npm.frame.minY < yarn.frame.minY, smallerFirst)
            XCTAssertEqual(alpha.frame.minY < zulu.frame.minY, smallerFirst)
            XCTAssertLessThan(downloads.frame.minY, min(alpha.frame.minY, zulu.frame.minY), "Items stay below their own category")
            XCTAssertLessThan(developer.frame.minY, min(npm.frame.minY, yarn.frame.minY), "Rules stay below their own category")
            XCTAssertEqual(alpha.value as? Int, ticked, "Sorting never changes a tick")
        }
    }
}
