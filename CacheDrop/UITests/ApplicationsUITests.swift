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
        // With no maker, no empty line is left: the password line sits right under the name (#298).
        let lockedTitle = element(app, "applicationsApp-" + locked!.path).staticTexts["Locked Suite"], maker = app.staticTexts["Maker Audio Inc"]
        XCTAssertLessThan(password.frame.minY - lockedTitle.frame.maxY, maker.frame.height, "No gap where the maker line would be")

        // Plug-ins: one row per product, its formats as items to tick (#176).
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

    /// #305: two apps of one maker. Each row offers only its own files, though the other keeps the maker installed, and once
    /// Synth is uninstalled, Pad's row is unchanged: Synth's untouched support folder is offered nowhere while Pad is installed.
    @MainActor func testAppsOfOneMakerAreEachUninstalledWithOnlyTheirOwnFiles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        let pad = try addApp("Pad", id: "com.maker.pad", bytes: 90_000, in: home)
        let synthFiles = ["Library/Preferences/com.maker.synth.plist", "Library/Containers/com.maker.synth/Data/state.db"].map(home.appendingPathComponent)
        let padFiles = ["Library/Preferences/com.maker.pad.plist", "Library/Containers/com.maker.pad/Data/state.db"].map(home.appendingPathComponent)
        let related = home.appendingPathComponent("Library/Application Support/Synth/presets.db")
        for file in synthFiles + padFiles + [related] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 60_000).write(to: file)
        }
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("5", modifierFlags: .command)

        let synthRow = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(synthRow.waitForExistence(timeout: 10))
        func choose(_ count: Int) -> XCUIElement { app.disclosureTriangles.matching(NSPredicate(format: "label == %@", "Choose items · \(count)")).firstMatch }
        XCTAssertTrue(choose(4).exists, "Synth: the app, its preferences and container, and the folder named like it")
        XCTAssertTrue(choose(3).exists, "Pad: the app, its preferences and container")
        revealAndClick(synthRow, in: app)
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planItem-com.maker.synth.plist"].value as? Int, 1, "Its own preferences are ticked with it")
        XCTAssertEqual(app.checkBoxes["planItem-com.maker.pad.plist"].value as? Int, 0, "Pad's are Pad's")

        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.buttons["Clean up"].waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20))
        for file in synthFiles { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), file.path) }
        for file in padFiles + [related] { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
        app.buttons["Done"].click()

        let padRow = element(app, "applicationsApp-" + pad.path, .checkBox)
        XCTAssertTrue(padRow.waitForExistence(timeout: 120), "The rescan lists Pad again")
        XCTAssertFalse(synthRow.exists)
        XCTAssertTrue(choose(3).waitForExistence(timeout: 5), "Pad's row is unchanged")
        XCTAssertFalse(choose(4).exists)
        expandDisclosures(in: app)
        XCTAssertFalse(app.checkBoxes["planItem-Synth"].exists, "Synth's folder is never offered as Pad's, nor as a leftover while Pad is installed")
        XCTAssertFalse(app.checkBoxes["planCategory-leftovers"].exists)
    }

    /// #303, #306: an uninstall rescans when it ends. After Done, while that scan runs, the bar shows its progress and the
    /// other app's row says it is being checked; then its checkbox comes back.
    @MainActor func testApplicationsRescansAfterAnUninstallAndRowsSayTheyAreBeingChecked() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        let pad = try addApp("Pad", id: "com.maker.pad", bytes: 90_000, in: home)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.5"
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("5", modifierFlags: .command)

        let synthRow = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(synthRow.waitForExistence(timeout: 10))
        revealAndClick(synthRow, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.buttons["Clean up"].waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20))
        app.buttons["Done"].click()

        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForExistence(timeout: 10), "The run rescans, and the bar shows its progress")
        XCTAssertTrue(element(app, "applicationsChecking-" + pad.path).waitForExistence(timeout: 5), "A row says it is being checked")
        let padRow = element(app, "applicationsApp-" + pad.path, .checkBox)
        XCTAssertTrue(padRow.waitForExistence(timeout: 120), "Its checkbox comes back after the scan")
        XCTAssertFalse(element(app, "applicationsChecking-" + pad.path).exists)
    }

    /// #306: Put back from History rescans, so the app it returned is listed on Applications again without Scan again.
    @MainActor func testPutBackFromHistoryListsTheAppOnApplicationsAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("5", modifierFlags: .command)

        let row = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.buttons["Clean up"].waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["View history"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: synth.path), "The app went to the Trash")
        // The run's own rescan ends before the put back, so only the put back can bring the app back.
        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForNonExistence(timeout: 120), "The rescan after the run finished")

        app.buttons["View history"].click()
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Uninstalled Synth")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        revealAndClick(run, in: app)
        let putBack = app.descendants(matching: .any)["putBack-Synth.app"]
        XCTAssertTrue(putBack.waitForExistence(timeout: 10))
        revealAndClick(putBack, in: app)
        XCTAssertTrue(app.staticTexts["putBackDone-Synth.app"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: synth.path), "The app is back where it was")

        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(row.waitForExistence(timeout: 120), "The app is listed on Applications again")
    }

    /// #176: a plug-in product is ticked with its removable formats, its AU (which needs a password) is listed without a
    /// checkbox and the review says it stays, the VST3 goes to the fixture Trash, and History says "Uninstalled <Product>".
    /// This is #176's one real check (#288): the real app's scan, check and run on a disposable plug-in built in a temp folder.
    @MainActor func testAPlugInProductIsUninstalledAndWhatNeedsAPasswordStays() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let au = home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Pro Synth.component")
        let vst3 = home.appendingPathComponent("Library/Audio/Plug-Ins/VST3/Pro Synth.vst3")
        defer {
            app.terminate(); try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: au.path)
            try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home)
        }
        for (bundle, ext) in [(au, "component"), (vst3, "vst3")] {
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.maker.prosynth.\(ext)"], format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        }
        let appex = home.appendingPathComponent("Applications/Pad.app/Contents/PlugIns/Pad.appex")
        try FileManager.default.createDirectory(at: appex.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.other.pad.auv3", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.AudioUnit"]],
                                           format: .xml, options: 0).write(to: appex.appendingPathComponent("Contents/Info.plist"))
        // As in a root-owned Components folder, the AU can't be moved without a password (Decision 50).
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: au.path)
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("5", modifierFlags: .command)

        let row = element(app, "applicationsPlugIn-" + au.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "A product CacheDrop can partly uninstall has a checkbox")
        XCTAssertEqual(row.value as? Int, 0, "Nothing is ticked when the page opens")
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 1 · 1 stays'")).firstMatch.exists, "Counts what can be chosen")
        revealAndClick(row, in: app)
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planItem-Pro Synth.vst3"].value as? Int, 1, "Its removable format is ticked with it")
        XCTAssertFalse(app.checkBoxes["planItem-Pro Synth.component"].exists, "A format that needs a password has no checkbox")
        XCTAssertEqual(element(app, "applicationsPassword-" + au.path, .staticText).value as? String, "AU: Needs your password to remove")
        XCTAssertTrue(element(app, "applicationsReveal-" + au.path, .button).exists, "Reveal in Finder, with no vendor tool installed")
        // A product that is only an AUv3 goes with its app (#288).
        XCTAssertEqual(element(app, "applicationsInsideApp-" + appex.path, .staticText).value as? String, "Goes with Pad")

        app.buttons["Review cleanup"].click()
        let staying = element(app, "reviewStaying-" + au.path + "-password", .staticText)
        XCTAssertTrue(staying.waitForExistence(timeout: 5))
        let line = reviewLine(app, "movedToTrash", "apps").value as? String ?? ""
        XCTAssertTrue(line.hasPrefix("Apps, plug-ins and their files"), "The review names plug-ins too: " + line)
        XCTAssertEqual(staying.value as? String, "Pro Synth: 1 part stays · Needs your password", "The review says what stays")
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["View history"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vst3.path), "The VST3 went to the Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: au.path), "What needs a password is never acted on")

        app.buttons["View history"].click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Uninstalled Pro Synth · 1 item")).firstMatch.waitForExistence(timeout: 10))
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
