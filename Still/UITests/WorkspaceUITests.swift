import XCTest

final class WorkspaceUITests: XCTestCase {
    @MainActor
    func testInspectingFixturesPreservesWindowAndNeverSelects() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-workspace"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic data — no personal files accessed"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let bounds = window.frame
        app.buttons["Review Downloads"].click()
        XCTAssertTrue(app.staticTexts["Downloads inspection"].exists)
        app.buttons["Inspect Summer trip.mov"].click()
        XCTAssertTrue(app.staticTexts["Downloads/Trips/Summer trip.mov"].exists)
        XCTAssertTrue(app.staticTexts["Nothing selected"].exists)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["Selected for Trash"].exists)
        XCTAssertTrue(app.staticTexts["Nothing selected"].exists)
        XCTAssertEqual(window.frame.width, bounds.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, bounds.height, accuracy: 1)
        app.buttons["Choose items"].click()
        XCTAssertTrue(app.staticTexts["Summer trip.mov"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(window.frame, bounds)
    }
    @MainActor
    func testKeyboardNavigationAndAppearanceKeepWindowBounds() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-workspace"]
        app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Selected for Trash"].waitForExistence(timeout: 3))
        for appearance in ["Dark", "Light"] {
            app.popUpButtons.firstMatch.click()
            app.menuItems[appearance].click()
            XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, appearance)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Review Downloads"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor
    func testChooseDisposableFolderAndInspectWithoutMutation() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillUI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("camera.txt")
        try Data(repeating: 65, count: 137).write(to: file)
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.typeKey("a", modifierFlags: .command)
        path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        XCTAssertTrue(app.buttons["Inspect camera.txt"].waitForExistence(timeout: 5))
        app.buttons["Inspect camera.txt"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", file.path)).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Logical size: 137 bytes"].exists)
        XCTAssertTrue(app.buttons["Quick Look"].isEnabled)
        XCTAssertTrue(app.buttons["Reveal in Finder"].exists)
        XCTAssertTrue(app.staticTexts["Observed"].exists)
        XCTAssertTrue(app.staticTexts["iCloud in this scan"].exists)
        XCTAssertTrue(app.staticTexts["Pinning: Unknown — not established by this scan"].exists)
        XCTAssertFalse(app.buttons["Remove local download"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: file), Data(repeating: 65, count: 137))
    }

    @MainActor
    func testUnavailableSelectedFolderShowsUnknownCoverageAndRecovery() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillCoverageUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("temporary.txt"))
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeKey("a", modifierFlags: .command); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Complete scope logical bytes: 1 bytes"].waitForExistence(timeout: 10))
        try FileManager.default.removeItem(at: root)
        app.buttons["Recheck folder"].click()
        XCTAssertTrue(app.staticTexts["Complete scope logical bytes: Unknown"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Identified local downloaded allocation: Unknown · 0 files"].exists)
        XCTAssertTrue(app.staticTexts["No readable entries observed; this is not an empty-folder result."].exists)
        XCTAssertTrue(app.buttons["Choose folder again…"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Last complete observation:")).firstMatch.exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor
    func testLiveSelectionSurvivesSearchNavigationAndWindowClosure() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("selected.pdf"))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        app.buttons["Choose folder…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        app.dialogs.buttons["Scan folder"].click()
        let checkbox = app.checkBoxes["Select selected.pdf"]
        for _ in 0..<5 { if checkbox.exists { break }; app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350) }
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(checkbox.value as? Int, 0)
        app.buttons["Inspect selected.pdf"].click()
        XCTAssertEqual(checkbox.value as? Int, 0)
        checkbox.click()
        let search = app.textFields["Search inspected files"]
        search.click(); search.typeText("does-not-match")
        XCTAssertTrue(app.staticTexts["1 file selected"].exists)
        app.buttons["View cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["liveSelectionSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        let bounds = app.windows.firstMatch.frame
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.checkBoxes["Selected selected.pdf"].click()
        XCTAssertFalse(app.checkBoxes["Selected selected.pdf"].exists)
        app.checkBoxes["Select selected.pdf"].click()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertFalse(app.checkBoxes["Selected selected.pdf"].exists)
    }

    @MainActor
    func testBulkMixedReviewCancelAndImmutableApprovalKeepWindowStable() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<20 {
            let path = index % 2 == 0 ? "file\(index).pdf" : "Nested/file\(index).pdf"
            try Data([1]).write(to: root.appendingPathComponent(path))
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(category.value as? Int, 0)
        let bounds = app.windows.firstMatch.frame
        category.click()
        let allSelected = NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "20 files selected", "20 files selected")
        XCTAssertTrue(app.staticTexts.matching(allSelected).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        let item = app.checkBoxes.matching(NSPredicate(format: "label BEGINSWITH %@", "Selected ")).firstMatch
        for _ in 0..<4 { if item.exists { break }; app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250) }
        XCTAssertTrue(item.exists, app.debugDescription); item.click()
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 2000)
        XCTAssertEqual(category.value as? Int, 2)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5))
        let confirmation = app.sheets.containing(.staticText, identifier: "Review Move to Trash").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let disclosure = confirmation.disclosureTriangles.firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.click()
        XCTAssertTrue(app.buttons["Approve Move to Trash"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "19 files selected", "19 files selected")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5), "Cancel must restore focus to Review cleanup")
        app.buttons["Approve Move to Trash"].click()
        XCTAssertTrue(app.staticTexts["Approved batch: 19 files · No files moved."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("file0.pdf")), Data([1]))
    }

    @MainActor
    func testDesignReviewCaptures() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--fixture-workspace", "--design-initial-size"]; app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            app.typeKey("1", modifierFlags: .command); capture("overview-" + theme)
            app.buttons["Review Downloads"].click(); capture("inspection-" + theme)
            app.buttons["View cleanup plan"].click(); capture("plan-" + theme)
            app.typeKey("4", modifierFlags: .command); capture("settings-" + theme)
        }
    }

    @MainActor
    func testNativeDesignReviewAndMinimumGalleryCaptures() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("selected.pdf"))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click(); capture("native-overview-" + theme)
        }
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click(); capture("native-inspection-" + theme)
        }
        let selected = app.checkBoxes["Select selected.pdf"]
        for _ in 0..<5 { if selected.exists { break }; app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300) }
        XCTAssertTrue(selected.waitForExistence(timeout: 5)); selected.click()
        XCTAssertEqual(selected.value as? Int, 1)

        app.buttons["View cleanup plan"].click()
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("native-plan-" + theme)
            XCTAssertTrue(app.buttons["Review cleanup"].isEnabled && app.buttons["Review cleanup"].isHittable)
            app.buttons["Review cleanup"].click()
            XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5))
            capture("native-confirmation-" + theme)
            XCTAssertTrue(app.buttons["Cancel"].isHittable && app.buttons["Approve Move to Trash"].isHittable)
            app.buttons["Cancel"].click()
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.typeKey("4", modifierFlags: .command); capture("native-locations-" + theme)
            app.typeKey("2", modifierFlags: .command)
        }
        app.terminate()
        app.launchArguments = ["--future-milestones", "--design-initial-size"]
        app.launch(); app.typeKey("5", modifierFlags: .command)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click(); capture("native-alert-settings-" + theme)
        }

    }

    @MainActor
    func testMinimumGalleryStatesAndOpaqueChromeCaptures() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        app.launchArguments = ["--design-gallery", "--design-minimum"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native design system"].waitForExistence(timeout: 10))
        let minimum = app.windows.firstMatch.frame
        XCTAssertEqual(minimum.width, 900, accuracy: 1)
        XCTAssertEqual(minimum.height, 640, accuracy: 1)
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("gallery-minimum-" + theme)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1200)
            capture("gallery-states-minimum-" + theme)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 2000)
        }
        app.checkBoxes["Opaque chrome"].click()
        capture("gallery-minimum-opaque-Dark")
        XCTAssertEqual(app.windows.firstMatch.frame, minimum)
    }

    @MainActor
    func testMinimumPopulatedPlanAndConfirmationRemainReachable() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Long project folder name for layout and keyboard review")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<12 { try Data([1]).write(to: nested.appendingPathComponent("A long descriptive document name with several words - \(i).pdf")) }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", "--design-minimum", "--design-opaque-chrome"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: .command)
        app.checkBoxes["downloadsCategorySelection"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "12 files selected")).firstMatch.waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        XCTAssertEqual(bounds.width, 900, accuracy: 1); XCTAssertEqual(bounds.height, 640, accuracy: 1)
        func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        for theme in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[theme].click()
            capture("native-plan-minimum-opaque-" + theme)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1500)
            XCTAssertTrue(app.buttons["Review cleanup"].isEnabled && app.buttons["Review cleanup"].isHittable)
            app.buttons["Review cleanup"].click()
            XCTAssertTrue(app.staticTexts["Review Move to Trash"].waitForExistence(timeout: 5))
            capture("native-confirmation-minimum-" + theme)
            XCTAssertTrue(app.buttons["Cancel"].isHittable && app.buttons["Approve Move to Trash"].isHittable)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertFalse(app.staticTexts["Review Move to Trash"].exists)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 2000)
        }
    }

    @MainActor
    func testOwnedLargeScanShowsBoundedProgressAndAcknowledgesStop() throws {
        try assertOwnedProgress(minimum: false)
    }
    @MainActor
    func testMinimumOwnedLargeScanKeepsProgressAndStopReachable() throws {
        try assertOwnedProgress(minimum: true)
    }
    @MainActor
    private func assertOwnedProgress(minimum: Bool) throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
        let available = try temporary.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        guard available > 1_900_000_000 else { throw XCTSkip("Owned progress fixture requires conservative disk headroom") }
        let root = temporary.appendingPathComponent("StillProgressUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        for index in 0..<50_000 {
            try autoreleasepool {
                if index % 1000 == 0 { try manager.createDirectory(at: root.appendingPathComponent("batch-\(index / 1000)"), withIntermediateDirectories: false) }
                try Data().write(to: root.appendingPathComponent("batch-\(index / 1000)/file-\(index)"))
            }
        }
        let app = XCUIApplication()
        app.launchArguments = [minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))
        let bounds = app.windows.firstMatch.frame
        for appearance in ["Light", "Dark"] {
            app.popUpButtons.firstMatch.click(); app.menuItems[appearance].click()
            if appearance == "Light" {
                app.buttons["Choose folder…"].click()
                app.typeKey("g", modifierFlags: [.command, .shift])
                let field = app.textFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.typeKey("a", modifierFlags: .command); field.typeText(root.path)
                app.typeKey(.return, modifierFlags: [])
                app.dialogs.buttons["Scan folder"].click()
            } else { app.buttons["Recheck folder"].click() }
            XCTAssertTrue(app.staticTexts["scanProgressSummary"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Stop scan"].waitForExistence(timeout: 1))
            XCTAssertTrue(bounds.contains(app.buttons["Stop scan"].frame))
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "bounded-scan-progress-" + (minimum ? "minimum-" : "") + appearance; shot.lifetime = .keepAlways; add(shot)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -40)
            app.buttons["Stop scan"].click()
            let stopped = app.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] 'Stop requested' OR value CONTAINS[c] 'Scan stopped'"))
            XCTAssertTrue(stopped.firstMatch.waitForExistence(timeout: 1))
            XCTAssertTrue(app.buttons["Recheck folder"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertFalse(app.buttons["Review cleanup"].exists)
        }
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("batch-0/file-0").path))
    }

    @MainActor
    func testInitialReviewWindowFitsConstrainedDisplayAndKeepsToolbarReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-workspace", "--design-initial-size", "--design-constrained-screen"]
        app.launch()
        XCTAssertTrue(app.buttons["Review Downloads"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(bounds.width, 1024)
        XCTAssertLessThanOrEqual(bounds.height, 720)
        XCTAssertGreaterThanOrEqual(bounds.width, 900)
        XCTAssertGreaterThanOrEqual(bounds.height, 640)
        XCTAssertTrue(app.popUpButtons["Appearance"].isHittable)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.popUpButtons["Appearance"].click(); app.menuItems["Dark"].click()
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Review Downloads"].isHittable)
        XCTAssertTrue(app.popUpButtons["Appearance"].isHittable)
    }

    @MainActor
    func testRefreshPreservesChoicesAndSearchThenExplainsChangedTargets() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillSelectionUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("selected.pdf")
        try Data([1, 2, 3]).write(to: chosen)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-slow-refresh", "--design-initial-size"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        XCTAssertTrue(app.staticTexts["Observed"].waitForExistence(timeout: 10))
        let checkbox = app.checkBoxes["Select selected.pdf"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5)); checkbox.click()
        XCTAssertEqual(checkbox.value as? Int, 1)
        app.buttons["View cleanup plan"].click()
        let search = app.textFields["Search Downloads items"]
        search.click(); search.typeText("selected.pdf")
        let bounds = app.windows.firstMatch.frame
        func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        for i in 0..<500 { try Data().write(to: root.appendingPathComponent("new-\(i).txt")) }
        let recheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Recheck location:")).firstMatch
        XCTAssertTrue(recheck.isHittable); recheck.click()
        XCTAssertTrue(app.buttons["Stop refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        app.buttons["Stop refresh"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Refresh required ·")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("refresh-required-" + theme) }
        recheck.click()
        XCTAssertTrue(app.buttons["Stop refresh"].waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["Review cleanup"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(search.value as? String, "selected.pdf")
        XCTAssertTrue(app.checkBoxes["Selected selected.pdf"].exists)
        XCTAssertTrue(app.staticTexts["1 file selected"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        // Same-size change: contents do not need to be read to invalidate the original observation.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)], ofItemAtPath: chosen.path)
        recheck.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "File changed or is no longer eligible.")).firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        XCTAssertTrue(app.checkBoxes["Select selected.pdf"].exists)
        for theme in ["Light", "Dark"] { app.popUpButtons["Appearance"].click(); app.menuItems[theme].click(); capture("refresh-changed-" + theme) }
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        XCTAssertEqual(try Data(contentsOf: chosen), Data([1, 2, 3]))
    }

}
