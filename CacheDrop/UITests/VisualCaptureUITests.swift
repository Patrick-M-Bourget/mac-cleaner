import XCTest
import AppKit

/// Opt-in window captures, separate from assertions in the journey suite. Images stay in the runner's temp folder.
final class VisualCaptureUITests: XCTestCase {
    @MainActor func testCaptureWindow() throws {
        guard ProcessInfo.processInfo.environment["CACHEDROP_VISUAL_CAPTURE"] == "1" else {
            throw XCTSkip("Run scripts/visual-check.py capture when the Mac is free")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        defer { app.terminate() }
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
            for page in ["overview", "plan"] {
                if page == "plan" {
                    app.typeKey("3", modifierFlags: .command)
                    XCTAssertTrue(app.staticTexts["Ready to clean"].waitForExistence(timeout: 10))
                }
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
}
