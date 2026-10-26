import Foundation
import Testing
import StillCore

/// A temp home; tests never read or write the real home, models or app data.
private func modelsHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillModels-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private let day: TimeInterval = 86_400
/// Writes `size` bytes at `relative`, last accessed, changed and created `age` ago.
@discardableResult
private func file(_ home: URL, _ relative: String, size: Int = 10, age: TimeInterval = 30 * day, contents: Data? = nil) throws -> URL {
    let url = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (contents ?? Data(repeating: 1, count: size)).write(to: url)
    try setTimes(url, age)
    return url
}
private func setTimes(_ url: URL, _ age: TimeInterval) throws {
    let date = Date().addingTimeInterval(-age)
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
}
/// Ages every entry under `root` (deepest first, so a folder's own times are set last).
private func ageTree(_ root: URL, _ age: TimeInterval) throws {
    let entries = (FileManager.default.subpaths(atPath: root.path) ?? []).sorted { $0.count > $1.count }
    for entry in entries { try setTimes(root.appendingPathComponent(entry), age) }
    try setTimes(root, age)
}

private let hub = ".cache/huggingface/hub"

@Test func eachHuggingFaceModelIsATrashCandidateWithItsSizeAndLastUse() throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try file(home, hub + "/models--meta-llama--Llama-3-8B/blobs/aaa", size: 4000, age: 200 * day)
    try file(home, hub + "/models--meta-llama--Llama-3-8B/refs/main", size: 40, age: 200 * day)
    // Read 3 days ago, though the folder itself is old.
    let weights = try file(home, hub + "/models--openai--whisper-small/blobs/bbb", size: 2000)
    try ageTree(home.appendingPathComponent(hub + "/models--meta-llama--Llama-3-8B"), 200 * day)
    try ageTree(home.appendingPathComponent(hub + "/models--openai--whisper-small"), 200 * day)
    try setTimes(weights, 3 * day)
    // Datasets, lock files and the cache's own files are not models.
    try file(home, hub + "/datasets--squad/blobs/ccc", size: 3000)
    try file(home, hub + "/.locks/models--meta-llama--Llama-3-8B/aaa.lock")
    try file(home, hub + "/version.txt")

    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { _ in nil })
    #expect(candidates.allSatisfy { $0.ruleID == "huggingface-models" && $0.action == .trash && $0.isDirectory })
    let found = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url.lastPathComponent, $0) })
    #expect(Set(found.keys) == ["models--meta-llama--Llama-3-8B", "models--openai--whisper-small"])
    let llama = try #require(found["models--meta-llama--Llama-3-8B"])
    #expect(llama.logicalBytes == 4040)
    #expect(llama.sizeComplete)
    #expect(llama.itemName == "meta-llama/Llama-3-8B")
    let llamaUsed = try #require(llama.lastUsed)
    #expect(abs(llamaUsed.timeIntervalSinceNow + 200 * day) < 5)
    let whisperUsed = try #require(found["models--openai--whisper-small"]?.lastUsed)
    #expect(abs(whisperUsed.timeIntervalSinceNow + 3 * day) < 5)
    let rule = try #require(Catalog(rules: fixtureRules).rule("huggingface-models"))
    #expect(rule.category == .models)
    #expect(rule.regen == .model)
}

/// Stands in for the Finder Trash so tests never touch the user's real Trash.
private struct FixtureTrash: TrashMoving {
    let folder: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
private struct Running: RunningAppChecking {
    var names: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { names.contains(owner.name) }
}
private func run(_ home: URL, _ candidates: [Candidate], running: Running = Running(), previewOnly: Bool = false) async throws -> CatalogExecutionResult {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: running)
    let executor = CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: FixtureTrash(folder: home.appendingPathComponent("FixtureTrash")))
    return await executor.execute(CatalogApproval(candidates: candidates, previewOnly: previewOnly))
}

@Test func aChosenHuggingFaceModelGoesToTrashAndTheOthersStay() async throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try file(home, hub + "/models--org--chosen/blobs/aaa", size: 3000)
    let kept = try file(home, hub + "/models--org--kept/blobs/bbb", size: 3000)
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { _ in nil })
    let chosen = try #require(candidates.first { $0.itemName == "org/chosen" })
    let result = try await run(home, [chosen])
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded)
    #expect(record.action == "moveToTrash")
    #expect(record.trashURL?.lastPathComponent == "models--org--chosen")
    #expect(result.movedToTrashBytes == chosen.allocatedBytes)
    #expect(result.measuredFreedBytes == 0)
    #expect(!FileManager.default.fileExists(atPath: chosen.url.path))
    #expect(FileManager.default.fileExists(atPath: kept.path))
}

// MARK: Ollama

