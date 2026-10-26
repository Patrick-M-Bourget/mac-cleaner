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

final class CatalogCleanupUITests: XCTestCase {
    @MainActor func testDeveloperCachesShowOnlyWhenPresentAndPreviewNeverRunsTheTool() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDeveloperCaches(home, folders: ["Library/Caches/Yarn", ".cargo/registry", ".gradle/caches", "Library/Caches/Homebrew", "Library/Caches/ccache"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        // Overview has one row per category; the plan lists the rules that found something.
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ccache'")).firstMatch.exists)
        developer.click()

        XCTAssertTrue(app.descendants(matching: .any)["planRule-homebrew"].waitForExistence(timeout: 5))
        for present in ["npm-cache", "yarn-cache", "cargo-cache", "gradle-cache"] { XCTAssertTrue(app.descendants(matching: .any)["planRule-" + present].exists, present) }
        for absent in ["pnpm-store", "uv-cache", "pip-cache", "cocoapods-cache"] { XCTAssertFalse(app.descendants(matching: .any)["planRule-" + absent].exists, absent) }
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ccache'")).firstMatch.exists)
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let developer = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'Archives'")).firstMatch.exists)
        developer.click()
        XCTAssertTrue(app.checkBoxes["planRule-xcode-device-support"].waitForExistence(timeout: 5))

        for rule in ["xcode-derived-data", "xcode-simulators"] {
            let box = app.checkBoxes["planRule-" + rule]
            XCTAssertTrue(box.waitForExistence(timeout: 5), rule)
            box.click()
        }
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        let refused = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Xcode is running'")).firstMatch
        XCTAssertTrue(refused.waitForExistence(timeout: 5))
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["0 bytes"].exists)
        row.click()

        // Opening a category from Overview never preselects it.
        let category = app.checkBoxes["planRule-npm-cache"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        category.click()

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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-downloads"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        // Nothing is preselected; the installer is chosen on its own.
        let category = app.checkBoxes["planRule-downloads-installers"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? Int, 0)
        let item = app.checkBoxes["planItem-Setup.dmg"]
        if !item.waitForExistence(timeout: 2) { app.disclosureTriangles.firstMatch.click() }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? Int, 0)
        item.click()
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        let rule = app.checkBoxes["planRule-chrome-code-sign-clones"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        XCTAssertEqual(rule.value as? Int, 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Up to '")).firstMatch.exists)
        rule.click()
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        XCTAssertTrue(app.checkBoxes["planRule-chrome-cache"].waitForExistence(timeout: 5))
        let profile = app.checkBoxes["planProfile-chrome-cache-Default"]
        XCTAssertTrue(profile.exists)
        XCTAssertTrue(app.checkBoxes["planProfile-chrome-cache-Profile 1"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Cookies' OR label CONTAINS 'Local Storage'")).firstMatch.exists)
        XCTAssertEqual(profile.value as? Int, 0)
        profile.click()
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear Google Chrome cache"].waitForExistence(timeout: 5))
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let denied = app.descendants(matching: .any)["overviewNotAccessible-safari-cache"]
        XCTAssertTrue(denied.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Not accessible"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["overviewCategory-browser"].exists, "Nothing found, so no 0-byte browser row")
        denied.buttons["fullDiskAccessLink"].click()
        XCTAssertTrue(app.staticTexts["Full Disk Access is optional"].waitForExistence(timeout: 5))
        app.buttons["closeFullDiskAccess"].click() // Never "Open System Settings".
        app.terminate()

        // Granted: the Safari folder opens.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
        app.launch()
        let row = app.buttons["overviewCategory-browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["overviewNotAccessible-safari-cache"].exists)
        row.click()
        let rule = app.checkBoxes["planRule-safari-cache"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        rule.click()
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.staticTexts["Clear Safari cache"].waitForExistence(timeout: 5))
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let updaters = app.buttons["overviewCategory-updaters"]
        XCTAssertTrue(updaters.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["overviewCategory-logs"].exists)
        updaters.click()

        let update = app.checkBoxes["planProfile-updater-downloads-com.example.StillFixture"]
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["planRule-crash-reports"].exists)
        XCTAssertTrue(app.checkBoxes["planRule-app-logs"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'FixtureAgent' OR identifier CONTAINS 'FixtureAgent'")).firstMatch.exists)
        update.click()
        app.checkBoxes["planRule-crash-reports"].click()
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear App update downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Clear Crash reports"].exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
    }

    /// A stand-in `docker` in the fixture: `system df` prints `df` (or fails, as with no daemon); anything else leaves a marker.
    @MainActor private func addDocker(_ home: URL, daemonAnswers: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".docker"), withIntermediateDirectories: true)
        let marker = home.appendingPathComponent("docker-pruned")
        let docker = home.appendingPathComponent(".still-test-tools/docker")
        try FileManager.default.createDirectory(at: docker.deletingLastPathComponent(), withIntermediateDirectories: true)
        let df = daemonAnswers
            ? #"echo '{"Active":"1","Reclaimable":"2.5GB (62%)","Size":"4GB","TotalCount":"5","Type":"Images"}'; echo '{"Active":"0","Reclaimable":"1.2GB","Size":"1.2GB","TotalCount":"9","Type":"Build Cache"}'"#
            : "echo 'Cannot connect to the Docker daemon' >&2; exit 1"
        try "#!/bin/sh\nif test \"$*\" = 'system df --format json'; then \(df); else touch '\(marker.path)'; fi\n".write(to: docker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: docker.path)
        return marker
    }

    @MainActor func testDockerPruneKindsAreSeparateChoicesAndPreviewNeverPrunes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDocker(home, daemonAnswers: true)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        // Each prune kind is its own choice, none preselected; nothing is offered for volumes.
        for rule in ["docker-images", "docker-build-cache"] {
            let header = app.checkBoxes["planRule-" + rule]
            XCTAssertTrue(header.waitForExistence(timeout: 5), rule)
            XCTAssertEqual(header.value as? Int, 0, rule)
        }
        XCTAssertFalse(app.checkBoxes["planRule-docker-containers"].exists)
        app.checkBoxes["planRule-docker-build-cache"].click()
        XCTAssertEqual(app.checkBoxes["planRule-docker-images"].value as? Int, 0)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Clear Docker build cache"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Clear Docker images"].exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'would run docker builder prune -a -f'")).firstMatch.exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    @MainActor func testDockerShowsANoticeInsteadOfRowsWhenItsDaemonIsntRunning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addDocker(home, daemonAnswers: false)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-developer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        XCTAssertTrue(app.staticTexts["planNote-docker-images"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Docker isn’t running'")).firstMatch.exists)
        XCTAssertFalse(app.checkBoxes["planRule-docker-images"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}

final class ICloudCleanupUITests: XCTestCase {
    /// Two iCloud Drive files in the fixture home, one set to Keep Downloaded. Their iCloud states come from the
    /// debug fixture file, so the test never reads or evicts anything in real iCloud Drive.
    @MainActor private func addICloudFiles(_ home: URL) throws {
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        for name in ["Report.pdf", "Pinned.pdf"] {
            let file = home.appendingPathComponent(drive + "/" + name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 150_000).write(to: file)
        }
        let states = [drive + "/Report.pdf": "ready", drive + "/Pinned.pdf": "pinned"]
        try JSONEncoder().encode(states).write(to: home.appendingPathComponent(".still-test-icloud.json"))
    }

    @MainActor func testLocalCopiesAreChosenAndPreviewEvictsNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        try addICloudFiles(home)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-icloud"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["overviewCloudFinding"].exists)
        row.click()

        let header = app.checkBoxes["planRule-icloud-local-copies"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? Int, 0)
        let item = app.checkBoxes["planItem-Report.pdf"]
        if !item.waitForExistence(timeout: 2) { app.disclosureTriangles.allElementsBoundByIndex.forEach { $0.click() } }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planItem-Pinned.pdf"].exists, "Keep Downloaded files are never offered")
        item.click()
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Remove local copies: Downloaded iCloud Drive files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'stay in iCloud and download again when you open them'")).firstMatch.exists)
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
        let old = folder.appendingPathComponent("old-notes.txt"), recent = folder.appendingPathComponent("recent.txt")
        try Data(repeating: 1, count: 4_000).write(to: old)
        try Data(repeating: 2, count: 4_000).write(to: recent)
        let then = Date().addingTimeInterval(-200 * 86_400)
        try FileManager.default.setAttributes([.creationDate: then, .modificationDate: then], ofItemAtPath: old.path)
        var times = [timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0)]
        XCTAssertEqual(utimes(old.path, &times), 0)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.buttons["Choose a folder…"].click()
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        panel.buttons["Scan folder"].click()

        let explore = app.buttons["Explore storage"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        explore.click()
        let mode = app.segmentedControls["explorerMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.buttons["Large and old files"].click()

        // Only the old file is listed, and nothing is preselected.
        let item = app.checkBoxes["explorerChoose-old-notes.txt"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["explorerChoose-recent.txt"].exists)
        XCTAssertEqual(item.value as? Int, 0)
        item.click()
        XCTAssertEqual(item.value as? Int, 1)
        app.buttons["View cleanup plan"].click()

        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.staticTexts["Move to Trash: Large and old files"].waitForExistence(timeout: 5))
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would move to Trash"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }
}
