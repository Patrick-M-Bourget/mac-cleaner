import XCTest

final class ModelsCleanupUITests: XCTestCase {
    /// A Hugging Face model and an Ollama model in the fixture home, plus a stand-in `ollama` that would leave a marker if it ever ran.
    @MainActor private func addModels(_ home: URL) throws -> URL {
        let weights = home.appendingPathComponent(".cache/huggingface/hub/models--org--tiny/blobs/aaa")
        try FileManager.default.createDirectory(at: weights.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: 80_000).write(to: weights)
        let manifest = home.appendingPathComponent(".ollama/models/manifests/registry.ollama.ai/library/llama3/latest")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":2,"config":{"digest":"sha256:c1","size":10},"layers":[{"digest":"sha256:w1","size":90000}]}"#.utf8).write(to: manifest)
        let marker = home.appendingPathComponent("ollama-ran")
        let ollama = home.appendingPathComponent(".cachedrop-test-tools/ollama")
        try writeStandInTool("#!/bin/sh\ntouch '\(marker.path)'\n", to: ollama)
        return marker
    }

    @MainActor func testModelsAreChosenOneByOneAndADryRunNeitherTrashesNorRunsOllama() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addModels(home)
        turnOnDryRun(app)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        waitForCatalogScan(app)
        let row = app.buttons["overviewCategory-models"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealAndClick(row, in: app)

        // Nothing is preselected; each model is chosen on its own and shows when it was last used.
        for rule in ["planRule-huggingface-models", "planRule-ollama-models"] {
            let header = app.checkBoxes[rule]
            XCTAssertTrue(header.waitForExistence(timeout: 5), rule)
            XCTAssertEqual(header.value as? Int, 0, rule)
        }
        for (rule, name) in [("huggingface-models", "org/tiny"), ("ollama-models", "llama3:latest")] {
            // Items are drawn lazily: bring the rule's list into view first.
            reveal(app.checkBoxes["planRule-" + rule], in: app, nearTop: true)
            let item = app.checkBoxes["planItem-" + name]
            if !item.waitForExistence(timeout: 2) { expandDisclosures(in: app) }
            XCTAssertTrue(item.waitForExistence(timeout: 5), name)
            XCTAssertEqual(item.value as? Int, 0, name)
            // #367: clicking the item's row ticks it, as its checkbox does; Finder is its own Reveal link.
            revealAndClick(app.buttons["Select " + name], in: app)
            XCTAssertEqual(item.value as? Int, 1, name)
            XCTAssertTrue(app.links["planItemReveal-" + name].exists, name)
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Select org/tiny' AND value CONTAINS 'Last used'")).firstMatch.exists)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(reviewLine(app, "movedToTrash", "models").waitForExistence(timeout: 5))
        XCTAssertTrue(reviewLine(app, "commandsRun", "models").exists)
        cleanUpFromReview(app)

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cache/huggingface/hub/models--org--tiny").path))
    }
}
