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

/// Adds developer caches and a stand-in `brew` that would leave a marker if it ever ran.
@MainActor func addDeveloperCaches(_ home: URL, folders: [String]) throws -> URL {
    for folder in folders {
        let file = home.appendingPathComponent(folder + "/entry")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 50_000).write(to: file)
    }
    let marker = home.appendingPathComponent("brew-ran")
    let brew = home.appendingPathComponent(".still-test-tools/brew")
    try FileManager.default.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: brew, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
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

        XCTAssertTrue(app.staticTexts["Clear Homebrew cache"].waitForExistence(timeout: 5))
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
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: simctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: simctl.path)
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
        XCTAssertTrue(running.label.contains("Xcode is running"), running.label)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear Xcode DerivedData"].waitForExistence(timeout: 5))
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

        // Opening a category from Overview never preselects it.
        let category = app.checkBoxes["planRule-npm-cache"]
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

        XCTAssertTrue(app.staticTexts["Clear npm cache"].waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache/content-v2/sha512/ab/blob").path))
    }

    @MainActor func testPreviewOnlyDownloadsInstallerIsChosenOnItsOwnAndStaysInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // Nothing is preselected; the installer is chosen on its own.
        let category = app.checkBoxes["planRule-downloads-installers"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        let item = app.checkBoxes["planItem-Setup.dmg"]
        if !item.waitForExistence(timeout: 2) { expandDisclosures(in: app) }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? Int, 0)
        revealAndClick(item, in: app)
        XCTAssertEqual(item.value as? Int, 1)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Move to Trash: Installers in Downloads"].waitForExistence(timeout: 5))
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

        let rule = app.checkBoxes["planRule-chrome-code-sign-clones"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        XCTAssertEqual(rule.value as? Int, 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Up to '")).firstMatch.exists)
        revealAndClick(rule, in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear Chrome code-sign copies"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'code_sign_clone.old'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'code_sign_clone.new'")).firstMatch.exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists)
        XCTAssertTrue(app.staticTexts["Estimated before cleanup · Upper bound"].exists)
        XCTAssertTrue(app.staticTexts["Measured freed space"].exists)
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

        XCTAssertTrue(app.checkBoxes["planRule-chrome-cache"].waitForExistence(timeout: 5))
        let profile = app.checkBoxes["planProfile-chrome-cache-Default"]
        XCTAssertTrue(profile.exists)
        XCTAssertTrue(app.checkBoxes["planProfile-chrome-cache-Profile 1"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Cookies' OR label CONTAINS 'Local Storage'")).firstMatch.exists)
        XCTAssertEqual(profile.value as? Int, 0)
        revealAndClick(profile, in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear Google Chrome cache"].waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would delete"].exists || app.staticTexts["Skipped"].exists)
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
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

        let update = app.checkBoxes["planProfile-updater-downloads-com.example.StillFixture"]
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["planRule-crash-reports"].exists)
        XCTAssertTrue(app.checkBoxes["planRule-app-logs"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'FixtureAgent' OR identifier CONTAINS 'FixtureAgent'")).firstMatch.exists)
        revealAndClick(update, in: app)
        revealAndClick(app.checkBoxes["planRule-crash-reports"], in: app)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear App update downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Clear Crash reports"].exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }
}
