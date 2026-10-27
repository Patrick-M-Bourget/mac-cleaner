import Foundation
import Testing
@testable import CacheDropCore

/// uv's cache is changed only through uv's own commands (Decision 44): CacheDrop asks `uv cache dir` where it is
/// and runs `uv cache prune`, never deleting the folder itself. Every uv here is a stand-in script in a temp fixture.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropUV-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func makeFolder(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative).appendingPathComponent("entry")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
/// A stand-in uv: `cache dir` runs `dir`, `cache prune` runs `prune`, each a shell snippet.
private func fakeUV(_ home: URL, dir: String, prune: String = "exit 0") throws -> URL {
    let tool = home.appendingPathComponent("tools/uv")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    let script = "#!/bin/sh\ncase \"$1 $2\" in\n\"cache dir\") \(dir) ;;\n\"cache prune\") \(prune) ;;\n*) exit 64 ;;\nesac\n"
    try script.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}
private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }
private struct SameVolume { func read(_ url: URL) -> CapacitySample? { CapacitySample(available: 1_000, total: 10_000, volumeID: "fake", metric: .important, date: Date()) } }

private func execute(_ candidate: Candidate, catalog: Catalog, home: URL, previewOnly: Bool = false) async throws -> CleanupRecord {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NothingRunning()), measure: SameVolume().read, trash: TrashNeverUsed())
    return try #require(await run.execute(CatalogApproval(candidates: [candidate], previewOnly: previewOnly)).records.first)
}

@Test func uvsCacheIsPrunedWithItsOwnCommandAndItsFolderKept() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".cache/uv", bytes: 3000)
    let marker = home.appendingPathComponent("ran")
    let uv = try fakeUV(home, dir: "echo '\(home.path)/.cache/uv'", prune: "echo \"$@\" > '\(marker.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let rule = try #require(catalog.rule("uv-cache"))
    #expect(rule.action == .tool)
    #expect(rule.tool?.commandLine == "uv cache prune")
    #expect(rule.tool?.deletesLocationAfter == false)
    #expect(rule.consequence.hasPrefix("Runs `uv cache prune`"))

    let candidate = try #require(catalog.discover(fixture: home, locateTool: onlyTool("uv", uv)).first { $0.ruleID == "uv-cache" })
    #expect(candidate.action == .tool && candidate.toolURL == uv)
    #expect(candidate.url.path == home.appendingPathComponent(".cache/uv").path)
    // A prune frees an unknown part of the folder, so the folder's total isn't offered as the size.
    #expect(candidate.logicalBytes == 0 && !candidate.sizeComplete)

    let record = try await execute(candidate, catalog: catalog, home: home)
    #expect(record.state == .succeeded)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "cache prune\n")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cache/uv/entry").path))
}

/// uv's cache can be moved (`cache-dir` in uv.toml, `UV_CACHE_DIR`): the folder uv names is offered, not the default one.
@Test func aCustomUVCacheFolderIsTheOneOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".cache/uv")
    try makeFolder(home, "Developer/uv-cache")
    let uv = try fakeUV(home, dir: "echo '\(home.path)/Developer/uv-cache'")
    let found = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: onlyTool("uv", uv)).filter { $0.ruleID == "uv-cache" }
    #expect(found.map(\.url.path) == [home.appendingPathComponent("Developer/uv-cache").path])
    #expect(found.allSatisfy { $0.action == .tool && $0.folderSource == "Named by `uv cache dir`" })
}

/// A folder uv names outside the home folder is out of CacheDrop's scope, and one that doesn't exist has nothing to prune.
/// Either way the plan says why it isn't offered (#198).
@Test func aUVCacheFolderOutsideHomeOrMissingIsNotOffered() throws {
    let home = try fixtureHome(), outside = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: outside) }
    try makeFolder(home, ".cache/uv")
    try makeFolder(outside, "uv")
    let catalog = Catalog(rules: fixtureRules)
    for (named, why) in [("\(outside.path)/uv", "\(outside.path)/uv as its cache (`uv cache dir`), which is outside your home folder"),
                         ("\(home.path)/missing-uv", "~/missing-uv as its cache (`uv cache dir`), but there’s no folder there")] {
        let uv = try fakeUV(home, dir: "echo '\(named)'")
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("uv", uv))
        #expect(!discovery.candidates.contains { $0.ruleID == "uv-cache" }, "\(named)")
        #expect(discovery.notes == [CatalogNote(ruleID: "uv-cache", text: "uv names \(why), so it isn’t offered.")], "\(named)")
    }
}

