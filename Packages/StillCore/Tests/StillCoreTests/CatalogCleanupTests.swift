import Foundation
import Testing
import StillCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalog-\(UUID())")
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
    let candidates = Catalog(rules: BuiltInCatalog.rules).discover(home: home)
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
    #expect(Catalog(rules: BuiltInCatalog.rules).discover(home: home).isEmpty)
}

private struct FakeRunning: RunningAppChecking {
    var running: Set<String> = []
    var unknown = false
    func isRunning(_ owner: RuleOwner) -> Bool? { unknown ? nil : running.contains(owner.name) }
}
private func npmCandidate(_ home: URL) throws -> Candidate {
    try #require(Catalog(rules: BuiltInCatalog.rules).discover(home: home).first)
}

@Test func aCandidateWhoseOwnerIsRunningIsRefusedWithAReason() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let catalog = Catalog(rules: BuiltInCatalog.rules)
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
    let check = CandidateCheck(catalog: Catalog(rules: BuiltInCatalog.rules), running: FakeRunning())
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
    try FileManager.default.createDirectory(at: cache.appendingPathComponent(".git"), withIntermediateDirectories: true)
    let candidate = try npmCandidate(home)
    #expect(CandidateCheck(catalog: Catalog(rules: BuiltInCatalog.rules), running: FakeRunning()).check(candidate) == .protected(".git"))
}

@Test func anExcludedCandidateOrOneHoldingAnExclusionIsRefused() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidate = try npmCandidate(home)
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    let outer = ExclusionPolicy(rules: [try ExclusionRule.capture(home.appendingPathComponent(".npm"))])
    #expect(CandidateCheck(catalog: catalog, running: FakeRunning(), exclusions: outer).check(candidate) == .excluded)
    let inner = ExclusionPolicy(rules: [try ExclusionRule.capture(cache.appendingPathComponent("index-v5"))])
    #expect(CandidateCheck(catalog: catalog, running: FakeRunning(), exclusions: inner).check(candidate) == .excluded)
}

@Test func npmIsMatchedByItsScriptNotByEveryNodeProcess() throws {
    let npm = try #require(BuiltInCatalog.rules.first { $0.id == "npm-cache" }?.owner)
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
