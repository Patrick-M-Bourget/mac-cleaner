import XCTest
import Darwin
final class StorageAlertsUITests: XCTestCase {
    @MainActor func testOpenedAlertPreservesContextAndOffersOnlyExplicitScanAcrossThemesAndSizes() throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let token = UUID().uuidString
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + token)
        try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(token.utf8).write(to: root.appendingPathComponent(".still-owned-test-state"))
        defer { try? manager.removeItem(at: root) }
        var identity = stat(); XCTAssertEqual(lstat(root.path, &identity), 0)
        for minimum in [false, true] {
            for fixture in ["dated", "legacy", "malformed"] {
                let app = XCUIApplication()
                app.launchEnvironment["STILL_TEST_STATE_ROOT"] = root.path
                app.launchEnvironment["STILL_TEST_STATE_ID"] = "\(identity.st_dev):\(identity.st_ino)"
                app.launchEnvironment["STILL_TEST_ALERT_OPEN"] = fixture
                app.launchArguments = ["--future-milestones", minimum ? "--design-minimum" : "--design-initial-size"]
                app.launch()
                let status = app.staticTexts["openedStorageAlert"]
                XCTAssertTrue(status.waitForExistence(timeout: 10))
                let displayedTime = status.value as? String ?? status.label
                if fixture == "dated" { XCTAssertTrue(displayedTime.contains("1970")) }
                else { XCTAssertEqual(displayedTime, "Alert check time unavailable") }
                XCTAssertFalse(app.buttons["Stop scan"].exists)
                XCTAssertFalse(app.buttons["Explore storage"].exists)
                let bounds = app.windows.firstMatch.frame
                for theme in ["Light", "Dark"] {
                    app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                    let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    capture.name = "alert-open-" + fixture + "-" + (minimum ? "minimum-" : "initial-") + theme
                    capture.lifetime = .keepAlways; add(capture)
                    XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                }
                app.buttons["Choose a folder to scan…"].click()
                XCTAssertTrue(app.dialogs.buttons["Scan folder"].waitForExistence(timeout: 5))
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(status.exists)
                XCTAssertFalse(app.buttons["Explore storage"].exists)
                app.buttons["Dismiss alert"].click()
                XCTAssertFalse(status.exists)
                XCTAssertTrue(app.buttons["Choose folder…"].exists)
                app.terminate()
            }
        }
    }

    @MainActor func testAlertsAreHiddenByDefaultAndFutureSettingsDoNotRequestPermission() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Storage alerts"].exists)
        app.terminate()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Storage alerts"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Storage alerts"].click()
        XCTAssertTrue(app.staticTexts["Alerts are off."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Minimum available space (GB)"].value as? String, "40")
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
    }

    @MainActor func testOnDemandWindowCloseTerminatesAndLoginControlsAreReadOnlyUntilChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        XCTAssertTrue(app.buttons["Storage alerts"].waitForExistence(timeout: 10))
        app.buttons["Storage alerts"].click()
        XCTAssertTrue(app.checkBoxes["Start Still at Login"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["loginRegistrationStatus"].exists)
        XCTAssertTrue(app.staticTexts["Alerts are off."].exists)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }

    @MainActor func testDisposableAlertOptInExplainsRefusalWithoutChangingOSAuthorization() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTestState-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try String(root.lastPathComponent.dropFirst("StillTestState-".count)).write(to: root.appendingPathComponent(".still-owned-test-state"), atomically: false, encoding: .utf8)
        var identity = stat()
        guard lstat(root.path, &identity) == 0 else { throw CocoaError(.fileReadUnknown) }
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.launchArguments = ["--future-milestones"]
        app.launchEnvironment = ["STILL_TEST_STATE_ROOT": root.path, "STILL_TEST_STATE_ID": "\(identity.st_dev):\(identity.st_ino)"]
        app.launch()
        XCTAssertTrue(app.buttons["Storage alerts"].waitForExistence(timeout: 10))
        app.buttons["Storage alerts"].click()
        XCTAssertTrue(app.staticTexts["Alerts are off."].waitForExistence(timeout: 5))
        let threshold = app.textFields["Minimum available space (GB)"]
        threshold.click(); app.typeKey("a", modifierFlags: .command); threshold.typeText("1")
        app.buttons["Apply threshold"].click()
        let toggle = app.checkBoxes["Notify me when space is low"]
        XCTAssertTrue(toggle.isEnabled && toggle.isHittable)
        toggle.click()
        let refusal = app.staticTexts["Disposable tests do not change notification settings."]
        let responded = refusal.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Disposable alert opt-in response accessibility"; tree.lifetime = .keepAlways; add(tree)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Disposable alert opt-in response"; screen.lifetime = .keepAlways; add(screen)
        XCTAssertTrue(responded, "Opt-in action must reach the controller and update public status before any native permission operation is possible.")
        XCTAssertEqual(toggle.value as? Int, 0)
        XCTAssertTrue(app.checkBoxes["Start Still at Login"].exists)
    }

    @MainActor func testFutureHomebrewPreviewIsSecondaryAndClearlySynthetic() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        revealOverviewTool(app, label: "Review Homebrew opportunities")
        XCTAssertTrue(app.buttons["Review Homebrew opportunities"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Review Homebrew opportunities"].click()
        XCTAssertTrue(app.buttons["Choose Homebrew executable…"].exists)
        XCTAssertFalse(app.buttons["Inspect selected Homebrew"].isEnabled)
        app.buttons["Show disposable preview example"].click()
        XCTAssertTrue(app.staticTexts["Synthetic preview evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["/disposable/cache/archive (12.3MB)"].exists)
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Back to Overview"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
    }

    @MainActor func testSelectedHomebrewCacheInventoryIsReadOnlyAcrossThemesAndSizes() async throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("StillHomebrewUI-" + UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let cache = root.appendingPathComponent("cache")
        try manager.createDirectory(at: cache.appendingPathComponent("downloads"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        // Provisioning belongs to the disposable test runner, never the app.
        for path in ["bin/brew", "Library/Homebrew/brew.sh", "Library/Homebrew/help.sh", "Library/Homebrew/formula_path.sh"] {
            let url = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/Homebrew/brew/aa278895809b4c079e560fb4fb9bf17e48cf65f1/" + path))
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertLessThan(data.count, 256_000)
            let target = source.appendingPathComponent(path)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        let sentinel = cache.appendingPathComponent("obsolete.incomplete")
        let download = cache.appendingPathComponent("downloads/current.tar.gz")
        try Data(repeating: 0x61, count: 27).write(to: sentinel)
        try Data(repeating: 0x62, count: 101).write(to: download)
        for minimum in [false, true] {
            let app = XCUIApplication()
            let state = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
            app.launchArguments = ["--future-milestones", "--homebrew-inventory-fixture", minimum ? "--design-minimum" : "--design-initial-size"]
            var information = stat()
            XCTAssertEqual(lstat(root.path, &information), 0)
            app.launchEnvironment["STILL_TEST_HOMEBREW_ROOT"] = root.path
            app.launchEnvironment["STILL_TEST_HOMEBREW_ROOT_ID"] = "\(information.st_dev):\(information.st_ino)"
            app.launch()
            revealOverviewTool(app, label: "Review Homebrew opportunities")
            XCTAssertTrue(app.buttons["Review Homebrew opportunities"].waitForExistence(timeout: 10))
            let bounds = app.windows.firstMatch.frame
            app.buttons["Review Homebrew opportunities"].click()
            XCTAssertTrue(app.buttons["Inspect selected Homebrew"].isEnabled, app.debugDescription)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                attachment.name = "homebrew-selected-" + (minimum ? "minimum-" : "initial-") + theme
                attachment.lifetime = .keepAlways; add(attachment)
            }
            app.buttons["Inspect selected Homebrew"].click()
            let status = app.staticTexts["homebrewPreviewStatus"]
            let completed = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Read-only cache inventory complete", "Read-only cache inventory complete")
            let completion = XCTNSPredicateExpectation(predicate: completed, object: status)
            let result = await XCTWaiter.fulfillment(of: [completion], timeout: 20)
            XCTAssertEqual(result, .completed)
            guard result == .completed else { return }
            for _ in 0..<5 {
                let evidence = app.staticTexts["Observed regular files: 2"]
                if evidence.exists && app.scrollViews.firstMatch.frame.contains(evidence.frame) { break }
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -150)
            }
            XCTAssertTrue(app.staticTexts["Observed regular files: 2"].exists)
            XCTAssertTrue(app.staticTexts["Logical bytes: 128"].exists)
            XCTAssertTrue(app.staticTexts["Reclaimable space: Unknown"].exists)
            XCTAssertFalse(app.buttons["Clean Homebrew cache"].exists)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                attachment.name = "homebrew-inventory-" + (minimum ? "minimum-" : "initial-") + theme
                attachment.lifetime = .keepAlways; add(attachment)
            }
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(try Data(contentsOf: sentinel), Data(repeating: 0x61, count: 27))
            XCTAssertEqual(try Data(contentsOf: download), Data(repeating: 0x62, count: 101))
            XCTAssertEqual(Set(try manager.contentsOfDirectory(atPath: cache.path)), Set(["obsolete.incomplete", "downloads"]))
            app.terminate()
        }
    }

    @MainActor func testFuturePipInventoryShowsRecordedQualificationWithoutRunningPersonalTools() {
        let app = XCUIApplication()
        app.launchArguments = ["--future-milestones"]
        app.launch()
        revealOverviewTool(app, label: "Review pip cache opportunities")
        XCTAssertTrue(app.buttons["Review pip cache opportunities"].waitForExistence(timeout: 10))
        let bounds = app.windows.firstMatch.frame
        app.buttons["Review pip cache opportunities"].click()
        XCTAssertTrue(app.buttons["Choose Python interpreter…"].exists)
        XCTAssertFalse(app.buttons["Inspect selected pip cache"].isEnabled)
        app.buttons["Show recorded disposable qualification"].click()
        XCTAssertTrue(app.staticTexts["Recorded disposable evidence"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.frame, bounds)
        app.buttons["Back to Overview"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].exists)
    }

    @MainActor func testSelectedPipCacheInventoryIsReadOnlyAcrossThemesAndSizes() throws {
        continueAfterFailure = false
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("StillPipUI-" + UUID().uuidString)
        let wheel = root.appendingPathComponent("wheels/a/package-1.0-py3-none-any.whl")
        try manager.createDirectory(at: wheel.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let seed = Data("disposable-inventory-sentinel".utf8)
        try seed.write(to: wheel)
        for minimum in [false, true] {
            let app = XCUIApplication()
            let state = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
            app.launchArguments = ["--future-milestones", "--pip-inventory-fixture", minimum ? "--design-minimum" : "--design-initial-size"]
            var information = stat()
            XCTAssertEqual(lstat(root.path, &information), 0)
            app.launchEnvironment["STILL_TEST_PIP_CACHE"] = root.path
            app.launchEnvironment["STILL_TEST_PIP_CACHE_ID"] = "\(information.st_dev):\(information.st_ino)"
            app.launch()
            revealOverviewTool(app, label: "Review pip cache opportunities")
            XCTAssertTrue(app.buttons["Review pip cache opportunities"].waitForExistence(timeout: 10))
            let bounds = app.windows.firstMatch.frame
            app.buttons["Review pip cache opportunities"].click()
            XCTAssertTrue(app.buttons["Inspect selected pip cache"].isEnabled,
                          "Fixture preload failed; canonical root: \(root.resolvingSymlinksInPath().path); UI: \(app.debugDescription)")
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let selection = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                selection.name = "pip-selected-" + (minimum ? "minimum-" : "initial-") + theme
                selection.lifetime = .keepAlways; add(selection)
            }
            app.buttons["Inspect selected pip cache"].click()
            let status = app.staticTexts["pipInventoryStatus"]
            let completed = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Read-only inventory complete", "Read-only inventory complete")
            expectation(for: completed, evaluatedWith: status)
            waitForExpectations(timeout: 45)
            for _ in 0..<4 {
                let evidence = app.staticTexts["Listed wheels: 1"]
                if evidence.exists && app.scrollViews.firstMatch.frame.contains(evidence.frame) { break }
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -180)
            }
            XCTAssertTrue(app.staticTexts["Listed wheels: 1"].exists)
            XCTAssertTrue(app.staticTexts["Wheel logical bytes: 29"].exists)
            XCTAssertFalse(app.buttons["Clean pip cache"].exists)
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                let inventory = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                inventory.name = "pip-inventory-" + (minimum ? "minimum-" : "initial-") + theme
                inventory.lifetime = .keepAlways; add(inventory)
            }
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            XCTAssertEqual(try Data(contentsOf: wheel), seed)
            XCTAssertEqual(try manager.contentsOfDirectory(atPath: root.path), ["wheels"])
            app.terminate()
        }
    }

    @MainActor func testFutureDockerReportKeepsHostCapacityAndPersistentDataDistinct() throws {
        for size in ["--design-initial-size", "--design-minimum"] {
            let app = XCUIApplication()
            let state = try configureIsolatedJourneyState(app)
            defer { app.terminate(); try? FileManager.default.removeItem(at: state) }
            app.launchArguments = ["--future-milestones", size]
            app.launch()
            revealOverviewTool(app, label: "Review Docker storage")
            XCTAssertTrue(app.buttons["Review Docker storage"].waitForExistence(timeout: 10))
            let bounds = app.windows.firstMatch.frame
            app.buttons["Review Docker storage"].click()
            for theme in ["Light", "Dark"] {
                app.popUpButtons["Appearance"].click(); app.menuItems[theme].click()
                XCTAssertTrue(app.textFields["Local Unix socket path"].exists)
                XCTAssertFalse(app.buttons["Inspect selected Docker"].isEnabled)
                let empty = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                empty.name = "docker-explicit-endpoint-" + size + "-" + theme
                empty.lifetime = .keepAlways; add(empty)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
                XCTAssertTrue(app.staticTexts["VM virtual capacity: Unknown"].exists)
                XCTAssertTrue(app.staticTexts["Host allocated bytes: Unknown"].exists)
                let example = app.buttons["Show synthetic Docker report"]
                XCTAssertTrue(example.waitForExistence(timeout: 5)); example.click()
                XCTAssertTrue(app.staticTexts["Synthetic daemon report"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Local Volumes · Persistent application data"].exists)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
                let report = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                report.name = "docker-persistent-data-" + size + "-" + theme
                report.lifetime = .keepAlways; add(report)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 1400)
                let endpoint = app.textFields["Local Unix socket path"]
                endpoint.click(); endpoint.typeKey("a", modifierFlags: .command)
                endpoint.typeText("/disposable/" + theme + "/daemon.sock")
                XCTAssertTrue(app.staticTexts["Socket changed. Inspect explicitly to read this endpoint. No command was run."].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["Synthetic daemon report"].exists)
                XCTAssertFalse(app.staticTexts["Local Volumes · Persistent application data"].exists)
                XCTAssertTrue(app.staticTexts["Host allocated bytes: Unknown"].exists)
                XCTAssertTrue(app.staticTexts["VM virtual capacity: Unknown"].exists)
                XCTAssertFalse(app.buttons["Inspect selected Docker"].isEnabled)
                XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            }
            app.buttons["Back to Overview"].click()
            XCTAssertTrue(app.buttons["Choose folder…"].exists)
            XCTAssertEqual(app.windows.firstMatch.frame, bounds)
            app.terminate()
        }
    }
}
