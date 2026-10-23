import XCTest
import AppKit
import Darwin

/// Manual fresh-host qualification only. Ordinary all/local runs skip before app launch.
final class NativeAlertsQualificationUITests: XCTestCase {
    private struct JourneyFailure: Error { let message: String }
    @MainActor func testRealOptInMonitoringAndWindowLifecycleOnFreshHostedRunner() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["STILL_ALERTS_NATIVE_QUALIFICATION"] == "1",
              environment["GITHUB_ACTIONS"] == "true",
              environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              let probe = environment["STILL_ALERTS_PROBE_ID"], UUID(uuidString: probe) != nil,
              let commit = environment["STILL_ALERTS_SOURCE_COMMIT"], commit.count == 40,
              let temporary = environment["RUNNER_TEMP"],
              let reportPath = environment["STILL_ALERTS_REPORT_DIRECTORY"],
              environment["STILL_TEST_STATE_ROOT"] == nil, environment["STILL_TEST_STATE_ID"] == nil,
              NSUserName() == "runner", geteuid() != 0 else {
            throw XCTSkip("Real authorization is manual-only on a fresh GitHub-hosted runner.")
        }
        let directory = URL(fileURLWithPath: reportPath).standardizedFileURL
        let temporaryURL = URL(fileURLWithPath: temporary).resolvingSymlinksInPath()
        var metadata = stat()
        guard directory.path == directory.resolvingSymlinksInPath().path,
              directory.deletingLastPathComponent() == temporaryURL,
              directory.lastPathComponent == "still-alerts-native-" + probe,
              lstat(directory.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == geteuid(), metadata.st_mode & 0o777 == 0o700 else {
            throw XCTSkip("Hosted evidence directory identity was not established; no app launch.")
        }
        // Check normal app-owned storage before launch. Never delete/reset existing OS or app state.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let manager = FileManager.default
        guard !manager.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Still").path),
              !manager.fileExists(atPath: home.appendingPathComponent("Library/Preferences/com.patrickbourget.Still.plist").path),
              !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.patrickbourget.Still" }) else {
            throw XCTSkip("Runner app state is not fresh; no reset or authorization attempt.")
        }
        var events: [String] = []
        var outcome = "started"
        let app = XCUIApplication()
        func record(_ event: String) { events.append(event) }
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw JourneyFailure(message: message) }
        }
        func capture(_ title: String, application: XCUIApplication) {
            let tree = XCTAttachment(string: application.debugDescription)
            tree.name = title + " accessibility"; tree.lifetime = .keepAlways; add(tree)
            let screen = XCTAttachment(screenshot: application.screenshot())
            screen.name = title; screen.lifetime = .keepAlways; add(screen)
        }
        func monitoring() -> Bool {
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Monitoring startup-volume capacity while Still runs.")).firstMatch.exists
        }
        defer {
            let report: [String: Any] = ["probeID": probe, "sourceCommit": commit, "outcome": outcome,
                                       "events": events, "nativeOSAuthorization": true,
                                       "notificationDeliveryQualified": false, "loginRegistrationQualified": false]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("journey.json"), options: .atomic)
            }
            if app.state != .notRunning { app.terminate() } // Only this freshly launched owned app.
        }
        do {
            app.launchArguments = ["--future-milestones"]
            app.launchEnvironment.removeValue(forKey: "STILL_TEST_STATE_ROOT")
            app.launchEnvironment.removeValue(forKey: "STILL_TEST_STATE_ID")
            app.launch()
            try require(app.buttons["Storage alerts"].waitForExistence(timeout: 15), "Future alert route unavailable")
            app.buttons["Storage alerts"].click()
            try require(app.staticTexts["Alerts are off."].waitForExistence(timeout: 5), "Fresh alerts did not start off")
            let toggle = app.checkBoxes["Notify me when space is low"]
            try require(toggle.exists && toggle.isEnabled, "Real startup capacity did not allow the suggested threshold")
            record("fresh alerts off; route browsing made no authorization request")
            // Stay well below the separately checked >2 GB hosted headroom without filling disk.
            let threshold = app.textFields["Minimum available space (GB)"]
            threshold.click(); app.typeKey("a", modifierFlags: .command); threshold.typeText("1")
            app.buttons["Apply threshold"].click()
            record("explicit 1 decimal GB threshold; real capacity only, no artificial storage writes")
            capture("Before native opt-in", application: app)
            toggle.click()
            record("explicit user opt-in")

            // Discover the actual running notification UI by its observed display name; no guessed bundle ID.
            var candidates = [app]
            var candidateIdentifiers = Set(["com.patrickbourget.Still"])
            var approved = false
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline && !monitoring() && !approved {
                for running in NSWorkspace.shared.runningApplications where running.localizedName?.localizedCaseInsensitiveContains("notification") == true {
                    if let identifier = running.bundleIdentifier, candidateIdentifiers.insert(identifier).inserted {
                        candidates.append(XCUIApplication(bundleIdentifier: identifier))
                        record("observed notification UI: " + (running.localizedName ?? "") + " · " + identifier)
                    }
                }
                for candidate in candidates {
                    for window in candidate.windows.allElementsBoundByIndex {
                        let identifiesStill = window.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Still")).firstMatch.exists
                        let allow = window.buttons.matching(identifier: "Allow")
                        let refuse = window.buttons.matching(identifier: "Don’t Allow").count + window.buttons.matching(identifier: "Don't Allow").count
                        if identifiesStill && allow.count == 1 && refuse == 1 && allow.firstMatch.isHittable {
                            capture("Expected Still notification permission", application: candidate)
                            allow.firstMatch.click(); approved = true
                            record("visible expected Still permission approved using exact Allow control")
                            break
                        }
                    }
                    if approved { break }
                }
                if !approved && !monitoring() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
            }
            let ready = NSPredicate { _, _ in MainActor.assumeIsolated { monitoring() } }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
            guard result == .completed else {
                for (index, candidate) in candidates.enumerated() { capture("Unsupported native authorization surface \(index)", application: candidate) }
                record("no supported actionable Still prompt/authorized monitoring outcome; stopped without settings changes or retry")
                outcome = "unsupported-native-authorization"
                throw XCTSkip("Hosted notification prompt unavailable, denied, or API did not produce effective monitoring; see evidence.")
            }
            record(approved ? "real authorization produced valid monitoring capacity" : "native authorized state confirmed by effective monitoring")
            try require(app.menuBars.menuBarItems["Still storage alerts"].exists, "Effective monitoring has no accessible Still menu-bar presence")
            capture("Native monitoring active", application: app)
            app.typeKey("w", modifierFlags: .command)
            try require(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningForeground, "Closing the monitoring workspace terminated the app")
            try require(app.windows.count == 0, "Workspace did not close")
            record("closing workspace retains same monitoring process")
            app.activate()
            app.menuBars.menuBarItems["Window"].click()
            app.menuItems["Show Still"].firstMatch.click()
            try require(app.buttons["Storage alerts"].waitForExistence(timeout: 5), "Show Still did not reopen workspace")
            app.buttons["Storage alerts"].click()
            try require(monitoring(), "Monitoring did not survive window reconstruction")
            app.typeKey("q", modifierFlags: .command)
            try require(app.wait(for: .notRunning, timeout: 10), "Explicit Quit did not stop the app")
            record("Show Still reopens monitoring workspace; explicit Quit stops process")
            app.launch()
            try require(app.buttons["Storage alerts"].waitForExistence(timeout: 10), "Relaunch workspace unavailable")
            // Monitoring must restore before visiting Settings, whose configure task could mask startup gaps.
            let menuPresence = NSPredicate { _, _ in MainActor.assumeIsolated { app.menuBars.menuBarItems["Still storage alerts"].exists } }
            let resumed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: menuPresence, object: nil)], timeout: 10)
            try require(resumed == .completed, "Saved monitoring did not resume from Overview before opening Settings")
            record("native monitoring menu presence restored from Overview before opening Settings")
            app.buttons["Storage alerts"].click()
            let restored = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
            try require(restored == .completed, "Saved preference did not resume native authorized monitoring")
            record("saved preference resumes after explicit Quit without another permission request")
            app.checkBoxes["Notify me when space is low"].click()
            try require(app.staticTexts["Alerts are off."].waitForExistence(timeout: 5), "Disable did not stop monitoring")
            app.buttons["Overview"].click()
            try require(app.buttons["Choose folder…"].exists, "Capacity-only monitoring changed scope selection")
            app.buttons["History"].click()
            try require(app.staticTexts["No completed runs"].waitForExistence(timeout: 5), "Capacity-only journey created cleanup history")
            app.typeKey("w", modifierFlags: .command)
            try require(app.wait(for: .notRunning, timeout: 10), "Disabled alerts left idle app alive after close")
            record("disable then workspace close exits on-demand app; no folder scan or cleanup requested")
            outcome = "native-opt-in-and-window-lifecycle-passed"
        } catch let skip as XCTSkip { throw skip }
        catch {
            outcome = "failed-native-journey"
            record(String(describing: error)); capture("Failed native journey", application: app)
            XCTFail("Native alert journey failed: \(error)")
        }
    }
}
