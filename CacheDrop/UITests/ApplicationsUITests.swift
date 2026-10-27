import XCTest

/// #267, Decision 51: the Applications page lists apps, plug-in products and leftovers of removed apps from a fixture home.
/// Installed apps come only from the home's `Applications` folder and `.cachedrop-test-installed-apps` (DEBUG seam), and the
/// home stands in for the system root, so the journey never reads this Mac's apps or plug-ins.
final class ApplicationsUITests: XCTestCase {
    /// An app bundle in the fixture home's Applications folder.
    private func addApp(_ name: String, id: String, bytes: Int, copyright: String? = nil, in home: URL) throws -> URL {
        let bundle = home.appendingPathComponent("Applications/\(name).app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "main"]
        if let copyright { info["NSHumanReadableCopyright"] = copyright }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try Data(repeating: 1, count: bytes).write(to: bundle.appendingPathComponent("Contents/MacOS/main"))
        return bundle
    }

    /// An element by identifier. Applications' identifiers carry paths (#271), longer than the 128 characters a
    /// subscript query allows, so this matches with a predicate instead (#273).
    private func element(_ app: XCUIApplication, _ identifier: String, _ type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    @MainActor func testApplicationsListsAppsPlugInsAndLeftoversAndTheirOverviewRowOpensIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        var locked: URL?
        defer {
            app.terminate()
            if let locked { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
            try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home)
        }
        let bigApp = try addApp("Big Synth", id: "com.maker.bigsynth", bytes: 900_000, copyright: "© 2025 Maker Audio Inc. All rights reserved.", in: home)
        let smallApp = try addApp("Small Tool", id: "com.other.smalltool", bytes: 90_000, in: home)
        _ = try addApp("Notes", id: "com.apple.Notes", bytes: 2_000_000, in: home)
        _ = try addApp("CacheDrop", id: "com.patrickbourget.CacheDrop", bytes: 2_000_000, in: home)
        locked = try addApp("Locked Suite", id: "com.vendor.locked", bytes: 50_000, in: home)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked!.path)
        for (folder, ext) in [("Components", "component"), ("VST3", "vst3")] {
            let bundle = home.appendingPathComponent("Library/Audio/Plug-Ins/\(folder)/Pro Synth.\(ext)")
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "com.maker.prosynth.\(ext)"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        }
        let leftover = home.appendingPathComponent("Library/Containers/com.gone.synth/Data/state.db")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: leftover)
        app.launch()
        waitForCatalogScan(app)