/// Without uv nothing is offered: the folder is never deleted in its place.
@Test func withoutUVItsCacheIsNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".cache/uv")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: { _ in nil })
    #expect(!discovery.candidates.contains { $0.ruleID == "uv-cache" })
    #expect(!discovery.scannedRuleIDs.contains("uv-cache"))
}

/// `uv cache dir` failing, timing out or printing something that isn't a folder: the rule is unavailable, says why,
/// counts as not measured rather than 0, and never falls back to deleting the folder.
@Test func whenUVDoesntSayWhereItsCacheIsTheRuleIsUnavailable() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".cache/uv")
    var rules = fixtureRules
    let index = try #require(rules.firstIndex { $0.id == "uv-cache" })
    let rule = rules[index], tool = try #require(rule.tool)
    rules[index] = CleanupRule(id: rule.id, category: rule.category, title: rule.title, detail: rule.detail, consequence: rule.consequence, regen: rule.regen, action: rule.action,
                               locations: rule.locations, owner: rule.owner,
                               tool: ToolCommand(executables: tool.executables, arguments: tool.arguments, timeout: tool.timeout,
                                                 locationQuery: LocationQuery(try #require(tool.locationQuery).arguments, timeout: 0.3)))
    let catalog = Catalog(rules: rules)
    for answer in ["echo 'error: no cache' >&2; exit 2", "sleep 5", "echo 'cache is somewhere'", "echo ''", "echo '\(home.path)/../uv'"] {
        let uv = try fakeUV(home, dir: answer)
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("uv", uv))
        #expect(!discovery.candidates.contains { $0.ruleID == "uv-cache" }, "\(answer)")
        #expect(discovery.notes == [CatalogNote(ruleID: "uv-cache", text: "uv didn’t say where its cache is (`uv cache dir`), so it isn’t offered.")], "\(answer)")
        #expect(discovery.notMeasured["uv-cache"] == [".cache/uv"], "\(answer)")
    }
}

/// A dry run asks uv where its cache is but never runs the prune.
@Test func aDryRunNeverRunsUVsPrune() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".cache/uv")
    let marker = home.appendingPathComponent("ran")
    let uv = try fakeUV(home, dir: "echo '\(home.path)/.cache/uv'", prune: "touch '\(marker.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home, locateTool: onlyTool("uv", uv)).first { $0.ruleID == "uv-cache" })
    let record = try await execute(candidate, catalog: catalog, home: home, previewOnly: true)
    #expect(record.state == .skipped && record.message.hasPrefix(CleanupRecord.previewPrefix))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cache/uv/entry").path))
}

/// A prune stopped at its time limit may have removed part of the cache; the folder itself is left in place.
@Test func aUVPruneStoppedAtItsTimeLimitLeavesTheFolder() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".cache/uv")
    var rules = fixtureRules
    let index = try #require(rules.firstIndex { $0.id == "uv-cache" })
    let rule = rules[index], tool = try #require(rule.tool)
    rules[index] = CleanupRule(id: rule.id, category: rule.category, title: rule.title, detail: rule.detail, consequence: rule.consequence, regen: rule.regen, action: rule.action,
                               locations: rule.locations, owner: rule.owner,
                               tool: ToolCommand(executables: tool.executables, arguments: tool.arguments, timeout: 0.5, locationQuery: tool.locationQuery))
    let catalog = Catalog(rules: rules)
    let uv = try fakeUV(home, dir: "echo '\(home.path)/.cache/uv'", prune: "echo pruning; sleep 5")
    let candidate = try #require(catalog.discover(fixture: home, locateTool: onlyTool("uv", uv)).first { $0.ruleID == "uv-cache" })
    let record = try await execute(candidate, catalog: catalog, home: home)
    #expect(record.state == .failed && record.partlyRemoved == true)
    #expect(record.message == "Stopped at the 1-second time limit. uv cache prune may have cleaned part of it; the folder was left in place.")
    #expect(record.toolOutput == "pruning")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cache/uv/entry").path))
}
