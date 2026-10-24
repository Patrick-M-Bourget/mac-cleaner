import XCTest
import Darwin
import StillCore

final class CapacityRefreshUITests: XCTestCase {
    @MainActor func testCapacityRefreshIsSeparateFromScanAndKeepsOverviewContext() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = ["--design-minimum"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let refresh = app.buttons["Refresh capacity"]
        guard refresh.waitForExistence(timeout: 10) else {
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "capacity-refresh-missing-action"; capture.lifetime = .keepAlways; add(capture)
            XCTFail("Overview needs a capacity-only refresh action separate from Scan again")
            return
        }
        let window = app.windows.firstMatch.frame
        let coverage = app.staticTexts["No included locations with current observations."]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        let coverageValue = coverage.value as? String ?? coverage.label
        XCTAssertTrue(app.buttons["Scan again"].exists)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(refresh.frame))
        refresh.click()
        XCTAssertTrue(app.staticTexts["Storage overview"].exists)
        XCTAssertTrue(coverage.exists)
        XCTAssertEqual(coverage.value as? String ?? coverage.label, coverageValue)
        XCTAssertFalse(app.buttons["Stop scan"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, window)
        app.buttons["Cleanup plan"].click()
        XCTAssertTrue(app.staticTexts["Selected for Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "0 files selected", "0 files selected")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Review cleanup"].isEnabled)
        app.buttons["Overview"].click()
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, window)
    }

    @MainActor func testCompletedScanRefreshesCapacityWithoutChangingChoices() throws { try completedJourney(cleanup: false) }
    @MainActor func testCompletedCleanupRefreshesCapacityWithoutRewritingResults() throws { try completedJourney(cleanup: true) }

    @MainActor private func completedJourney(cleanup: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillSelectionUI-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Review-" + UUID().uuidString + ".pdf")
        let original = Data([1, 2, 3, 4]); try original.write(to: file)
        defer { app.terminate(); try? manager.removeItem(at: state); try? manager.removeItem(at: root) }
        func sample(_ available: Int64) throws {
            let data = try JSONSerialization.data(withJSONObject: ["available": available, "total": 512_000_000_000, "metric": "important"])
            try data.write(to: state.appendingPathComponent("capacity-reading.json"), options: .atomic)
        }
        try sample(40_000_000_000)
        var info = stat(); XCTAssertEqual(lstat(root.path, &info), 0)
        app.launchArguments = ["--ui-test-downloads-root", "--ui-test-capacity-reading", "--design-minimum"]
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ROOT"] = root.path
        app.launchEnvironment["STILL_TEST_DOWNLOADS_ID"] = "\(info.st_dev):\(info.st_ino)"
        app.launch()
        let amount = app.staticTexts["startupCapacityAmount"]
        func observes(_ expected: String) -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", expected, expected), object: amount)], timeout: 5) == .completed
        }
        guard observes("40 GB") else { XCTFail("Owned launch capacity must be visible"); return }
        try sample(50_000_000_000)
        app.buttons["Refresh capacity"].click()
        guard observes("50 GB") else { XCTFail("Manual capacity refresh must read independently"); return }
        try sample(60_000_000_000)
        app.buttons["Choose folder…"].click(); app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.typeText(root.path)
        app.typeKey(.return, modifierFlags: []); app.dialogs.buttons["Scan folder"].click()
        waitForOverviewScan(app)
        guard observes("60 GB") else {
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = "capacity-after-scan"; screenshot.lifetime = .keepAlways; add(screenshot)
            XCTFail("Completing a logical scan must refresh startup capacity"); return
        }
        app.typeKey("2", modifierFlags: .command)
        let category = app.checkBoxes["downloadsCategorySelection"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: .command)
        try sample(70_000_000_000); app.buttons["Refresh capacity"].click()
        XCTAssertTrue(observes("70 GB"))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: file), original)
        // Live choices already keep this process alive; capacity adds no keepalive.
        try sample(75_000_000_000)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate(); app.menuBars.menuBarItems["Window"].click(); app.menuItems["Show Still"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(observes("70 GB"), "Recreating the window must retain recent process-owned evidence")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 file selected"].waitForExistence(timeout: 5))
        guard cleanup else { return }
        try sample(80_000_000_000)
        app.buttons["Review cleanup"].click()
        XCTAssertTrue(app.sheets.buttons["Move to Trash"].waitForExistence(timeout: 5))
        app.sheets.buttons["Move to Trash"].click()
        guard app.staticTexts["Succeeded: 1"].waitForExistence(timeout: 20) else { XCTFail("Owned cleanup must complete"); return }
        let returned = app.staticTexts["trashLocation-" + file.lastPathComponent]
        let journal = try SQLiteCleanupJournal(url: state.appendingPathComponent("cleanup.sqlite"))
        let completed = try journal.records().first { $0.originalURL == file && $0.state == .succeeded }
        let returnedURL = completed?.trashURL
        let fixtureDetails = XCTAttachment(string: "Owned original: " + file.path + "\nPublic UI value: " + (returned.value as? String ?? returned.label) + "\nRecorded result: " + (returnedURL?.path ?? "No returned location"))
        fixtureDetails.name = "owned-capacity-cleanup-location"; fixtureDetails.lifetime = .keepAlways; add(fixtureDetails)
        let fixtureCapture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        fixtureCapture.name = "owned-capacity-cleanup-result"; fixtureCapture.lifetime = .keepAlways; add(fixtureCapture)
        guard let returnedURL else { XCTFail("Owned completed record must disclose its returned Trash location"); return }
        let parent = returnedURL.deletingLastPathComponent()
        let knownTrash = parent.lastPathComponent == ".Trash" || (parent.deletingLastPathComponent().lastPathComponent == ".Trashes" && parent.lastPathComponent == String(geteuid()))
        var returnedInfo = stat()
        guard knownTrash, returnedURL.lastPathComponent.contains(file.deletingPathExtension().lastPathComponent),
              lstat(returnedURL.path, &returnedInfo) == 0, returnedInfo.st_mode & S_IFMT == S_IFREG else {
            XCTFail("Only the exact journal-bound UUID fixture in native Trash can be removed"); return
        }
        XCTAssertEqual(try Data(contentsOf: returnedURL), original)
        try manager.removeItem(at: returnedURL)
        let sidebar = app.staticTexts["sidebarCapacityAmount"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "80 GB", "80 GB"), object: sidebar)
        guard XCTWaiter.wait(for: [expected], timeout: 5) == .completed else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "capacity-after-cleanup"; image.lifetime = .keepAlways; add(image)
            XCTFail("Cleanup completion must refresh startup capacity independently of recorded observations"); return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let records = try encoder.encode(journal.records())
        let resultEvidence = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "Observed startup-volume available-capacity change:", "Observed startup-volume available-capacity change:")).firstMatch
        let historicalValue = resultEvidence.value as? String ?? resultEvidence.label
        app.typeKey("1", modifierFlags: .command)
        try sample(90_000_000_000); app.buttons["Refresh capacity"].click()
        XCTAssertTrue(observes("90 GB"))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Cleanup results"].waitForExistence(timeout: 5))
        XCTAssertEqual(resultEvidence.value as? String ?? resultEvidence.label, historicalValue)
        XCTAssertEqual(try encoder.encode(journal.records()), records)
    }

    @MainActor func testCapacityStatesStayStableAtMinimumSize() throws { try capacityStates(minimum: true) }
    @MainActor func testCapacityStatesStayStableAtInitialSize() throws { try capacityStates(minimum: false) }

    @MainActor private func capacityStates(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        func sample(available: Int64?, total: Int64?, metric: String = "important", delay: Int = 0) throws {
            var values: [String: Any] = ["metric": metric, "delayMilliseconds": delay]
            if let available { values["available"] = available }
            if let total { values["total"] = total }
            try JSONSerialization.data(withJSONObject: values).write(to: state.appendingPathComponent("capacity-reading.json"), options: .atomic)
        }
        try sample(available: 40_000_000_000, total: 512_000_000_000)
        app.launchArguments = ["--ui-test-capacity-reading", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        let amount = app.staticTexts["startupCapacityAmount"]
        guard amount.waitForExistence(timeout: 10) else { XCTFail("Launch capacity missing"); return }
        let bounds = app.windows.firstMatch.frame
        let observation = app.staticTexts["capacityObservation"]
        let contentAnchor = app.staticTexts["Scanned locations"]
        XCTAssertTrue(contentAnchor.waitForExistence(timeout: 5))
        let anchor = contentAnchor.frame
        func capture(_ name: String) {
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                image.name = "capacity-" + name + (minimum ? "-minimum-" : "-initial-") + theme
                image.lifetime = .keepAlways; add(image)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                XCTAssertEqual(contentAnchor.frame, anchor)
                XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["refreshCapacity"].frame))
            }
        }
        capture("observed-important")
        try sample(available: 50_000_000_000, total: 512_000_000_000, delay: 8_000)
        app.buttons["Refresh capacity"].click()
        XCTAssertFalse(app.buttons["refreshCapacity"].isEnabled)
        XCTAssertEqual(amount.value as? String ?? amount.label, "40 GB")
        capture("refreshing-retained")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["refreshCapacity"])], timeout: 12), .completed)
        try sample(available: 40_000_000_000, total: nil, metric: "available")
        app.buttons["Refresh capacity"].click()
        let partial = app.staticTexts["Total capacity unavailable"]
        guard partial.waitForExistence(timeout: 5) else { XCTFail("Partial metadata must retain available space"); return }
        XCTAssertTrue(app.staticTexts["sidebarCapacityObservation"].waitForExistence(timeout: 5))
        let sidebar = app.staticTexts["sidebarCapacityAmount"]
        guard sidebar.waitForExistence(timeout: 5) else {
            let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            image.name = "capacity-partial-sidebar-missing"; image.lifetime = .keepAlways; add(image)
            XCTFail("Sidebar must show valid available space without a total"); return
        }
        XCTAssertTrue((sidebar.value as? String ?? sidebar.label).contains("40 GB"))
        capture("partial-fallback")
        try sample(available: nil, total: nil)
        app.buttons["Refresh capacity"].click()
        guard app.buttons["Try again"].waitForExistence(timeout: 5) else { XCTFail("Failure needs retry"); return }
        XCTAssertTrue((observation.value as? String ?? observation.label).hasPrefix("Last observed "))
        XCTAssertEqual(amount.value as? String ?? amount.label, "40 GB")
        capture("stale-failure")
        try sample(available: 60_000_000_000, total: 512_000_000_000)
        app.buttons["Try again"].click()
        XCTAssertTrue(app.buttons["Refresh capacity"].waitForExistence(timeout: 5))
        capture("recovered")
    }

    @MainActor func testUnavailableFirstUseRecoversAtMinimumSize() throws { try unavailableFirstUse(minimum: true) }
    @MainActor func testUnavailableFirstUseRecoversAtInitialSize() throws { try unavailableFirstUse(minimum: false) }
    @MainActor private func unavailableFirstUse(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        let file = state.appendingPathComponent("capacity-reading.json")
        try Data("{}".utf8).write(to: file)
        app.launchArguments = ["--ui-test-capacity-reading", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        guard app.buttons["Try again"].waitForExistence(timeout: 10) else { XCTFail("First-use failure needs retry"); return }
        let bounds = app.windows.firstMatch.frame
        let contentAnchor = app.staticTexts["Scanned locations"]
        XCTAssertTrue(contentAnchor.waitForExistence(timeout: 5))
        let frame = contentAnchor.frame
        func capture(_ stateName: String) {
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                image.name = "capacity-first-use-" + stateName + (minimum ? "-minimum-" : "-initial-") + theme
                image.lifetime = .keepAlways; add(image)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                XCTAssertEqual(contentAnchor.frame, frame)
                XCTAssertTrue(bounds.contains(app.buttons["refreshCapacity"].frame))
            }
        }
        XCTAssertTrue(app.staticTexts["Capacity unavailable"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["startupCapacityAmount"].exists)
        capture("unavailable")
        try Data("{\"available\":40000000000,\"total\":512000000000,\"delayMilliseconds\":8000}".utf8).write(to: file, options: .atomic)
        app.buttons["Try again"].click()
        XCTAssertFalse(app.buttons["refreshCapacity"].isEnabled)
        XCTAssertTrue(app.staticTexts["Checking capacity…"].firstMatch.exists)
        capture("checking")
        guard app.staticTexts["startupCapacityAmount"].waitForExistence(timeout: 12) else { XCTFail("Retry must recover first-use capacity"); return }
        XCTAssertTrue(app.buttons["Refresh capacity"].exists)
        capture("recovered")
        // Exercise the native one-shot deadline, then let its expired metadata reply arrive.
        try Data("{\"available\":70000000000,\"total\":512000000000,\"delayMilliseconds\":15000}".utf8).write(to: file, options: .atomic)
        app.buttons["Refresh capacity"].click()
        guard app.buttons["Try again"].waitForExistence(timeout: 12) else { XCTFail("A stalled capacity read must expire after its deadline"); return }
        XCTAssertEqual(app.staticTexts["startupCapacityAmount"].value as? String ?? app.staticTexts["startupCapacityAmount"].label, "40 GB")
        capture("expired")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND label != %@", "40 GB", "40 GB"), object: app.staticTexts["startupCapacityAmount"])
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 6), .completed, "An expired native reply must not replace retained evidence")
        // Failure retries on real app activation, without changing any alert preferences.
        try Data("{\"available\":60000000000,\"total\":512000000000}".utf8).write(to: file, options: .atomic)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate(); app.activate()
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", "60 GB", "60 GB"), object: app.staticTexts["startupCapacityAmount"])
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 5), .completed)
        capture("foreground-recovered")
    }

    @MainActor func testCapacityGalleryAtMinimumSize() throws { try capacityGallery(minimum: true) }
    @MainActor func testCapacityGalleryAtInitialSize() throws { try capacityGallery(minimum: false) }
    @MainActor private func capacityGallery(minimum: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(); let state = try configureIsolatedJourneyState(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
        app.launchArguments = ["--design-gallery", minimum ? "--design-minimum" : "--design-initial-size"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native design system"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        for theme in ["Light", "Dark"] {
            app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
            for name in ["checking", "refreshing", "important", "fallback", "partial", "stale", "unavailable"] {
                let heading = app.staticTexts["Synthetic capacity " + name + " · Inert example"]
                revealScrollElement(app, control: heading, label: name)
                let container = app.descendants(matching: .any)["capacityGallery-" + name].firstMatch
                let action = container.buttons["refreshCapacity"]
                for _ in 0..<8 where !app.scrollViews.firstMatch.frame.contains(action.frame) {
                    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -60)
                }
                XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(heading.frame))
                XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(action.frame))
                XCTAssertEqual(action.isEnabled, !["checking", "refreshing"].contains(name))
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                image.name = "capacity-gallery-" + name + (minimum ? "-minimum-" : "-initial-") + theme
                image.lifetime = .keepAlways; add(image)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
        }
    }
}
