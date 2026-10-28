import Foundation
import Testing
import CacheDropCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func writeNpmCache(in home: URL, files: [String: Int] = ["index-v5/aa/one": 3, "content-v2/sha512/ab/blob": 5000]) throws -> URL {
    let cache = home.appendingPathComponent(".npm/_cacache")
    for (path, size) in files {
        let file = cache.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: size).write(to: file)
    }
    return cache
}

@Test func npmRuleDiscoversTheCacheFolderWithItsSize() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home)
    #expect(candidates.count == 1)
    let candidate = try #require(candidates.first)
    #expect(candidate.ruleID == "npm-cache")
    #expect(candidate.url.path == cache.path)
    #expect(candidate.action == .delete)
    #expect(candidate.logicalBytes == 5003)
    #expect(candidate.sizeComplete)
    #expect((candidate.allocatedBytes ?? 0) >= 5003)
}

@Test func aRuleWhoseFolderIsMissingOffersNothing() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(Catalog(rules: fixtureRules).discover(fixture: home).isEmpty)
}

private struct FakeRunning: RunningAppChecking {
    var running: Set<String> = []
    var unknown = false
    func isRunning(_ owner: RuleOwner) -> Bool? { unknown ? nil : running.contains(owner.name) }
}
private func npmCandidate(_ home: URL) throws -> Candidate {
    try #require(Catalog(rules: fixtureRules).discover(fixture: home).first)
}

@Test func aCandidateWhoseOwnerIsRunningIsRefusedWithAReason() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let catalog = Catalog(rules: fixtureRules)
    #expect(CandidateCheck(catalog: catalog, running: FakeRunning()).check(candidate) == nil)
    let refusal = CandidateCheck(catalog: catalog, running: FakeRunning(running: ["npm"])).check(candidate)
    #expect(refusal == .ownerRunning("npm"))
    #expect(refusal?.reason == "npm is running. Quit it, then scan again.")
    #expect(CandidateCheck(catalog: catalog, running: FakeRunning(unknown: true)).check(candidate) == .ownerUnknown("npm"))
}

@Test func aMissingOrReplacedFolderIsRefused() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FakeRunning())
    try FileManager.default.moveItem(at: cache, to: home.appendingPathComponent(".npm/old"))
    #expect(check.check(candidate) == .missing)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    #expect(check.check(candidate) == .changed)
    try FileManager.default.removeItem(at: cache)
    try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: home.appendingPathComponent(".npm/old"))
    #expect(check.check(candidate) == .changed)
}

@Test func aGitWorkingTreeInsideTheCacheIsProtected() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    try FileManager.default.createDirectory(at: cache.appendingPathComponent(".git"), withIntermediateDirectories: true)
    #expect(Catalog(rules: fixtureRules).discover(fixture: home).isEmpty)
    #expect(CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FakeRunning()).check(candidate) == .protected(".git"))
}

/// #211: a cache folder holding one of CacheDrop's or Still's own folders, the apps' or a UI-test runner's, is refused.
@Test(arguments: ["CacheDrop", "Still", "com.patrickbourget.CacheDrop", "com.patrickbourget.Still",
                  "com.patrickbourget.StillUITests", "com.patrickbourget.CacheDropUITests", "com.patrickbourget.CacheDropUITests.xctrunner"])
func aCacheHoldingOneOfOurOwnFoldersIsProtected(name: String) throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    try FileManager.default.createDirectory(at: cache.appendingPathComponent(name), withIntermediateDirectories: true)
    #expect(Catalog(rules: fixtureRules).discover(fixture: home).isEmpty)
    #expect(CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FakeRunning()).check(candidate) == .protected(name))
}

@Test func anExcludedCandidateOrOneHoldingAnExclusionIsRefused() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let catalog = Catalog(rules: fixtureRules)
    let outer = ExclusionPolicy(rules: [try ExclusionRule.capture(home.appendingPathComponent(".npm"))])
    #expect(CandidateCheck(catalog: catalog, running: FakeRunning(), exclusions: outer).check(candidate) == .excluded)
    let inner = ExclusionPolicy(rules: [try ExclusionRule.capture(cache.appendingPathComponent("index-v5"))])
    #expect(CandidateCheck(catalog: catalog, running: FakeRunning(), exclusions: inner).check(candidate) == .excluded)
    // #313: the reason names where exclusions live, Locations & access's Protected items.
    #expect(CheckRefusal.excluded.reason == "In Protected items, in Locations & access.")
}

@Test func npmIsMatchedByItsScriptNotByEveryNodeProcess() throws {
    let npm = try #require(fixtureRules.first { $0.id == "npm-cache" }?.owner)
    #expect(npm.matches(["node", "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js", "install"]))
    #expect(npm.matches(["node", "/usr/local/bin/npm", "ci"]))
    #expect(npm.matches(["/usr/local/bin/node", "--max-old-space-size=4096", "/x/npx-cli.js"]))
    #expect(!npm.matches(["node", "/Users/me/.vscode/extensions/tsserver.js"]))
    #expect(!npm.matches(["node", "server.js", "npm"]))
    #expect(!npm.matches(["/Applications/Visual Studio Code.app/Contents/MacOS/Electron"]))
}

