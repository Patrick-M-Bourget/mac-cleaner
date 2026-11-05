import XCTest
import AppKit

/// Opt-in window captures, separate from assertions in the journey suite. Images stay in the runner's temp folder.
/// `scripts/visual-check.py capture --scenario NAME` names the scenario (#728): the fixtures it adds and the pages it captures,
/// each page reached from the one before it, in light then dark.
final class VisualCaptureUITests: XCTestCase {
    @MainActor func testCaptureWindow() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CACHEDROP_VISUAL_CAPTURE"] == "1" else {
            throw XCTSkip("Run scripts/visual-check.py capture when the Mac is free")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate() }
        let pages: [String]
        switch environment["CACHEDROP_VISUAL_SCENARIO"] ?? "overview" {
        case "overview":
            pages = ["overview", "plan"]
        case "audio-software":
            try addAudioSoftware(in: home)
            pages = ["sounds", "drivers"]
        case "photo-video":
            try addAdobeCaches(in: home)
            try addFinalCutLibraries(in: home)
            pages = ["overview", "smart-clean", "plan-photo-video", "plan-final-cut"]
        case let unknown:
            XCTFail("No capture scenario named \(unknown)")
            return
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropVisual-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        app.launchEnvironment["CACHEDROP_TEST_VISUAL_WINDOW"] = "1"
        app.launchEnvironment["CACHEDROP_TEST_CAPACITY"] = "40000000000,100000000000"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Keep modification-date labels stable, too.
        for path in ["Downloads/Setup.dmg", ".npm/_cacache/content-v2/sha512/ab/blob"] {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: home.appendingPathComponent(path).path)
        }
        var manifest: [String: Any] = [:]
        for appearance in ["Light", "Dark"] {
            try Data(appearance.utf8).write(to: state.appendingPathComponent("appearance-preference.txt"))
            app.launch()
            waitForCatalogScan(app)
            let window = app.windows["CacheDrop"]
            XCTAssertEqual(window.frame.width, 1000, accuracy: 2)
            XCTAssertEqual(window.frame.height, 760, accuracy: 2)
            XCTAssertTrue(CGDisplayBounds(CGMainDisplayID()).contains(window.frame), "The whole fixture window must fit on the primary display")
            for page in pages {
                show(page, in: app)
                // Park outside the window and allow an existing hover tooltip to disappear.
                CGWarpMouseCursorPosition(CGPoint(x: window.frame.minX - 20, y: window.frame.minY + 100))
                Thread.sleep(forTimeInterval: 1)
                let bounds = window.frame
                // Coordinates are window-local points, with the origin at the top left.
                var masks: [[String: Any]] = [["x": 0, "y": 0, "width": bounds.width, "height": 30, "reason": "native title bar and top corners"],
                    ["x": 0, "y": bounds.height - 12, "width": 12, "height": 12, "reason": "native bottom-left corner"],
                    ["x": bounds.width - 12, "y": bounds.height - 12, "width": 12, "height": 12, "reason": "native bottom-right corner"]]
                for text in window.staticTexts.allElementsBoundByIndex {
                    let label = (text.value as? String) ?? text.label
                    if label.range(of: "^(Updated|Scanned) [0-9]", options: .regularExpression) != nil {
                        let rect = text.frame.intersection(bounds)
                        if !rect.isNull {
                            masks.append(["x": rect.minX - bounds.minX, "y": rect.minY - bounds.minY, "width": rect.width, "height": rect.height, "reason": label.hasPrefix("Updated ") ? "capacity timestamp" : "scan timestamp"])
                        }
                    }
                }
                let name = "\(page)-\(appearance.lowercased()).png"
                try window.screenshot().pngRepresentation.write(to: output.appendingPathComponent(name))
                manifest[name] = ["width": bounds.width, "height": bounds.height, "masks": masks]
            }
            app.terminate()
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("manifest.json"))
        print("VISUAL_CAPTURE_DIR=\(output.path)")
    }

    /// Brings a scenario's page on screen from the one captured before it. Overview is where the scan leaves the window.
    /// A group is scrolled to the top of the page with `reveal`, which scrolls the page's scroll view (`app.scrollViews`).
    @MainActor private func show(_ page: String, in app: XCUIApplication) {
        switch page {
        case "plan":
            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Ready to clean"].waitForExistence(timeout: 10))
        case "sounds":
            openApplications(app, ["audio software"])
            let sounds = app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH 'Show sounds · '")).firstMatch
            openDisclosure(sounds, in: app)
            reveal(sounds, in: app, nearTop: true)
        case "drivers":
            openApplicationsSections(app, ["drivers"])
            let drivers = app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH 'Choose drivers · '")).firstMatch
            XCTAssertTrue(drivers.waitForExistence(timeout: 5), "Audio software lists its drivers")
            reveal(drivers, in: app, nearTop: true)
        case "smart-clean":
            // Smart clean with its Photo and video row; the page lists no items (#779).
            app.typeKey("2", modifierFlags: .command)
            let category = app.checkBoxes["smartCleanCategory-photo-video"]
            XCTAssertTrue(category.waitForExistence(timeout: 10), "Smart clean lists Photo and video")
            reveal(category, in: app, nearTop: true)
        case "plan-photo-video":
            // Overview's row opens the Cleanup plan with Photo and video open (#733). Its own page name: a second `case "plan"`
            // never ran, so the first capture reached the plan with ⌘3, where categories start collapsed (Decision 48, #752).
            app.typeKey("1", modifierFlags: .command)
            revealAndClick(app.buttons["overviewCategory-photo-video"], in: app)
            let category = app.checkBoxes["planCategory-photo-video"]
            XCTAssertTrue(category.waitForExistence(timeout: 10), "The Cleanup plan lists Photo and video")
            XCTAssertTrue(app.checkBoxes["planRule-adobe-media-cache"].waitForExistence(timeout: 5), "Photo and video is open")
            reveal(category, in: app, nearTop: true)
        case "plan-final-cut":
            // Photo and video is still open from Overview's row (#752).
            let render = app.checkBoxes["planRule-final-cut-render-files"]
            XCTAssertTrue(render.waitForExistence(timeout: 10), "Photo and video lists Final Cut Pro's render files")
            reveal(render, in: app, nearTop: true)
        default:
            break
        }
    }}
