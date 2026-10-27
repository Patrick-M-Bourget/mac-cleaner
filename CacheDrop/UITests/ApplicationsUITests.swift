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
        _ = try addApp("Big Synth", id: "com.maker.bigsynth", bytes: 900_000, copyright: "© 2025 Maker Audio Inc. All rights reserved.", in: home)
        _ = try addApp("Small Tool", id: "com.other.smalltool", bytes: 90_000, in: home)
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

        // Apps: largest first, read-only, never Apple's or CacheDrop.
        let big = app.descendants(matching: .any)["applicationsApp-Big Synth"], small = app.descendants(matching: .any)["applicationsApp-Small Tool"]
        XCTAssertTrue(big.waitForExistence(timeout: 10), "The apps are listed")
        XCTAssertTrue(small.exists)
        XCTAssertLessThan(big.frame.minY, small.frame.minY, "Largest first")
        XCTAssertTrue(app.staticTexts["Maker Audio Inc"].exists, "A row names its maker")
        XCTAssertFalse(app.descendants(matching: .any)["applicationsApp-Notes"].exists, "Apple's apps are never listed")
        XCTAssertFalse(app.descendants(matching: .any)["applicationsApp-CacheDrop"].exists, "CacheDrop never lists itself")
        XCTAssertFalse(app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH 'applications'")).firstMatch.exists, "Nothing new can be ticked yet")

        // An app that needs a password says so, with Reveal in Finder.
        let password = app.staticTexts["applicationsPassword-Locked Suite"]
        XCTAssertTrue(password.exists)
        XCTAssertEqual(password.value as? String, "Needs your password to remove")
        XCTAssertTrue(app.buttons["applicationsReveal-Locked Suite"].exists)

        // Plug-ins: one row per product, its formats as items.
        let product = app.descendants(matching: .any)["applicationsPlugIn-Pro Synth"]
        XCTAssertTrue(product.exists)
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 2'")).firstMatch.exists, "AU and VST3")

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Cleanup plan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planCategory-leftovers"].exists, "Leftovers leave the Cleanup plan")
        app.typeKey("7", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsHeader"].waitForExistence(timeout: 5), "⌘7 opens Applications")
        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path))
    }
}