@Test func theSystemCheckerFindsALiveProcessRunningTheOwnersScript() throws {
    let folder = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: folder) }
    let script = folder.appendingPathComponent("still-fake-tool-\(UUID().uuidString.prefix(8)).sh")
    try "sleep 30\n".write(to: script, atomically: true, encoding: .utf8)
    let owner = RuleOwner(name: "fake tool", scripts: [script.lastPathComponent])
    let checker = SystemRunningAppChecker()
    #expect(checker.isRunning(owner) == false)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path]
    try process.run()
    defer { process.terminate() }
    Thread.sleep(forTimeInterval: 0.2)
    #expect(checker.isRunning(owner) == true)
}

/// A fake volume whose available space grows by what each item frees.
private final class FakeVolume: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Int64 = 1_000_000
    var freedPerRead: [Int64] = []
    func read(_ url: URL) -> CapacitySample? {
        lock.lock(); defer { lock.unlock() }
        if !freedPerRead.isEmpty { available += freedPerRead.removeFirst() }
        return CapacitySample(available: available, total: 10_000_000, volumeID: "fake-volume", metric: .important, date: Date())
    }
}
private func executor(_ home: URL, running: FakeRunning = FakeRunning(), catalog: Catalog = Catalog(rules: fixtureRules), volume: FakeVolume = FakeVolume()) throws -> (CleanupExecutor, SQLiteCleanupJournal) {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    return (CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: running), measure: volume.read, trash: TrashNeverUsed()), journal)
}

@Test func deletingTheNpmCacheRecordsMeasuredFreedSpaceApartFromTheEstimate() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let volume = FakeVolume()
    volume.freedPerRead = [0, 4096]
    let (run, journal) = try executor(home, volume: volume)
    let approval = CatalogApproval(candidates: [candidate], previewOnly: false)
    let result = await run.execute(approval)
    #expect(result.records.map(\.state) == [.succeeded])
    #expect(!FileManager.default.fileExists(atPath: cache.path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm").path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".npm").path).isEmpty)
    #expect(result.estimatedBytes == candidate.allocatedBytes)
    #expect(result.measuredFreedBytes == 4096)
    #expect(result.records.first?.action == "delete")
    #expect(result.records.first?.ruleID == "npm-cache")
    let reopened = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    #expect(try reopened.records().map(\.state) == [.succeeded])
    #expect(try reopened.records().first?.itemCapacity?.observedChange == 4096)
    _ = journal
    let replay = await run.execute(approval)
    #expect(replay.rejectedReplay)
}

/// Every path with its contents, so a test can prove nothing changed on disk.
private func snapshot(_ root: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(root.path.count))
        result[relative] = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true ? try Data(contentsOf: url) : Data()
    }
    return result
}

@Test func previewOnlyRunsTheWholeFlowAndChangesNothingOnDisk() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let before = try snapshot(cache)
    let (run, _) = try executor(home)
    let result = await run.execute(CatalogApproval(candidates: [candidate], previewOnly: true))
    #expect(try snapshot(cache) == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".npm").path) == ["_cacache"])
    let record = try #require(result.records.first)
    #expect(record.previewOnly == true)
    #expect(record.state == .skipped)
    #expect(record.message.hasPrefix("Dry run: would delete"))
    #expect(result.previewOnly)
    #expect(result.measuredFreedBytes == nil)
    #expect(result.estimatedBytes == candidate.allocatedBytes)
}

@Test func aChangedOrOwnerRunningItemIsSkippedAndReportedWhileTheRestContinue() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for folder in ["a/cache", "b/cache", "c/cache"] {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: home.appendingPathComponent(folder + "/file"))
    }
    let catalog = Catalog(rules: [
        CleanupRule(id: "a", category: .developer, title: "A", detail: "", consequence: "", regen: .cache, action: .delete, locations: ["a/cache", "b/cache"], owner: nil),
        CleanupRule(id: "c", category: .developer, title: "C", detail: "", consequence: "", regen: .cache, action: .delete, locations: ["c/cache"], owner: RuleOwner(name: "Tool C", executables: ["toolc"])),
    ])
    let candidates = catalog.discover(fixture: home)
    #expect(candidates.map(\.ruleID) == ["a", "a", "c"])
    try FileManager.default.removeItem(at: home.appendingPathComponent("a/cache"))
    try FileManager.default.createDirectory(at: home.appendingPathComponent("a/cache"), withIntermediateDirectories: true)
    let (run, _) = try executor(home, running: FakeRunning(running: ["Tool C"]), catalog: catalog)
    let result = await run.execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.skipped, .succeeded, .skipped])
    #expect(result.records.map(\.message) == ["Changed since the scan.", "Permanently removed", "Tool C is running. Quit it, then scan again."])
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("a/cache").path))
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("b/cache").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("c/cache/file").path))
}

@Test func historyNeverCountsDeletedCachesAsHeldInTrash() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try writeNpmCache(in: home)
    let (run, journal) = try executor(home)
    _ = await run.execute(CatalogApproval(candidates: [try npmCandidate(home)], previewOnly: false))
    let history = try journal.completedHistory()
    #expect(history.completedRuns.count == 1)
    #expect(history.completedRuns.first?.trashHeldAllocatedBytes == 0)
}
