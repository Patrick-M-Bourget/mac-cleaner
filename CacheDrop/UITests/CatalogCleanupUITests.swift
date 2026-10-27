import XCTest

/// A fixture home with an npm cache and a Downloads installer, inside the runner's temp folder. The app reads it only through
/// the DEBUG-only CACHEDROP_TEST_CATALOG_HOME seam, so the journey never touches real user paths.
@MainActor func configureCatalogHome(_ app: XCUIApplication) throws -> URL {
    let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CacheDropTestHome-" + UUID().uuidString)
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

/// The review sheet has two buttons, Cancel and Clean up, and no preview mode.
@MainActor func cleanUpFromReview(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Cancel"].exists)
    XCTAssertFalse(app.buttons["Run preview"].exists)
    app.buttons["Clean up"].click()
}

/// Writes an executable stand-in tool into the fixture home's `.cachedrop-test-tools`. The sandboxed runner quarantines every
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
    let brew = home.appendingPathComponent(".cachedrop-test-tools/brew")
    try writeStandInTool("#!/bin/sh\ntouch '\(marker.path)'\n", to: brew)
    return marker
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
@MainActor func revealAndClick(_ element: XCUIElement, in app: XCUIApplication) {
    reveal(element, in: app)
    element.click()
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
        // The npm cache is among the first locations, Downloads comes later: its row and the total show up mid-scan.
        XCTAssertTrue(app.buttons["overviewCategory-developer"].waitForExistence(timeout: 10))
        XCTAssertTrue(progress.exists, "The developer row appeared before the scan finished")
        let total = app.staticTexts["overviewRecommendedTotal"]
        XCTAssertTrue((total.value as? String)?.hasPrefix("Up to ") == true, total.debugDescription)
        XCTAssertFalse(app.staticTexts["Nothing to review in the known locations."].exists)

        XCTAssertTrue(progress.waitForNonExistence(timeout: 60))
        XCTAssertTrue(app.buttons["overviewCategory-downloads"].exists)
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
                                                   ".android/avd/Pixel.avd"])
        let marker = home.appendingPathComponent("simctl-ran")
        let simctl = home.appendingPathComponent(".cachedrop-test-tools/simctl")
        // Lists one shut-down simulator and one unused runtime (#134); any other call leaves the marker.
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"0A1B2C3D-0000-0000-0000-000000000000","name":"iPhone 16","state":"Shutdown","isAvailable":true}]}}"#
        let runtimes = #"{"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB":{"identifier":"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB","deletable":true,"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.watchOS-11-0","version":"11.0","build":"22R349","sizeBytes":4500000000}}"#
        try writeStandInTool("#!/bin/sh\ncase \"$*\" in\n\"list devices -j\") echo '\(devices)' ;;\n\"runtime list -j\") echo '\(runtimes)' ;;\n*) touch '\(marker.path)' ;;\nesac\n", to: simctl)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
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
            revealAndClick(box, in: app)
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
        let script = home.appendingPathComponent(".cachedrop-test-npm/npm-cli.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "while :; do sleep 1; done\n".write(to: script, atomically: true, encoding: .utf8)
        let npm = Process()
        npm.executableURL = URL(fileURLWithPath: "/bin/sh")
        npm.arguments = [script.path]
        try npm.run()
        defer { if npm.isRunning { npm.terminate() }; app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
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

        // The plan's bottom bar has only Review cleanup.
        XCTAssertFalse(app.descendants(matching: .any)["previewOnlyToggle"].exists)
        let review = app.buttons["Review cleanup"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        review.click()

        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        XCTAssertFalse(reviewLine(app, "commandsRun", "developer").exists)
        XCTAssertFalse(app.staticTexts["reviewPreviewNotice"].exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["Deleted"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["catalogPreviewNotice"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache").path))
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        // One rule with one item: the category checkbox is the choice.
        let rule = app.checkBoxes["planCategory-developer"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        revealAndClick(rule, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        let dryRun = app.descendants(matching: .any)["dryRunToggle"]
        XCTAssertTrue(dryRun.waitForExistence(timeout: 5))
        XCTAssertEqual(dryRun.value as? Int, 0)
        dryRun.click()
        XCTAssertEqual(dryRun.value as? Int, 1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(dryRun.waitForNonExistence(timeout: 5))
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let denied = app.descendants(matching: .any)["overviewNotAccessible"]
        XCTAssertTrue(denied.waitForExistence(timeout: 10))
        // Safari's cache is one of the places named; others that need access too (sandboxed app caches, #133) add to the count.
        XCTAssertTrue(denied.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Full Disk Access ·' AND value CONTAINS 'Safari cache'")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["overviewCategory-browser"].exists, "Nothing found, so no 0-byte browser row")
        revealAndClick(denied.links["fullDiskAccessLink"], in: app)
        XCTAssertTrue(app.staticTexts["Broader access is optional"].waitForExistence(timeout: 5))
        app.buttons["closeFullDiskAccess"].click() // "Not now", never "Open System Settings".
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        // #125: a clear Scan a folder action on Overview picks the folder and scans it right away.
        app.buttons["overviewScanFolder"].click()
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
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(openLargeAndOld(app).waitForExistence(timeout: 30))
    }

    /// Opens Explore storage from Overview in its Large and old files mode; returns the fixture's old file toggle.
    @MainActor private func openLargeAndOld(_ app: XCUIApplication) -> XCUIElement {
        let explore = app.links["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 30))
        explore.click()
        let mode = app.radioGroups["explorerMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        mode.radioButtons["Large and old files"].click()
        return app.checkBoxes["explorerChoose-old-archive.zip"]
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
        let workspaces = app.buttons["guidance-agent-workspaces"]
        XCTAssertEqual(workspaces.label, "Open in Finder")
        XCTAssertTrue((workspaces.value as? String)?.contains("1 workspace · 1 has uncommitted changes") == true,
                      String(describing: workspaces.value))
        revealAndClick(photos, in: app)
        XCTAssertTrue(app.staticTexts["guidanceStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guidanceStatus"].value as? String, "Test run: would open Photos.")

        app.buttons["appManagedBack"].click()
        revealAndClick(app.buttons["overviewCategory-developer"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["planCategory-developer"].waitForExistence(timeout: 5))
        for id in ["photos-library", "xcode-archives", "messages-attachments", "time-machine-snapshots", "agent-workspaces"] {
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let developer = app.buttons["meterSegment-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 15))
        XCTAssertTrue(developer.label.hasPrefix("Developer caches and build files, up to "), developer.label)
        XCTAssertTrue(app.buttons["meterSegment-downloads"].exists)
        let trash = app.descendants(matching: .any)["meterSegment-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 10))
        XCTAssertTrue(trash.label.hasPrefix("In Trash, "), trash.label)
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

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let line = app.staticTexts["overviewTrash"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        func lineText() -> String { [line.label, line.value as? String ?? ""].first { !$0.isEmpty } ?? "" }
        let before = lineText()
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

        app.typeKey("5", modifierFlags: .command)
        // The run's row is one button whose label holds its title.
        let run = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Put back from Trash' OR value CONTAINS 'Put back from Trash'")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(lineText(), before, "The Trash holds what it held before the run")
    }
}

extension CatalogCleanupUITests {
    /// #137, #141: Smart clean, opened from Overview's link, lists only data that rebuilds itself, all ticked and each untickable.
    /// Its Clean up opens the review; the installer (Trash) and Homebrew (a tool) stay out. The Cleanup plan keeps its own selection.
    @MainActor func testSmartCleanReviewsOnlyRebuildableItemsAndKeepsThePlanSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        let marker = try addDeveloperCaches(home, folders: ["Library/Caches/Homebrew", "Library/Caches/Yarn"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))

        // The Cleanup plan's own choice: the installer.
        app.typeKey("3", modifierFlags: .command)
        let installer = app.checkBoxes["planCategory-downloads"]
        XCTAssertTrue(installer.waitForExistence(timeout: 10))
        revealAndClick(installer, in: app)
        XCTAssertEqual(installer.value as? Int, 1)

        app.typeKey("1", modifierFlags: .command)
        let link = app.links["overviewSmartClean"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue(link.label.hasPrefix("Smart clean · "), link.label)
        revealAndClick(link, in: app)

        // Only rebuildable data, all ticked; the installer is not in it, and Yarn can be unticked.
        let developer = app.checkBoxes["smartCleanCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertEqual(developer.value as? Int, 1)
        XCTAssertFalse(app.checkBoxes["smartCleanCategory-downloads"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["smartCleanNotIncluded-downloads"].exists)
        let yarn = app.checkBoxes["smartCleanLine-yarn-cache|"]
        XCTAssertTrue(yarn.waitForExistence(timeout: 5))
        XCTAssertEqual(app.checkBoxes["smartCleanLine-npm-cache|"].value as? Int, 1)
        revealAndClick(yarn, in: app)
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
        for kept in [".npm/_cacache/content-v2/sha512/ab/blob", "Downloads/Setup.dmg", "Library/Caches/Homebrew/entry", "Library/Caches/Yarn/entry"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(kept).path), kept)
        }

        // The Smart clean run left the Cleanup plan's choice alone.
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(installer.waitForExistence(timeout: 15))
        let chosen = NSPredicate(format: "value == 1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chosen, object: installer)], timeout: 15), .completed, "The installer is still chosen")
    }
}
