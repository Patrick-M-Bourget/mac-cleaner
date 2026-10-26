import XCTest

/// A fixture home with an npm cache and a Downloads installer, inside the runner's temp folder. The app reads it only through
/// the DEBUG-only STILL_TEST_CATALOG_HOME seam, so the journey never touches real user paths.
@MainActor func configureCatalogHome(_ app: XCUIApplication) throws -> URL {
    let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestHome-" + UUID().uuidString)
    let file = home.appendingPathComponent(".npm/_cacache/content-v2/sha512/ab/blob")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: 200_000).write(to: file)
    let installer = home.appendingPathComponent("Downloads/Setup.dmg")
    try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: 120_000).write(to: installer)
    app.launchEnvironment["STILL_TEST_CATALOG_HOME"] = home.path
    return home
}

/// Writes an executable stand-in tool into the fixture home's `.still-test-tools`. The sandboxed runner quarantines every
/// file it writes and can't clear that; the app clears it on stand-ins it finds there (debug test seam), so they can run.
@MainActor func writeStandInTool(_ script: String, to tool: URL) throws {
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try script.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
}

/// Adds developer caches and a stand-in `brew` that would leave a marker if it ever ran.
@MainActor func addDeveloperCaches(_ home: URL, folders: [String]) throws -> URL {
    for folder in folders {
        let file = home.appendingPathComponent(folder + "/entry")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 50_000).write(to: file)
    }
    let marker = home.appendingPathComponent("brew-ran")
    let brew = home.appendingPathComponent(".still-test-tools/brew")
    try writeStandInTool("#!/bin/sh\ntouch '\(marker.path)'\n", to: brew)
    return marker
}