private let manifests = ".ollama/models/manifests"
/// Writes an Ollama manifest naming `layers` (digest suffix → size) and their blobs. Ollama itself is never run.
@discardableResult
private func ollamaModel(_ home: URL, _ path: String, layers: [(String, Int)], age: TimeInterval = 30 * day) throws -> URL {
    let entries = layers.map { "{\"mediaType\":\"application/vnd.ollama.image.model\",\"digest\":\"sha256:\($0.0)\",\"size\":\($0.1)}" }
    let config = "cfg" + path.filter { $0.isLetter || $0.isNumber }
    let json = "{\"schemaVersion\":2,\"config\":{\"digest\":\"sha256:\(config)\",\"size\":10},\"layers\":[\(entries.joined(separator: ","))]}"
    for (digest, size) in layers { try file(home, ".ollama/models/blobs/sha256-\(digest)", size: size, age: age) }
    try file(home, ".ollama/models/blobs/sha256-\(config)", size: 10, age: age)
    return try file(home, manifests + "/" + path, age: age, contents: Data(json.utf8))
}
/// A stand-in `ollama` in the fixture that records its arguments; the real one is never run by tests.
private func fakeOllama(_ home: URL, _ script: String = "echo \"$@\" >> \"$(dirname \"$0\")/calls\"") throws -> URL {
    let tool = home.appendingPathComponent("tools/ollama")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ("#!/bin/sh\n" + script + "\n").write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}

@Test func ollamaModelsAreListedFromTheirManifestsWithTheSpaceOnlyTheyUse() throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let ollama = try fakeOllama(home)
    try ollamaModel(home, "registry.ollama.ai/library/llama3/latest", layers: [("weights1", 4000), ("shared", 500)], age: 100 * day)
    try ollamaModel(home, "registry.ollama.ai/library/llama3/8b", layers: [("weights1", 4000), ("shared", 500)])
    try ollamaModel(home, "registry.ollama.ai/someone/tuned/v2", layers: [("weights2", 3000), ("shared", 500)], age: 2 * day)
    try ollamaModel(home, "hf.co/org/repo/Q4_K_M", layers: [("weights3", 1000)])
    // Unreadable or unsafe manifests are never offered.
    try file(home, manifests + "/registry.ollama.ai/library/broken/latest", contents: Data("not json".utf8))
    try ollamaModel(home, "registry.ollama.ai/library/-rf/latest", layers: [("weights4", 100)])

    let catalog = Catalog(rules: fixtureRules)
    #expect(catalog.discover(fixture: home, locateTool: { _ in nil }).isEmpty)
    let candidates = catalog.discover(fixture: home, locateTool: { _ in ollama })
    #expect(candidates.allSatisfy { $0.ruleID == "ollama-models" && $0.action == .tool && !$0.isDirectory && $0.toolURL == ollama })
    let found = Dictionary(uniqueKeysWithValues: candidates.map { ($0.itemName ?? "", $0) })
    #expect(Set(found.keys) == ["llama3:latest", "llama3:8b", "someone/tuned:v2", "hf.co/org/repo:Q4_K_M"])
    // Two tags of one model share every blob: removing either frees only its own config.
    #expect(found["llama3:latest"]?.logicalBytes == 10)
    #expect(found["someone/tuned:v2"]?.logicalBytes == 3010)
    #expect(found["hf.co/org/repo:Q4_K_M"]?.logicalBytes == 1010)
    #expect(candidates.allSatisfy { $0.sizeIsEstimate && $0.allocatedBytes == nil })
    let used = try #require(found["someone/tuned:v2"]?.lastUsed)
    #expect(abs(used.timeIntervalSinceNow + 2 * day) < 5)
    let rule = try #require(catalog.rule("ollama-models"))
    #expect(rule.category == .models)
    #expect(rule.tool?.commandLine == "ollama rm <model>")
}

@Test func aChosenOllamaModelIsRemovedWithOllamaRmByName() async throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let ollama = try fakeOllama(home)
    try ollamaModel(home, "registry.ollama.ai/library/llama3/latest", layers: [("weights1", 4000)])
    try ollamaModel(home, "registry.ollama.ai/someone/tuned/v2", layers: [("weights2", 3000)])
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { _ in ollama })
    let chosen = try #require(candidates.first { $0.itemName == "someone/tuned:v2" })

    let preview = try await run(home, [chosen], previewOnly: true)
    #expect(preview.records.first?.message.hasPrefix("Preview only: would run ollama rm someone/tuned:v2") == true)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("tools/calls").path))

    let result = try await run(home, [chosen])
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded)
    #expect(record.action == "tool")
    #expect(record.message == "Ran ollama rm someone/tuned:v2")
    #expect(try String(contentsOf: home.appendingPathComponent("tools/calls"), encoding: .utf8) == "rm someone/tuned:v2\n")
}