        // Overview's leftovers row opens Applications, where the leftovers are; the Cleanup plan no longer shows them.
        revealAndClick(app.buttons["overviewCategory-leftovers"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Applications"].isSelected)
        XCTAssertTrue(app.checkBoxes["planCategory-leftovers"].waitForExistence(timeout: 5))

        // Apps: largest first, read-only, never Apple's or CacheDrop. Identifiers carry each entry's path, not its name (#271).
        let big = element(app, "applicationsApp-" + bigApp.path), small = element(app, "applicationsApp-" + smallApp.path)
        XCTAssertTrue(big.waitForExistence(timeout: 10), "The apps are listed")
        XCTAssertTrue(small.exists)
        XCTAssertLessThan(big.frame.minY, small.frame.minY, "Largest first")
        XCTAssertTrue(app.staticTexts["Maker Audio Inc"].exists, "A row names its maker")
        XCTAssertFalse(element(app, "applicationsApp-" + home.appendingPathComponent("Applications/Notes.app").path).exists, "Apple's apps are never listed")
        XCTAssertFalse(element(app, "applicationsApp-" + home.appendingPathComponent("Applications/CacheDrop.app").path).exists, "CacheDrop never lists itself")
        XCTAssertFalse(element(app, "applicationsApp-" + locked!.path, .checkBox).exists, "An app that needs a password has no checkbox")
        XCTAssertFalse(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 1'")).firstMatch.exists, "An app alone has no Choose items")

        // An app that needs a password says so, with Reveal in Finder.
        let password = element(app, "applicationsPassword-" + locked!.path, .staticText)
        XCTAssertTrue(password.exists)
        XCTAssertEqual(password.value as? String, "Needs your password to remove")
        XCTAssertTrue(element(app, "applicationsReveal-" + locked!.path, .button).exists)

        // Plug-ins: one row per product, its formats as items.
        // A product's identifier carries its first file's path.
        let product = element(app, "applicationsPlugIn-" + home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Pro Synth.component").path)
        XCTAssertTrue(product.exists)
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 2'")).firstMatch.exists, "AU and VST3")

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Cleanup plan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planCategory-leftovers"].exists, "Leftovers leave the Cleanup plan")
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsHeader"].waitForExistence(timeout: 5), "⌘5 opens Applications")
        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path))
    }

    /// #177: an app is ticked with its confirmed files, reviewed grouped by place with what stays, moved to the fixture Trash,
    /// and History says "Uninstalled <App> · N items". The possibly related folder stays unticked and in place.
    @MainActor func testAnAppIsUninstalledWithItsFiles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        let files = ["Library/Containers/com.maker.synth/Data/state.db", "Library/Preferences/com.maker.synth.plist"].map(home.appendingPathComponent)
        let related = home.appendingPathComponent("Library/Application Support/Synth/presets.db")
        for file in files + [related] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("5", modifierFlags: .command)

        let row = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "An app CacheDrop can uninstall has a checkbox")
        XCTAssertEqual(row.value as? Int, 0, "Nothing is ticked when the page opens")
        revealAndClick(row, in: app)
        XCTAssertEqual(row.value as? Int, 1)
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planItem-Synth"].value as? Int, 0, "A possibly related item is never ticked with its app")

        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "apps").waitForExistence(timeout: 5))
        let staying = element(app, "reviewStaying-" + synth.path + "-unticked", .staticText)
        XCTAssertEqual(staying.value as? String, "Synth: 1 part stays · Not ticked", "The review says what stays")
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["View history"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: synth.path), "The app went to the Trash")
        for file in files { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), file.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: related.path), "What wasn't ticked stays")

        app.buttons["View history"].click()
        // A History row is one combined button whose label starts with its title.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Uninstalled Synth · 3 items")).firstMatch.waitForExistence(timeout: 10))
    }

    /// #270: while the scan runs each section says it is looking; a section that finds nothing says so.
    @MainActor func testSectionsShowLoadingThenEmptyStates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.5"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsLoading-apps"].waitForExistence(timeout: 5), "Apps say they are loading")
        XCTAssertTrue(app.descendants(matching: .any)["applicationsLoading-leftovers"].exists)
        for section in ["apps", "plugIns", "leftovers"] {
            XCTAssertTrue(app.descendants(matching: .any)["applicationsEmpty-" + section].waitForExistence(timeout: 120), "\(section) says nothing was found")
        }
        XCTAssertFalse(app.descendants(matching: .any)["applicationsLoading-apps"].exists)
    }

    /// #270: a leftover ticked on Applications is reviewed and cleaned there (dry run), and Overview never calls it in the plan.
    @MainActor func testALeftoverIsTickedAndCleanedFromApplications() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let leftover = home.appendingPathComponent("Library/Containers/com.gone.synth/Data/state.db")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: leftover)
        app.launch()
        waitForCatalogScan(app)

        app.typeKey("5", modifierFlags: .command)
        let category = app.checkBoxes["planCategory-leftovers"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        revealAndClick(category, in: app)
        XCTAssertEqual(category.value as? Int, 1)
        app.typeKey("1", modifierFlags: .command)
        let row = app.buttons["overviewCategory-leftovers"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse((row.value as? String ?? "").contains("In cleanup plan"), String(describing: row.value))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled, "The plan has nothing chosen")

        app.typeKey("5", modifierFlags: .command)
        XCTAssertEqual(app.checkBoxes["planCategory-leftovers"].value as? Int, 1, "Its tick is kept")
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "leftovers").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path), "A dry run moves nothing")
    }
}