/// Scrolls `element` fully into view before a click. Still's window may open at its 900×640 minimum (the saved frame is
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
@MainActor func revealAndClick(_ element: XCUIElement, in app: XCUIApplication) {
    reveal(element, in: app)
    element.click()
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
    @MainActor func testDeveloperCachesShowOnlyWhenPresentAndPreviewNeverRunsTheTool() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn", ".cargo/registry", ".gradle/caches", "Library/Caches/Homebrew", "Library/Caches/ccache"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        // Overview has one row per category; the plan lists the rules that found something.
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ccache'")).firstMatch.exists)
        revealAndClick(developer, in: app)

        XCTAssertTrue(app.descendants(matching: .any)["planRule-homebrew"].waitForExistence(timeout: 5))
        for present in ["npm-cache", "yarn-cache", "cargo-cache", "gradle-cache"] { XCTAssertTrue(app.descendants(matching: .any)["planRule-" + present].exists, present) }
        for absent in ["pnpm-store", "uv-cache", "pip-cache", "cocoapods-cache"] { XCTAssertFalse(app.descendants(matching: .any)["planRule-" + absent].exists, absent) }
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ccache'")).firstMatch.exists)
        // Opening a category from Overview never preselects it.
        let homebrew = app.checkBoxes["planRule-homebrew"]
        XCTAssertEqual(homebrew.value as? Int, 0)
        revealAndClick(homebrew, in: app)
        XCTAssertEqual(homebrew.value as? Int, 1)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would run"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
    }


    /// Xcode build data in a fixture home. The journey itself runs under xcodebuild or Xcode, so
    /// DerivedData must show as refused with its reason; the stand-in simctl must never run in preview.
    @MainActor func testXcodeBuildDataIsRefusedWhileXcodeRunsAndPreviewNeverRunsSimctl() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        _ = try addDeveloperCaches(home, folders: ["Library/Developer/Xcode/DerivedData/Still-abc/Build/Products/Debug/Still.app",
                                                   "Library/Developer/Xcode/Archives/2026-10-01/Still.xcarchive",
                                                   "Library/Developer/Xcode/iOS DeviceSupport/16.4 (20E247)",
                                                   "Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)",
                                                   "Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)",
                                                   "Library/Developer/CoreSimulator/Devices/0A1B2C3D-0000-0000-0000-000000000000"])
        let marker = home.appendingPathComponent("simctl-ran")
        let simctl = home.appendingPathComponent(".still-test-tools/simctl")
        try writeStandInTool("#!/bin/sh\ntouch '\(marker.path)'\n", to: simctl)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'Archives'")).firstMatch.exists)
        revealAndClick(developer, in: app)
        XCTAssertTrue(app.checkBoxes["planRule-xcode-device-support"].waitForExistence(timeout: 5))

        for rule in ["xcode-derived-data", "xcode-simulators"] {
            let box = app.checkBoxes["planRule-" + rule]
            XCTAssertTrue(box.waitForExistence(timeout: 5), rule)
            revealAndClick(box, in: app)
        }
        // The plan says why DerivedData will be refused: this journey runs under xcodebuild or Xcode.
        let running = app.staticTexts["planRunning-xcode-derived-data"]
        XCTAssertTrue(running.waitForExistence(timeout: 5))
        XCTAssertTrue((running.value as? String ?? "").contains("Xcode is running"), running.debugDescription)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would run"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Still-abc/Build/Products/Debug/Still.app/entry").path))
    }


    @MainActor func testPreviewOnlyCleanupOfAFixtureCategoryReachesResultsAndChangesNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["0 bytes"].exists)
        revealAndClick(row, in: app)

        // Opening a category from Overview never preselects it. One rule with one item: the category checkbox is the choice.
        let category = app.checkBoxes["planCategory-developer"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        revealAndClick(category, in: app)

        let preview = app.checkBoxes["previewOnlyToggle"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(preview.value as? Int, 1)
        let review = app.buttons["Review cleanup"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        review.click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        XCTAssertFalse(reviewLine(app, "commandsRun", "developer").exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache/content-v2/sha512/ab/blob").path))
    }

    /// #123: after a cleanup, an Overview category opens a fresh plan, not the last run's results.
    @MainActor func testOverviewCategoryAfterACleanupOpensAFreshPlanWithThatCategoryOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        let rule = app.checkBoxes["planRule-npm-cache"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        revealAndClick(rule, in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // A fresh plan: the category is open and nothing is ticked.
        XCTAssertTrue(rule.waitForExistence(timeout: 5), "The category opened from Overview shows its items")
        XCTAssertFalse(app.staticTexts["catalogPreviewNotice"].exists, "The last run's results are gone")
        XCTAssertEqual(rule.value as? Int, 0)
    }

    @MainActor func testPreviewOnlyDownloadsInstallerIsChosenOnItsOwnAndStaysInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // A second installer, so the plan lists the items to choose from.
        try Data(repeating: 5, count: 90_000).write(to: home.appendingPathComponent("Downloads/Other.pkg"))
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // Nothing is preselected; the installer is chosen on its own.
        let category = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        let item = app.checkBoxes["planItem-Setup.dmg"]
        if !item.waitForExistence(timeout: 2) { expandDisclosures(in: app) }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? Int, 0)
        XCTAssertFalse(app.staticTexts["liveSelectionTrash"].exists)
        revealAndClick(item, in: app)
        XCTAssertEqual(item.value as? Int, 1)
        XCTAssertEqual(app.checkBoxes["planItem-Other.pkg"].value as? Int, 0)
        // The installer goes to Trash, so the summary says how much of the total does.
        XCTAssertTrue(app.staticTexts["liveSelectionTrash"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.staticTexts["liveSelectionTrash"].value as? String)?.hasSuffix(" of this goes to Trash") == true)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "movedToTrash", "downloads").waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would move to Trash"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Downloads/Setup.dmg").path))
    }

    @MainActor func testChromeCodeSignCopiesAreOfferedAsAnUpperBoundAndTheNewestIsKept() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        // A stand-in for the user's /private/var/folders entry, read through the same DEBUG-only home seam.
        let clones = home.appendingPathComponent(".still-test-user-folder/X/com.google.Chrome.code_sign_clone")
        for (name, age) in [("code_sign_clone.old", -86_400.0), ("code_sign_clone.new", 0)] {
            let executable = clones.appendingPathComponent(name + "/Google Chrome.app/Contents/MacOS/Google Chrome")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 150_000).write(to: executable)
            try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(age)], ofItemAtPath: clones.appendingPathComponent(name).path)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // One copy is offered (the newest is kept), so the category checkbox is the choice.
        let rule = app.checkBoxes["planCategory-browser"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        XCTAssertEqual(rule.value as? Int, 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Up to '")).firstMatch.exists)
        revealAndClick(rule, in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "browser").waitForExistence(timeout: 5))
        // The review lists each copy in a collapsed file list.
        revealAndClick(app.disclosureTriangles.matching(NSPredicate(format: "label ENDSWITH 'Show files'")).firstMatch, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'code_sign_clone.old'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'code_sign_clone.new'")).firstMatch.exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists)
        // A preview reports one line; the copies share disk space, so it is an upper bound.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Preview · Nothing changed · Up to '")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Measured freed space"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clones.appendingPathComponent("code_sign_clone.old").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clones.appendingPathComponent("code_sign_clone.new").path))
    }

    /// Chrome's caches are listed per profile with sizes; its profile data never appears and is never touched.
    /// A Chrome running on this Mac makes the review skip the caches, which the journey also accepts.
    @MainActor func testBrowserCachesShowPerProfileSizesAndPreviewLeavesProfilesAlone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // One rule with several items: its profiles are listed without a rule row.
        XCTAssertTrue(app.checkBoxes["planCategory-browser"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planRule-chrome-cache"].exists)
        let profile = app.checkBoxes["planProfile-chrome-cache-Default"]
        XCTAssertTrue(profile.exists)
        XCTAssertTrue(app.checkBoxes["planProfile-chrome-cache-Profile 1"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Cookies' OR label CONTAINS 'Local Storage' OR value CONTAINS 'Cookies' OR value CONTAINS 'Local Storage'")).firstMatch.exists)
        XCTAssertEqual(profile.value as? Int, 0)
        revealAndClick(profile, in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "browser").waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists || app.staticTexts["Skipped"].exists)
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// #117: without Full Disk Access (the fixture's Safari folder refuses to open), Safari's cache is listed as not
    /// accessible with the explanation, never sized as 0. With access, only its cache folder is offered, and a preview
    /// leaves the cache and Safari's history in place.
    @MainActor func testSafariCacheIsNotAccessibleWithoutFullDiskAccessAndOfferedWithIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let denied = app.descendants(matching: .any)["overviewNotAccessible"]
        XCTAssertTrue(denied.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 location needs Full Disk Access ·"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["overviewCategory-browser"].exists, "Nothing found, so no 0-byte browser row")
        revealAndClick(denied.links["fullDiskAccessLink"], in: app)
        XCTAssertTrue(app.staticTexts["Full Disk Access is optional"].waitForExistence(timeout: 5))
        app.buttons["closeFullDiskAccess"].click() // Never "Open System Settings".
        app.terminate()

        // Granted: the Safari folder opens.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.launch()
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["overviewNotAccessible"].exists)
        revealAndClick(row, in: app)
        let rule = app.checkBoxes["planCategory-browser"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        revealAndClick(rule, in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "browser").waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in [history, cache] { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// Updater downloads and logs show as their own Overview categories. A log folder holding a git checkout never appears,
    /// and a preview run leaves every fixture file in place. Per-app caches need an installed app, so unit tests cover them.
    @MainActor func testUpdaterDownloadsAndLogsAreTheirOwnCategoriesAndPreviewLeavesThemInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let files = ["Library/Caches/com.example.StillFixture/org.sparkle-project.Sparkle/Installation/a/Fixture.tar.xz",
                     "Library/Logs/DiagnosticReports/Fixture-2026-10-26.ips", "Library/Logs/FixtureApp/main.log",
                     "Library/Logs/FixtureAgent/checkout/.git/HEAD"].map(home.appendingPathComponent)
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
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
        revealAndClick(update, in: app)
        revealAndClick(app.checkBoxes["planRule-crash-reports"], in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "updaters").waitForExistence(timeout: 5))
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "logs").exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// A stand-in `docker` in the fixture: `system df` prints `df` (or fails, as with no daemon); anything else leaves a marker.
    @MainActor private func addDocker(_ home: URL, daemonAnswers: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".docker"), withIntermediateDirectories: true)
        let marker = home.appendingPathComponent("docker-pruned")
        let docker = home.appendingPathComponent(".still-test-tools/docker")
        let df = daemonAnswers
            ? #"echo '{"Active":"1","Reclaimable":"2.5GB (62%)","Size":"4GB","TotalCount":"5","Type":"Images"}'; echo '{"Active":"0","Reclaimable":"1.2GB","Size":"1.2GB","TotalCount":"9","Type":"Build Cache"}'"#
            : "echo 'Cannot connect to the Docker daemon' >&2; exit 1"
        try writeStandInTool("#!/bin/sh\nif test \"$*\" = 'system df --format json'; then \(df); else touch '\(marker.path)'; fi\n", to: docker)
        return marker
    }

    @MainActor func testDockerPruneKindsAreSeparateChoicesAndPreviewNeverPrunes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDocker(home, daemonAnswers: true)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
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
        revealAndClick(app.checkBoxes["planRule-docker-build-cache"], in: app)
        XCTAssertEqual(app.checkBoxes["planRule-docker-images"].value as? Int, 0)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "commandsRun", "developer").waitForExistence(timeout: 5))
        // The exact command shows with the files; only the chosen kind is there.
        revealAndClick(app.disclosureTriangles.matching(NSPredicate(format: "label ENDSWITH 'Show files'")).firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["docker builder prune -a -f"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["docker image prune -a -f"].exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        // Messages show on demand.
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'would run docker builder prune -a -f'")).firstMatch.exists)
        app.descendants(matching: .any)["resultsDetailsToggle"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'would run docker builder prune -a -f'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    @MainActor func testDockerShowsANoticeInsteadOfRowsWhenItsDaemonIsntRunning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDocker(home, daemonAnswers: false)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        XCTAssertTrue(app.staticTexts["planNote-docker-images"].waitForExistence(timeout: 5))
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
        try JSONEncoder().encode(states).write(to: home.appendingPathComponent(".still-test-icloud.json"))
    }

    @MainActor func testLocalCopiesAreChosenAndPreviewEvictsNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        try addICloudFiles(home)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
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
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "localCopiesRemoved", "icloud").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'stay in iCloud and download again when you open them'")).firstMatch.exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would remove local copy"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".still-test-icloud-evicted").path))
    }
}