@Test func aFailedOllamaRmShowsItsOutputAndChangesNothing() async throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let ollama = try fakeOllama(home, "echo 'Error: could not connect to ollama app, is it running?'; exit 1")
    let manifest = try ollamaModel(home, "registry.ollama.ai/library/llama3/latest", layers: [("weights1", 4000)])
    let chosen = try #require(Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { _ in ollama }).first)
    let record = try #require(try await run(home, [chosen]).records.first)
    #expect(record.state == .failed, "\(record.message)")
    #expect(record.toolOutput == "Error: could not connect to ollama app, is it running?")
    #expect(FileManager.default.fileExists(atPath: manifest.path))
}

// MARK: VM and disk images

private let vmBundles = "Library/Application Support/Claude/vm_bundles"
private let megabyte = 1_000_000
/// A sparse file of `size` logical bytes, so large images cost no real disk space in tests.
@discardableResult
private func sparse(_ home: URL, _ relative: String, size: Int, age: TimeInterval = 30 * day) throws -> URL {
    let url = try file(home, relative, size: 1, age: age)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(size))
    try handle.close()
    try setTimes(url, age)
    return url
}

@Test func anUnpackedVMImageBesideItsCompressedSourceIsOfferedForTrashOnlyWhileTheAppIsClosed() async throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let image = try sparse(home, vmBundles + "/claudevm.bundle/rootfs.img", size: 800 * megabyte, age: 5 * day)
    try file(home, vmBundles + "/claudevm.bundle/rootfs.img.zst", size: 1000)
    // Not offered: no compressed source, too small to matter, a source larger than the image, or inside a sparse bundle.
    try sparse(home, vmBundles + "/claudevm.bundle/data.img", size: 800 * megabyte)
    try sparse(home, vmBundles + "/claudevm.bundle/efi.img", size: 50 * megabyte)
    try file(home, vmBundles + "/claudevm.bundle/efi.img.gz", size: 100)
    try file(home, vmBundles + "/claudevm.bundle/odd.img", size: 100)
    try sparse(home, vmBundles + "/claudevm.bundle/odd.img.xz", size: 200 * megabyte)
    try sparse(home, vmBundles + "/claudevm.bundle/disk.sparsebundle/bands/0", size: 800 * megabyte)
    try file(home, vmBundles + "/claudevm.bundle/disk.sparsebundle/bands/0.zst", size: 100)
    // The same pair outside a known app's VM folder is not offered.
    try sparse(home, "Documents/rootfs.img", size: 800 * megabyte)
    try file(home, "Documents/rootfs.img.zst", size: 100)

    let catalog = Catalog(rules: fixtureRules)
    let candidates = catalog.discover(fixture: home, locateTool: { _ in nil })
    #expect(candidates.map(\.url.path) == [image.path])
    let candidate = try #require(candidates.first)
    #expect(candidate.ruleID == "app-vm-images")
    #expect(candidate.action == .trash)
    #expect(candidate.logicalBytes == Int64(800 * megabyte))
    let used = try #require(candidate.lastUsed)
    #expect(abs(used.timeIntervalSinceNow + 5 * day) < 5)
    let rule = try #require(catalog.rule("app-vm-images"))
    #expect(rule.category == .models)

    #expect(CandidateCheck(catalog: catalog, running: Running(names: ["Claude"])).check(candidate) == .ownerRunning("Claude"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(candidate) == nil)
    let record = try #require(try await run(home, [candidate]).records.first)
    #expect(record.state == .succeeded)
    #expect(record.message == "Moved to Trash")
    #expect(!FileManager.default.fileExists(atPath: image.path))
    #expect(FileManager.default.fileExists(atPath: image.path + ".zst"))
}

@Test func sparseBundlesStayProtectedOutsideTheVMImageRule() throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try sparse(home, vmBundles + "/claudevm.bundle/rootfs.img", size: 800 * megabyte)
    try file(home, vmBundles + "/claudevm.bundle/rootfs.img.zst", size: 100)
    let candidate = try #require(Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { _ in nil }).first)
    // A rule that doesn't lift the bundle protection refuses the same item.
    let others = fixtureRules.filter { $0.id != "app-vm-images" }
    let strict = try #require(fixtureRules.first { $0.id == "app-vm-images" })
    let plain = CleanupRule(id: strict.id, category: strict.category, title: strict.title, detail: strict.detail, consequence: strict.consequence,
                            regen: strict.regen, action: strict.action, locations: strict.locations, owner: strict.owner, contents: strict.contents)
    let check = CandidateCheck(catalog: Catalog(rules: others + [plain]), running: Running())
    #expect(check.check(candidate) == .protected("claudevm.bundle"))
    // Only the app's own `.bundle` folder is lifted; sparse bundles and other protected kinds stay protected.
    #expect(strict.unprotectedExtensions == ["bundle"])
}
