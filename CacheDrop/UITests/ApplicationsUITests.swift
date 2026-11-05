import XCTest

/// #267, Decision 51: the Applications page lists apps, plug-in products and files from deleted apps from a fixture home.
/// Installed apps come only from the home's `Applications` folder and `.cachedrop-test-installed-apps` (DEBUG seam), and the
/// home stands in for the system root, so the journey never reads this Mac's apps or plug-ins.
final class ApplicationsUITests: XCTestCase {
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
        // A second app's files, so the row has "Choose items · 2" to open.
        let other = home.appendingPathComponent("Library/Containers/com.gone.drums/Data/state.db")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 30_000).write(to: other)
        app.launch()
        waitForCatalogScan(app)

        // Overview's Files from deleted apps row opens Applications, where those files are; the Cleanup plan no longer shows them.
        revealAndClick(app.buttons["overviewCategory-leftovers"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Applications"].isSelected)
        XCTAssertTrue(app.checkBoxes["planCategory-leftovers"].waitForExistence(timeout: 5))
        // The row opened its own section (Decision 153); the other sections stay closed until opened for the checks below.
        let leftoverItems = app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 2'")).firstMatch
        XCTAssertTrue(leftoverItems.waitForExistence(timeout: 5))
        XCTAssertEqual(leftoverItems.value as? Int, 1, "Files from deleted apps arrives open")
        XCTAssertNotEqual(applicationsSection(app, "apps").value as? Int, 1)
        openApplicationsSections(app, ["apps", "plug-ins"])

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
        XCTAssertTrue(element(app, "applicationsReveal-" + locked!.path, .link).exists)
        // With no maker, no empty line is left: the password line sits right under the name (#298).
        let lockedTitle = element(app, "applicationsApp-" + locked!.path).staticTexts["Locked Suite"], maker = app.staticTexts["Maker Audio Inc"]
        XCTAssertLessThan(password.frame.minY - lockedTitle.frame.maxY, maker.frame.height, "No gap where the maker line would be")

        // Plug-ins: one row per product, its formats as items to tick (#176).
        // A product's identifier carries its first file's path.
        let product = element(app, "applicationsPlugIn-" + home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Pro Synth.component").path)
        XCTAssertTrue(product.waitForExistence(timeout: 5), "Under Other makers: it has no maker")
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 2'")).firstMatch.exists, "AU and VST3")

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Cleanup plan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.checkBoxes["planCategory-leftovers"].exists, "Leftovers leave the Cleanup plan")
        openApplications(app)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsHeader"].waitForExistence(timeout: 5), "⌘4 opens Applications")
        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path))
    }

    /// Decisions 151 and 153: sections start closed behind "Choose apps · N"; a search opens the ones with a match, and they stay as left.
    @MainActor func testApplicationsSectionsStartClosedAndASearchOpensTheOnesWithAMatch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let big = try addApp("Big Synth", id: "com.maker.bigsynth", bytes: 900_000, in: home)
        _ = try addApp("Zed Tool", id: "com.third.zed", bytes: 300_000, in: home)
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("4", modifierFlags: .command)

        let apps = applicationsSection(app, "apps")
        XCTAssertTrue(apps.waitForExistence(timeout: 10))
        XCTAssertEqual(apps.label, "Choose apps · 2", "A category row for the section, counting what it lists")
        XCTAssertNotEqual(apps.value as? Int, 1, "Sections start closed")
        XCTAssertFalse(app.checkBoxes["applicationsSection-apps"].exists, "A section is never ticked whole")
        let row = element(app, "applicationsApp-" + big.path)
        XCTAssertFalse(row.exists, "A closed section shows no rows")

        let search = app.textFields["applicationsSearch"]
        search.click(); search.typeText("bi")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "A search opens the section its match is in")
        XCTAssertEqual(apps.value as? Int, 1)
        apps.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        search.click(); search.typeText("g")
        XCTAssertNotEqual(apps.value as? Int, 1, "Closed during a search, it stays closed while its matches don't change")
        apps.click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(apps.value as? Int, 1, "Clearing the search leaves it open")

        apps.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Choose apps closes it again")
        app.typeKey("1", modifierFlags: .command); app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(apps.waitForExistence(timeout: 5))
        XCTAssertNotEqual(apps.value as? Int, 1, "It stays as it was left")
    }

    /// Decision 151: a DAW leaves Apps for Audio software; plug-ins group by maker, and a maker with one product shows it directly.
    /// Decision 175: Audio software opens straight to its groups, behind "Show groups · N".
    @MainActor func testAudioSoftwareHoldsDAWsAndPlugInsGroupedByMaker() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let live = try addApp("Ableton Live 12 Suite", id: "com.ableton.live", bytes: 400_000, in: home)
        let zed = try addApp("Zed Tool", id: "com.third.zed", bytes: 300_000, in: home)
        // Audio Units are named "Maker: Name", which is where a plug-in's maker comes from.
        for (name, id, maker) in [("Alpha", "com.maker.alpha", "Maker Audio Inc"), ("Beta", "com.maker.beta", "Maker Audio Inc"), ("Solo", "com.solo.solo", "Solo Sounds")] {
            let bundle = home.appendingPathComponent("Library/Audio/Plug-Ins/Components/\(name).component")
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": id,
                                       "AudioComponents": [["name": "\(maker): \(name)", "manufacturer": "Mkr\(name.prefix(1))", "type": "aufx", "subtype": "test"]]]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        }
        app.launch()
        waitForCatalogScan(app)
        openApplications(app, ["apps"])

        XCTAssertEqual(applicationsSection(app, "apps").label, "Choose apps · 1", "Apps keeps only Zed Tool")
        XCTAssertTrue(element(app, "applicationsApp-" + zed.path).waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "applicationsApp-" + live.path).exists, "The DAW isn't under Apps")

        let audio = applicationsSection(app, "audio software")
        XCTAssertEqual(audio.label, "Show groups · 4", "All four groups, two of them empty")
        XCTAssertFalse(app.checkBoxes["applicationsSection-audio"].exists, "A section is never ticked whole")
        // A search opens the section, the group and the maker its match is in.
        let beta = element(app, "applicationsPlugIn-" + home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Beta.component").path)
        let search = app.textFields["applicationsSearch"]
        search.click(); search.typeText("beta")
        XCTAssertTrue(beta.waitForExistence(timeout: 5), "Audio software, Plug-ins and Maker Audio Inc open for the match")
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])

        openApplicationsSections(app, ["audio software"])
        XCTAssertTrue(element(app, "applicationsGroup-apps").waitForExistence(timeout: 5), "Opening Audio software shows its groups")
        XCTAssertTrue(element(app, "applicationsGroup-plug-ins").exists)
        // Decision 176: a group that found nothing is one row reading Empty.
        XCTAssertTrue(element(app, "applicationsGroup-drivers").staticTexts["Empty"].waitForExistence(timeout: 5), "No drivers: Empty")
        XCTAssertFalse(element(app, "applicationsGroup-plug-ins").staticTexts["Empty"].exists)
        openApplicationsSections(app, ["apps", "plug-ins"])
        XCTAssertTrue(element(app, "applicationsApp-" + live.path).waitForExistence(timeout: 5), "DAWs and apps lists it")
        XCTAssertTrue(element(app, "applicationsGroup-maker:Maker Audio Inc").waitForExistence(timeout: 5), "Two products of one maker make a group")
        XCTAssertFalse(element(app, "applicationsGroup-maker:Solo Sounds").exists, "A maker with one product shows it directly")
        let solo = element(app, "applicationsPlugIn-" + home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Solo.component").path)
        XCTAssertTrue(solo.waitForExistence(timeout: 5), "Solo is listed on its own")
    }

    /// Decision 154: sounds and samples are read-only behind "Show sounds"; a driver the user can move and a Reason device have
    /// checkboxes, nothing ticked; the driver has Reveal in Finder (Decision 158). Decision 157: a library whose vendor's manager
    /// is installed offers Open <tool>; one whose manager isn't installed, and Splice's, offer none.
    @MainActor func testAudioSoftwareShowsSoundsAndOffersDriversAndReasonDevices() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        try addAudioSoftware(in: home)
        let driver = home.appendingPathComponent("Library/Audio/Plug-Ins/HAL/Loopback.driver")
        app.launch()
        waitForCatalogScan(app)
        openApplications(app, ["audio software"])

        let sounds = app.disclosureTriangles.matching(NSPredicate(format: "label == 'Show sounds · 3'")).firstMatch
        XCTAssertTrue(sounds.waitForExistence(timeout: 10), "Read-only: Show, not Choose")
        revealAndClick(sounds, in: app)
        let splice = home.appendingPathComponent("Splice").path
        XCTAssertTrue(element(app, "applicationsSoundReveal-" + splice, .link).waitForExistence(timeout: 5), "Splice sounds, with Reveal in Finder")
        let waves = home.appendingPathComponent("Applications/Waves/Data/Instrument Data/Waves Sample Libraries").path
        let openWaves = element(app, "applicationsSoundOpen-" + waves, .link)
        XCTAssertTrue(openWaves.waitForExistence(timeout: 5), "Waves' libraries offer their installed manager")
        XCTAssertEqual(openWaves.label, "Open Waves Central")
        XCTAssertTrue(element(app, "applicationsSoundReveal-" + waves, .link).exists, "Reveal in Finder stays")
        revealAndClick(openWaves, in: app)
        let status = app.staticTexts["applicationsStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String ?? status.label, "Test run: would open Waves Central.")
        let arturia = home.appendingPathComponent("Library/Arturia").path
        XCTAssertTrue(element(app, "applicationsSoundReveal-" + arturia, .link).waitForExistence(timeout: 5), "Arturia's resources are listed, so a missing link below is really missing")
        XCTAssertFalse(element(app, "applicationsSoundOpen-" + arturia, .link).exists, "No link when the manager isn't installed")
        XCTAssertFalse(element(app, "applicationsSoundOpen-" + splice, .link).exists, "No link for a vendor with no known manager")
        openApplicationsSections(app, ["drivers", "plug-ins"])
        let driverBox = app.descendants(matching: .checkBox).matching(NSPredicate(format: "identifier == %@", "applicationsDriver-" + driver.path)).firstMatch
        XCTAssertTrue(driverBox.waitForExistence(timeout: 5), "A driver the user can move has a checkbox")
        XCTAssertEqual(driverBox.value as? Int, 0, "Never pre-ticked")
        // #715: before ticking it, the user can see where it lives.
        XCTAssertTrue(element(app, "applicationsReveal-" + driver.path, .link).waitForExistence(timeout: 5),
                      "A driver the user can move has Reveal in Finder")
        let pangea = home.appendingPathComponent("Library/Application Support/Propellerhead Software/Optional REs/Pangea").path
        let device = app.descendants(matching: .checkBox).matching(NSPredicate(format: "identifier == %@", "applicationsPlugIn-" + pangea)).firstMatch
        XCTAssertTrue(device.waitForExistence(timeout: 5), "Reason's device can go to the Trash")
        XCTAssertEqual(device.value as? Int, 0)
    }

    /// #295, #352: one sortable column header (Name or Size, either way round) and one search order and filter every section;
    /// a ticked row the search hides stays ticked and counted in the bar, and clearing the search shows it again.
    @MainActor func testApplicationsSortByNameOrSizeAndSearchByMakerKeepsTicks() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let big = try addApp("Big Synth", id: "com.maker.bigsynth", bytes: 900_000, copyright: "© 2025 Maker Audio Inc. All rights reserved.", in: home)
        let apex = try addApp("Apex", id: "com.other.apex", bytes: 90_000, in: home)
        let zed = try addApp("Zed Tool", id: "com.third.zed", bytes: 300_000, in: home)
        let leftover = home.appendingPathComponent("Library/Containers/com.gone.synth/Data/state.db")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: leftover)
        app.launch()
        waitForCatalogScan(app)
        openApplications(app, ["apps"])

        let rows = [big, apex, zed].map { element(app, "applicationsApp-" + $0.path, .checkBox) }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 10))
        func order() -> [CGFloat] { rows.map(\.frame.minY) }
        XCTAssertTrue(order()[0] < order()[2] && order()[2] < order()[1], "Size, largest first, by default")

        // #352: the column header sorts; the active column carries the chevron and says its direction.
        let byName = app.buttons["applicationsSort-name"], bySize = app.buttons["applicationsSort-size"]
        XCTAssertTrue(bySize.exists && byName.exists)
        XCTAssertEqual(bySize.value as? String, "Largest first")
        byName.click()
        XCTAssertTrue(order()[1] < order()[0] && order()[0] < order()[2], "Name: Apex, Big Synth, Zed Tool")
        XCTAssertEqual(byName.value as? String, "A to Z")
        byName.click()
        XCTAssertTrue(order()[2] < order()[0] && order()[0] < order()[1], "Clicking the active column flips it: Zed Tool, Big Synth, Apex")
        XCTAssertEqual(byName.value as? String, "Z to A")
        bySize.click()
        XCTAssertTrue(order()[0] < order()[2] && order()[2] < order()[1], "Back to largest first")
        bySize.click()
        XCTAssertTrue(order()[1] < order()[2] && order()[2] < order()[0], "Smallest first")
        bySize.click()

        revealAndClick(rows[1], in: app)
        XCTAssertEqual(rows[1].value as? Int, 1)
        // The leftover's container ties it to its removed app, so it arrives ticked (#349).
        let count = app.staticTexts["actionStripNote"]
        XCTAssertEqual(count.value as? String, "2 items selected")

        let search = app.textFields["applicationsSearch"]
        search.click(); search.typeText("maker audio")
        XCTAssertTrue(rows[1].waitForNonExistence(timeout: 5), "A row whose name and maker don't match is hidden")
        XCTAssertTrue(rows[0].exists, "Searched by maker")
        XCTAssertFalse(rows[2].exists)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsNoMatches-leftovers"].exists, "A section with no matches says so")
        XCTAssertFalse(app.checkBoxes["planCategory-leftovers"].exists)
        XCTAssertEqual(count.value as? String, "2 items selected", "The hidden ticked rows are still counted")
        XCTAssertTrue(app.buttons["Review cleanup"].isEnabled)

        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(rows[1].waitForExistence(timeout: 5), "Clearing the search shows everything again")
        XCTAssertEqual(rows[1].value as? Int, 1, "Still ticked")
        XCTAssertTrue(app.checkBoxes["planCategory-leftovers"].exists)

        // #468: a search that matches nothing shows one "No matches" with Clear search, never a section's empty-list state.
        search.click(); search.typeText("zzqx")
        let none = app.descendants(matching: .any)["applicationsNoMatches"]
        XCTAssertTrue(none.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Empty"].exists, "No section reads Empty under it")
        revealAndClick(none.buttons["Clear search"], in: app)
        XCTAssertTrue(rows[1].waitForExistence(timeout: 5), "Clear search shows everything again")
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
        openApplications(app, ["apps"])

        let row = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "An app CacheDrop can uninstall has a checkbox")
        XCTAssertEqual(row.value as? Int, 0, "Nothing is ticked when the page opens")
        revealAndClick(row, in: app)
        XCTAssertEqual(row.value as? Int, 1)
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planItem-uninstall-app-possibly-related-Synth"].value as? Int, 0, "A possibly related item is never ticked with its app")

        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "apps").waitForExistence(timeout: 5))
        let staying = element(app, "reviewStaying-" + synth.path + "-unticked", .staticText)
        XCTAssertEqual(staying.value as? String, "Synth: 1 item you didn’t tick stays. Go back and tick it to remove it too.",
                       "The review says what stays, why and what to do (#354)")
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["View history"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: synth.path), "The app went to the Trash")
        for file in files { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), file.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: related.path), "What wasn't ticked stays")
        // #312: the app's result row names the app, never the rule ("App · ~/Applications").
        let named = NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Synth · ", "Synth · ")
        XCTAssertTrue(app.staticTexts.matching(named).firstMatch.exists, "Results name the app")
        let ruleNamed = NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "App · ", "App · ")
        XCTAssertFalse(app.staticTexts.matching(ruleNamed).firstMatch.exists, "Results never name the rule")

        app.buttons["View history"].click()
        // A History row is the one disclosure (#772): a disclosure triangle whose label starts with its title.
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label CONTAINS %@", "Uninstalled Synth · 3 items")).firstMatch.waitForExistence(timeout: 10))
    }

    /// Synth, a fixture app the journey starts itself (a copy of `sleep` in the fixture home's bundle), open while its uninstall
    /// is reviewed: its app and its container are two rows it holds. A debug run only ever sees and quits apps run from its
    /// fixture home, so no real app on this Mac is touched. A dry run, so nothing is removed. The caller stops `running` in its
    /// `defer`, before the home is removed.
    @MainActor private func reviewSynthWhileOpen(_ app: XCUIApplication, home: URL, running: Process) throws -> URL {
        turnOnDryRun(app)
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 1, in: home)
        app.launchEnvironment["CACHEDROP_TEST_PREPARE_SYNTH_APP"] = "1"
        let container = home.appendingPathComponent("Library/Containers/com.maker.synth/Data/state.db")
        try FileManager.default.createDirectory(at: container.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 60_000).write(to: container)
        running.executableURL = synth.appendingPathComponent("Contents/MacOS/main")
        running.arguments = ["600"]
        // The unsandboxed DEBUG app prepares only this known fixture, before the runner attempts its launch (#383).
        app.launch()
        let verification = Process()
        verification.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verification.arguments = ["--verify", "--strict", synth.path]
        verification.standardOutput = FileHandle.nullDevice
        verification.standardError = FileHandle.nullDevice
        try verification.run()
        verification.waitUntilExit()
        XCTAssertEqual(verification.terminationStatus, 0, "The fixture app needs a valid bundle signature before launch (#383)")
        waitForCatalogScan(app)
        openApplications(app, ["apps"])
        let row = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)
        XCTAssertEqual(row.value as? Int, 1)
        try running.run()
        app.buttons["Review cleanup"].click()
        return synth
    }

    /// #377, #560: an app that is open when its uninstall is reviewed. Its two rows are one line, "Synth is open, so its items
    /// will be skipped", with one "Quit Synth"; the link asks it to quit, its rows are checked again and become cleanable, and
    /// the sheet stays open.
    @MainActor func testTheReviewQuitsTheAppHoldingARowAndTheRowBecomesCleanable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let running = Process()
        // The fixture app is stopped whatever happens, before its home is removed.
        defer {
            if running.isRunning { running.terminate(); running.waitUntilExit() }
            app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home)
        }
        let synth = try reviewSynthWhileOpen(app, home: home, running: running)
        let skipped = app.staticTexts["reviewSkipped-uninstall-app"]
        XCTAssertTrue(skipped.waitForExistence(timeout: 10), "The app's rows will be skipped while it is open")
        XCTAssertTrue((skipped.value as? String ?? skipped.label).hasPrefix("Synth is open, so its items will be skipped · "), skipped.debugDescription)
        XCTAssertFalse(app.staticTexts["reviewSkipped-uninstall-app-files"].exists, "One line for the app and its files (#560)")
        let quits = app.links.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reviewQuit-"))
        XCTAssertEqual(quits.count, 1, "One link for the holder")
        let quit = quits.firstMatch
        XCTAssertTrue(quit.identifier.hasPrefix("reviewQuit-uninstall-app|"), quit.identifier)
        XCTAssertEqual(quit.label, "Quit Synth")

        quit.click()
        XCTAssertTrue(skipped.waitForNonExistence(timeout: 20), "Once Synth quits, its rows are checked again and can be cleaned")
        running.waitUntilExit()
        XCTAssertFalse(running.isRunning, "The fixture app was asked to quit and did")
        XCTAssertFalse(quits.firstMatch.exists)
        // The recheck changes no choice, so the sheet stays open (#307).
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sheetFooter").firstMatch.buttons["Clean up"].exists)
        XCTAssertFalse(app.staticTexts["Your choices changed. Check the items and try again."].exists)
        app.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: synth.path))
    }

    /// #560: the holder quits outside the sheet (here the journey stops it, as ⌘Q in the app would). Its line goes away by
    /// itself and the sheet stays open. Sizes count only what will be cleaned: while Synth holds every row, the group and its
    /// line show no size (never Zero KB) and the skipped size shows once, on Synth's line; once Synth is gone, it is the group's.
    @MainActor func testTheReviewDropsAHoldersLineWhenItQuitsOutsideTheSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let running = Process()
        defer {
            if running.isRunning { running.terminate(); running.waitUntilExit() }
            app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home)
        }
        _ = try reviewSynthWhileOpen(app, home: home, running: running)
        let skipped = app.staticTexts["reviewSkipped-uninstall-app"]
        XCTAssertTrue(skipped.waitForExistence(timeout: 10))
        let text = skipped.value as? String ?? skipped.label
        let size = try XCTUnwrap(text.components(separatedBy: " · ").last, text)
        XCTAssertNotEqual(size, "Zero KB", text)
        // The page behind the sheet shows Synth's size too, so sizes are looked for in the sheet only.
        let sheet = app.sheets.firstMatch
        XCTAssertFalse(sheet.staticTexts["Zero KB"].exists, "A group that cleans nothing shows no size")
        XCTAssertFalse(sheet.staticTexts[size].exists, "The skipped size shows only on Synth's line")

        running.terminate()
        running.waitUntilExit()
        XCTAssertTrue(skipped.waitForNonExistence(timeout: 20), "Synth's line goes once it quits, without the sheet's link")
        XCTAssertTrue(sheet.staticTexts[size].waitForExistence(timeout: 5), "Its rows will be cleaned, so the group counts them")
        XCTAssertFalse(sheet.staticTexts["Zero KB"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sheetFooter").firstMatch.buttons["Clean up"].exists, "The sheet stays open")
        XCTAssertFalse(app.staticTexts["Your choices changed. Check the items and try again."].exists)
        app.buttons["Cancel"].click()
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
        openApplications(app, ["apps"])

        let synthRow = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(synthRow.waitForExistence(timeout: 10))
        func choose(_ count: Int) -> XCUIElement { app.disclosureTriangles.matching(NSPredicate(format: "label == %@", "Choose items · \(count)")).firstMatch }
        XCTAssertTrue(choose(4).exists, "Synth: the app, its preferences and container, and the folder named like it")
        XCTAssertTrue(choose(3).exists, "Pad: the app, its preferences and container")
        revealAndClick(synthRow, in: app)
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planItem-uninstall-app-files-com.maker.synth.plist"].value as? Int, 1, "Its own preferences are ticked with it")
        XCTAssertEqual(app.checkBoxes["planItem-uninstall-app-files-com.maker.pad.plist"].value as? Int, 0, "Pad's are Pad's")

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
        XCTAssertFalse(app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH 'planItem-' AND identifier ENDSWITH '-Synth'")).firstMatch.exists, "Synth's folder is never offered as Pad's, nor as a leftover while Pad is installed")
        XCTAssertFalse(app.checkBoxes["planCategory-leftovers"].exists)
    }

    /// #303, #306: an uninstall rescans when it ends, and the bar shows its progress. Decision 134 (#647): that rescan reads
    /// again only what the uninstall touched, so while it runs the uninstalled app's row is gone and the other app's row can be
    /// ticked and reviewed; Clean up waits for the scan.
    @MainActor func testTheRescanAfterAnUninstallKeepsOtherAppsUsableAndTheUninstalledRowGone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        let pad = try addApp("Pad", id: "com.padmaker.pad", bytes: 90_000, in: home)
        // The rescan after the run holds, so it is still running while the page is used.
        app.launchEnvironment["CACHEDROP_TEST_RESCAN_PAUSE"] = "20"
        app.launch()
        waitForCatalogScan(app)
        openApplications(app, ["apps"])

        let synthRow = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(synthRow.waitForExistence(timeout: 10))
        revealAndClick(synthRow, in: app)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.buttons["Clean up"].waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20))
        app.buttons["Done"].click()

        let progress = app.staticTexts["catalogScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "The run rescans, and the bar shows its progress")
        XCTAssertTrue(synthRow.waitForNonExistence(timeout: 5), "The uninstalled app's row is gone at once")
        let padRow = element(app, "applicationsApp-" + pad.path, .checkBox)
        XCTAssertTrue(padRow.waitForExistence(timeout: 5), "The other app stays listed")
        XCTAssertTrue(progress.exists, "Still rescanning")
        XCTAssertTrue(padRow.isEnabled, "Not dimmed: the rescan doesn't read it again")
        revealAndClick(padRow, in: app)
        XCTAssertEqual(padRow.value as? Int, 1, "Ticked during the rescan")
        let review = app.buttons["Review cleanup"]
        XCTAssertTrue(review.isEnabled, "Review cleanup doesn't wait for the rescan")
        review.click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "apps").waitForExistence(timeout: 10))
        let footer = app.descendants(matching: .any).matching(identifier: "sheetFooter").firstMatch
        XCTAssertTrue(progress.exists, "Still rescanning")
        XCTAssertFalse(footer.buttons["Clean up"].isEnabled, "Clean up waits for the scan")
        XCTAssertTrue(progress.waitForNonExistence(timeout: 120))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: footer.buttons["Clean up"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, "The scan kept Pad's choices: the review stays open and can run")
        footer.buttons["Cancel"].click()
        XCTAssertFalse(synthRow.exists, "Still gone after the rescan")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pad.path), "Pad was only reviewed")
    }

    /// Decision 159 (#716): uninstalling a driver and one of Reason's devices reads only their rows again, as an app's uninstall
    /// does (134): while the rescan after it runs, their rows are gone, their groups' counts drop, and the other device stays
    /// listed and clickable, undimmed. The rescan holds only when it isn't a full scan, so the held progress shows it read less.
    @MainActor func testUninstallingADriverAndAReasonDeviceUpdatesTheirRowsWithoutAFullScan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let devices = home.appendingPathComponent("Library/Application Support/Propellerhead Software/Optional REs")
        for (name, bytes) in [("Pangea", 60_000), ("Humana", 90_000)] {
            let file = devices.appendingPathComponent(name).appendingPathComponent("data.bin")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: file)
        }
        let driver = home.appendingPathComponent("Library/Audio/Plug-Ins/HAL/Loopback.driver")
        try FileManager.default.createDirectory(at: driver.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.loop.back"], format: .xml, options: 0)
            .write(to: driver.appendingPathComponent("Contents/Info.plist"))
        app.launchEnvironment["CACHEDROP_TEST_RESCAN_PAUSE"] = "20"
        app.launch()
        waitForCatalogScan(app)
        openApplications(app, ["drivers", "plug-ins"])

        XCTAssertEqual(applicationsSection(app, "audio software").label, "Show groups · 4", "All four groups")
        func box(_ id: String) -> XCUIElement { element(app, id, .checkBox) }
        let driverBox = box("applicationsDriver-" + driver.path)
        let pangea = box("applicationsPlugIn-" + devices.appendingPathComponent("Pangea").path)
        let humana = box("applicationsPlugIn-" + devices.appendingPathComponent("Humana").path)
        XCTAssertTrue(driverBox.waitForExistence(timeout: 10) && pangea.waitForExistence(timeout: 5) && humana.exists)
        tick(driverBox, in: app); tick(pangea, in: app)
        app.buttons["Review cleanup"].click()
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: driver.path), "The driver went to the Trash")
        app.buttons["Done"].click()

        let progress = app.staticTexts["catalogScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "The run rescans")
        XCTAssertTrue(driverBox.waitForNonExistence(timeout: 5), "The driver's row is gone at once")
        XCTAssertFalse(pangea.exists, "So is the device's")
        XCTAssertTrue(element(app, "applicationsGroup-drivers").staticTexts["Empty"].waitForExistence(timeout: 5), "Drivers reads Empty at once")
        XCTAssertTrue(app.disclosureTriangles["Choose plug-ins · 1"].exists, "Plug-ins' count drops at once")
        XCTAssertTrue(humana.waitForExistence(timeout: 5), "The other device stays listed")
        XCTAssertTrue(progress.exists, "Still rescanning: the held rescan reads only the touched rows")
        XCTAssertTrue(humana.isEnabled, "Not dimmed: the rescan doesn't read it again")
        XCTAssertTrue(progress.waitForNonExistence(timeout: 120))
        XCTAssertTrue(humana.exists && !driverBox.exists && !pangea.exists, "The same rows after the rescan")
    }

    /// #556, Decision 123: a Smart clean that uninstalled nothing leaves Apps and Plug-ins readable and clickable during the
    /// rescan that follows, even on a first visit: an app can be ticked and reviewed without waiting. Clean up waits for the
    /// scan, and the review stays open when it ends without changing the choices (Decision 54).
    @MainActor func testApplicationsDontWaitForTheRescanAfterASmartCleanThatUninstalledNothing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        // The rescan after the run holds, so it is still running when the review opens.
        app.launchEnvironment["CACHEDROP_TEST_RESCAN_PAUSE"] = "20"
        app.launch()
        waitForCatalogScan(app)
        app.typeKey("2", modifierFlags: .command)
        let cleanUp = app.buttons["smartCleanCleanUp"]
        XCTAssertTrue(cleanUp.waitForExistence(timeout: 10))
        cleanUp.click()
        XCTAssertTrue(reviewLine(app, "permanentlyRemoved", "developer").waitForExistence(timeout: 10))
        cleanUpFromReview(app)
        let done = app.buttons["smartCleanDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        done.click()
        let progress = app.staticTexts["catalogScanProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "The run rescans")

        openApplications(app, ["apps"])
        let row = element(app, "applicationsApp-" + synth.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The apps are listed during the rescan")
        XCTAssertTrue(progress.exists, "Still rescanning")
        XCTAssertTrue(row.isEnabled, "Not dimmed: the run changed no app")
        revealAndClick(row, in: app)
        XCTAssertEqual(row.value as? Int, 1, "Ticked during the rescan")
        let review = app.buttons["Review cleanup"]
        XCTAssertTrue(review.isEnabled, "Review cleanup doesn't wait for the rescan")
        review.click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "apps").waitForExistence(timeout: 10))
        let footer = app.descendants(matching: .any).matching(identifier: "sheetFooter").firstMatch
        XCTAssertTrue(progress.exists, "Still rescanning")
        XCTAssertFalse(footer.buttons["Clean up"].isEnabled, "Clean up waits for the scan")
        XCTAssertTrue(progress.waitForNonExistence(timeout: 120))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: footer.buttons["Clean up"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, "The scan kept the choices: the review stays open and can run")
        footer.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: synth.path), "Nothing was uninstalled")
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
        openApplications(app, ["apps"])

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
        let run = app.disclosureTriangles.matching(NSPredicate(format: "label CONTAINS %@", "Uninstalled Synth")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        revealAndClick(run, in: app)
        let putBack = app.descendants(matching: .any)["putBack-Synth.app"]
        XCTAssertTrue(putBack.waitForExistence(timeout: 10))
        revealAndClick(putBack, in: app)
        XCTAssertTrue(app.staticTexts["putBackDone-Synth.app"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: synth.path), "The app is back where it was")

        openApplications(app, ["apps"])
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
        openApplications(app, ["plug-ins"])

        let row = element(app, "applicationsPlugIn-" + au.path, .checkBox)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "A product CacheDrop can partly uninstall has a checkbox")
        XCTAssertEqual(row.value as? Int, 0, "Nothing is ticked when the page opens")
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label == 'Choose items · 1 · 1 stays'")).firstMatch.exists, "Counts what can be chosen")
        revealAndClick(row, in: app)
        expandDisclosures(in: app)
        XCTAssertEqual(app.checkBoxes["planItem-uninstall-plugin-Pro Synth.vst3"].value as? Int, 1, "Its removable format is ticked with it")
        XCTAssertFalse(app.checkBoxes["planItem-uninstall-plugin-Pro Synth.component"].exists, "A format that needs a password has no checkbox")
        XCTAssertEqual(element(app, "applicationsPassword-" + au.path, .staticText).value as? String, "AU: Needs your password to remove")
        XCTAssertTrue(element(app, "applicationsReveal-" + au.path, .link).exists, "Reveal in Finder, with no vendor tool installed")
        // A product that is only an AUv3 goes with its app (#288).
        XCTAssertEqual(element(app, "applicationsInsideApp-" + appex.path, .staticText).value as? String, "Goes with Pad")

        app.buttons["Review cleanup"].click()
        let staying = element(app, "reviewStaying-" + au.path + "-password", .staticText)
        XCTAssertTrue(staying.waitForExistence(timeout: 5))
        let line = reviewLine(app, "movedToTrash", "apps").value as? String ?? ""
        XCTAssertTrue(line.hasPrefix("Apps, audio software and their files"), "The review names audio software too: " + line)
        XCTAssertEqual(staying.value as? String, "Pro Synth: 1 file needs your password to remove, so it stays. Remove it in Finder if you want it gone.",
                       "The review says what stays, why and what to do (#354)")
        XCTAssertTrue(element(app, "reviewStayingLink-" + au.path + "-password", .link).exists, "With Reveal in Finder (#354)")
        cleanUpFromReview(app)
        XCTAssertTrue(app.buttons["View history"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vst3.path), "The VST3 went to the Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: au.path), "What needs a password is never acted on")

        app.buttons["View history"].click()
        XCTAssertTrue(app.disclosureTriangles.matching(NSPredicate(format: "label CONTAINS %@", "Uninstalled Pro Synth · 1 item")).firstMatch.waitForExistence(timeout: 10))
    }

    /// #270, #308: while the scan runs each section shows skeleton rows. Decision 176: a section that finds nothing is one row
    /// reading Empty, with no second line saying so.
    @MainActor func testSectionsShowLoadingThenEmptyStates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.5"
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        waitForOverview(app)
        openApplications(app)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsLoading-apps"].waitForExistence(timeout: 5), "Apps say they are loading")
        XCTAssertTrue(app.descendants(matching: .any)["applicationsLoading-leftovers"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["applicationsSummary"].exists, "While the lists load, the summary waits with them")
        for section in ["apps", "audio", "leftovers"] {
            let row = element(app, "applicationsSection-" + section)
            XCTAssertTrue(row.staticTexts["Empty"].waitForExistence(timeout: 120), "\(section) reads Empty")
        }
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Empty'")).count, 3, "One Empty per section")
        XCTAssertFalse(app.staticTexts["No files from deleted apps"].exists, "No second row saying so")
        XCTAssertFalse(app.descendants(matching: .any)["applicationsLoading-apps"].exists)
        // #575: nothing on the page can be ticked, so no card reading "—" and "0 items selected".
        XCTAssertFalse(app.descendants(matching: .any)["applicationsSummary"].exists)
    }

    /// #310: when the list of apps can't be read (Spotlight didn't answer), Apps says so with Scan again, never "no apps";
    /// once it can be read, Scan again lists them.
    @MainActor func testAppsSayTheListCouldntBeReadAndTryAgainListsThem() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let pad = try addApp("Pad", id: "com.example.pad", bytes: 10_000, in: home)
        let unreadable = home.appendingPathComponent(".cachedrop-test-apps-unreadable")
        try Data().write(to: unreadable)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()
        waitForOverview(app)
        openApplications(app)
        let notice = element(app, "applicationsUnreadable")
        XCTAssertTrue(notice.waitForExistence(timeout: 60), "Apps say the list couldn't be read")
        XCTAssertFalse(element(app, "applicationsSection-apps").staticTexts["Empty"].exists, "Couldn't read is never Empty")

        try FileManager.default.removeItem(at: unreadable)
        element(app, "applicationsUnreadableAction", .button).click()
        openApplicationsSections(app, ["apps"])
        XCTAssertTrue(element(app, "applicationsApp-" + pad.path).waitForExistence(timeout: 5), "Scan again listed the app")
        XCTAssertFalse(notice.exists)
    }

    /// #270, #349: a leftover ticked on Applications is reviewed and cleaned there (dry run); Overview calls it "Selected"
    /// only once its tick differs from the recommended default.
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

        openApplications(app)
        let category = app.checkBoxes["planCategory-leftovers"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        // Tied to its removed app by its container, so it arrives ticked: the recommended default, not "Selected".
        XCTAssertEqual(category.value as? Int, 1)
        // #481: the plan's count leaves it out, so its summary says one more is selected on Applications, with a link there.
        app.typeKey("3", modifierFlags: .command)
        let elsewhere = element(app, "liveSelectionSummaryElsewhere")
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 5), "The plan says what's selected on Applications")
        XCTAssertEqual(elsewhere.label, "1 on Applications")
        elsewhere.click()
        XCTAssertTrue(app.checkBoxes["planCategory-leftovers"].waitForExistence(timeout: 5), "The link opens Applications")
        app.typeKey("1", modifierFlags: .command)
        let row = app.buttons["overviewCategory-leftovers"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse((row.value as? String ?? "").contains("Selected"), String(describing: row.value))

        openApplications(app)
        XCTAssertEqual(app.checkBoxes["planCategory-leftovers"].value as? Int, 1, "Its tick is kept")
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(reviewLine(app, "movedToTrash", "leftovers").waitForExistence(timeout: 5))
        cleanUpFromReview(app)
        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path), "A dry run moves nothing")
    }

    /// #525: the summary covers the current Applications selection, including search-hidden and cross-page changes.
    @MainActor func testApplicationsSummaryShowsSelectedTrashSizeAcrossSectionsAndSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app), home = try configureCatalogHome(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        let synth = try addApp("Synth", id: "com.maker.synth", bytes: 90_000, in: home)
        let plugIn = home.appendingPathComponent("Library/Audio/Plug-Ins/VST3/Echo.vst3")
        let info = plugIn.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.effects.echo.vst3"], format: .xml, options: 0).write(to: info)
        try Data(repeating: 3, count: 60_000).write(to: plugIn.appendingPathComponent("Contents/data"))
        let leftover = home.appendingPathComponent("Library/Containers/com.gone.synth/Data/state.db")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 100_000).write(to: leftover)
        app.launchEnvironment["CACHEDROP_TEST_DISCOVERY_PAUSE"] = "0.1"
        app.launch(); waitForCatalogScan(app)
        openApplications(app, ["apps", "plug-ins"])
        let count = app.staticTexts["applicationsSummary"], size = app.staticTexts["applicationsSummaryValue"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        func text(_ element: XCUIElement) -> String { element.value as? String ?? element.label }
        XCTAssertEqual(text(count), "1 item selected", "Recommended leftovers count; other pages' caches do not")
        XCTAssertTrue(text(size).hasSuffix(" to Trash"))
        XCTAssertEqual(text(count), text(app.staticTexts["actionStripNote"]))
        XCTAssertLessThan(size.frame.minY, app.buttons["applicationsSort-name"].frame.minY)
        let leftoverSize = text(size)
        let synthRow = element(app, "applicationsApp-" + synth.path, .checkBox)
        revealAndClick(synthRow, in: app)
        XCTAssertEqual(text(count), "2 items selected")
        XCTAssertNotEqual(text(size), leftoverSize)
        let appAndLeftoverSize = text(size)
        let plugInRow = element(app, "applicationsPlugIn-" + plugIn.path, .checkBox)
        revealAndClick(plugInRow, in: app)
        XCTAssertEqual(text(count), "3 items selected")
        XCTAssertNotEqual(text(size), appAndLeftoverSize)
        XCTAssertEqual(text(count), text(app.staticTexts["actionStripNote"]))
        let selectedSize = text(size)
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForExistence(timeout: 5))
        XCTAssertEqual(text(size), selectedSize, "A rescan keeps the current estimate visible")
        XCTAssertEqual(text(count), "3 items selected")
        XCTAssertTrue(app.staticTexts["catalogScanProgress"].waitForNonExistence(timeout: 120))
        XCTAssertEqual(text(size), selectedSize)
        let search = app.textFields["applicationsSearch"]
        revealAndClick(search, in: app); search.typeText("nothing-matches-this")
        XCTAssertTrue(element(app, "applicationsNoMatches").waitForExistence(timeout: 5))
        XCTAssertEqual(text(size), selectedSize, "Hidden selections remain included")
        XCTAssertEqual(text(count), "3 items selected")
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        app.typeKey("2", modifierFlags: .command)
        revealAndClick(app.checkBoxes["smartCleanCategory-leftovers"], in: app)
        openApplications(app, ["apps", "plug-ins"])
        XCTAssertEqual(text(count), "2 items selected", "Another page changes the same selection")
        XCTAssertNotEqual(text(size), selectedSize)
        revealAndClick(synthRow, in: app); revealAndClick(plugInRow, in: app)
        XCTAssertEqual(text(count), "0 items selected")
        XCTAssertEqual(text(size), "—", "No selection is not an estimate of zero freed space")
    }

}