/// Large and old files explorer (#113): a picked fixture folder, chosen file by file, previewed, left in place.
extension CatalogCleanupUITests {
    @MainActor func testPickedFolderListsOldFilesUnchosenAndPreviewLeavesThemInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillPicked-" + UUID().uuidString)
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.links["Choose a folder…"].click()
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()

        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        explore.click()
        // A segmented picker is a radio group to accessibility.
        let mode = app.radioGroups["explorerMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.radioButtons["Large and old files"].click()

        // Only the old file is listed, and nothing is preselected.
        let item = app.checkBoxes["explorerChoose-old-archive.zip"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["explorerChoose-recent.zip"].exists)
        XCTAssertEqual(item.value as? Int, 0)
        item.click()
        XCTAssertEqual(item.value as? Int, 1)
        app.buttons["View cleanup plan"].click()

        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "files").waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would move to Trash"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }
}

final class GuidanceUITests: XCTestCase {
    /// A Photos library, Xcode archives, unreadable Messages attachments and two local snapshots in the fixture home.
    /// The snapshot count comes from a debug fixture file, so tmutil never runs, and opening is a debug no-op.
    @MainActor private func addGuidanceData(_ home: URL) throws -> URL {
        for path in ["Pictures/Photos Library.photoslibrary/originals/a.heic", "Library/Developer/Xcode/Archives/2026-10-26/App.xcarchive/Info.plist",
                     "Library/Messages/Attachments/ab/photo.jpg"] {
            let file = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 5, count: 90_000).write(to: file)
        }
        try "2".write(to: home.appendingPathComponent(".still-test-snapshots"), atomically: true, encoding: .utf8)
        let locked = home.appendingPathComponent("Library/Messages/Attachments")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        return locked
    }

    @MainActor func testGuidanceCategoriesShowSizeOrNotAccessibleAndNeverJoinThePlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let locked = try addGuidanceData(home)
        defer {
            app.terminate(); try? FileManager.default.removeItem(at: state)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        // One Overview row leads to the App-managed storage page.
        let entry = app.buttons["overviewAppManaged"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["guidance-photos-library"].exists)
        revealAndClick(entry, in: app)
        let photos = app.buttons["guidance-photos-library"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        XCTAssertEqual(photos.label, "Open Photos")
        XCTAssertTrue((app.buttons["guidance-messages-attachments"].value as? String)?.contains("Needs access") == true)
        // One access note for the page, never a link per row.
        XCTAssertTrue(app.descendants(matching: .any)["guidanceAccess"].exists)
        XCTAssertEqual(app.links.matching(identifier: "fullDiskAccessLink").count, 1)
        XCTAssertTrue((app.buttons["guidance-time-machine-snapshots"].value as? String)?.contains("2 snapshots · Size unknown") == true)
        XCTAssertTrue(app.buttons["guidance-xcode-archives"].exists)
        revealAndClick(photos, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would open Photos.")

        app.buttons["appManagedBack"].click()
        revealAndClick(app.buttons["overviewCategory-developer"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["planCategory-developer"].waitForExistence(timeout: 5))
        for id in ["photos-library", "xcode-archives", "messages-attachments", "time-machine-snapshots"] {
            XCTAssertFalse(app.descendants(matching: .any)["planRule-" + id].exists, id)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Pictures/Photos Library.photoslibrary/originals/a.heic").path))
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let line = app.staticTexts["overviewTrash"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        let text = [line.label, line.value as? String ?? ""].first { !$0.isEmpty } ?? ""
        XCTAssertTrue(text.hasPrefix("Trash holds "), "label: \(line.label), value: \(String(describing: line.value))")
        revealAndClick(app.links["overviewTrashOpen"], in: app)
        let marker = home.appendingPathComponent(".still-test-opened-trash")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), home.appendingPathComponent(".Trash").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path), "Opening the Trash changes nothing in it")
    }
}
