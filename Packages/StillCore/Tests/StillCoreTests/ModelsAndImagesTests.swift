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

    let candidates = Catalog(rules: BuiltInCatalog.rules).discover(home: home, locateTool: { _ in nil })
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
    let rule = try #require(Catalog(rules: BuiltInCatalog.rules).rule("huggingface-models"))
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
    let check = CandidateCheck(catalog: Catalog(rules: BuiltInCatalog.rules), running: running)
    let executor = CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: FixtureTrash(folder: home.appendingPathComponent("FixtureTrash")))
    return await executor.execute(CatalogApproval(candidates: candidates, previewOnly: previewOnly))
}

@Test func aChosenHuggingFaceModelGoesToTrashAndTheOthersStay() async throws {
    let home = try modelsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try file(home, hub + "/models--org--chosen/blobs/aaa", size: 3000)
    let kept = try file(home, hub + "/models--org--kept/blobs/bbb", size: 3000)
    let candidates = Catalog(rules: BuiltInCatalog.rules).discover(home: home, locateTool: { _ in nil })
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
