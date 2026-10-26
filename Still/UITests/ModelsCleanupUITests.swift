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
        let ollama = home.appendingPathComponent(".still-test-tools/ollama")
        try FileManager.default.createDirectory(at: ollama.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: ollama, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ollama.path)
        return marker
    }

    @MainActor func testModelsAreChosenOneByOneAndPreviewNeitherTrashesNorRunsOllama() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let state = try configureIsolatedState(app)
        let home = try configureCatalogHome(app)
        let marker = try addModels(home)
        defer { app.terminate(); try? FileManager.default.removeItem(at: state); try? FileManager.default.removeItem(at: home) }
        app.launch()

        XCTAssertTrue(app.staticTexts["Storage overview"].waitForExistence(timeout: 10))
        let row = app.buttons["overviewCategory-models"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        // Nothing is preselected; each model is chosen on its own and shows when it was last used.
        for rule in ["planRule-huggingface-models", "planRule-ollama-models"] {
            let header = app.checkBoxes[rule]
            XCTAssertTrue(header.waitForExistence(timeout: 5), rule)
            XCTAssertEqual(header.value as? Int, 0, rule)
        }
        for name in ["org/tiny", "llama3:latest"] {
            let item = app.checkBoxes["planItem-" + name]
            if !item.waitForExistence(timeout: 2) { app.disclosureTriangles.allElementsBoundByIndex.forEach { $0.click() } }
            XCTAssertTrue(item.waitForExistence(timeout: 5), name)
            XCTAssertEqual(item.value as? Int, 0, name)
            item.click()
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Last used'")).firstMatch.exists)
        XCTAssertEqual(app.checkBoxes["previewOnlyToggle"].value as? Int, 1)
        app.buttons["Review cleanup"].click()

        XCTAssertTrue(app.staticTexts["Move to Trash: Hugging Face models"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Clear Ollama models"].exists)
        app.buttons["Run preview"].click()

        XCTAssertTrue(app.staticTexts["catalogPreviewNotice"].waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cache/huggingface/hub/models--org--tiny").path))
    }
}
