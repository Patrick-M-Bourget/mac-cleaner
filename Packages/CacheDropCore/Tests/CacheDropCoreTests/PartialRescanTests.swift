import Foundation
import Testing
@testable import CacheDropCore

/// #556 part 2, Decision 133: after a run, the catalog reads again only the rules the run acted on and merges them into
/// the rows it shows, as a full scan would have found them.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropPartial-\(UUID())").resolvingSymlinksInPath()
    for name in ["a", "b", "c"] {
        let folder = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: folder.appendingPathComponent("blob"))
    }
    return home
}
private func rule(_ id: String, _ locations: [String], yields: Bool = false) -> CleanupRule {
    CleanupRule(id: id, category: .developer, title: id, detail: "", consequence: "", regen: .cache, action: .delete, locations: locations, owner: nil,
                yieldsToOtherRules: yields)
}

@Test func aPartialDiscoveryReadsOnlyItsRulesButStillYieldsToTheOthers() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // "inner" yields to "outer", whose location holds it; reading "inner" alone must yield as a full scan does.
    try FileManager.default.createDirectory(at: home.appendingPathComponent("a/inner"), withIntermediateDirectories: true)
    try Data(count: 4096).write(to: home.appendingPathComponent("a/inner/blob"))
    let catalog = Catalog(rules: [rule("outer", ["a"]), rule("inner", ["a/inner"], yields: true), rule("other", ["b"])])
    let full = catalog.discovery(fixture: home)
    let partial = catalog.discovery(home: home, inUse: FixtureNothingInUse(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(),
                                    access: .granted, only: ["inner", "other"])
    #expect(Set(partial.scannedRuleIDs) == ["inner", "other"])
    #expect(partial.candidates.map(\.ruleID) == ["other"], "Only its rules, and inner still yields to outer")
    #expect(full.candidates.filter { $0.ruleID != "outer" }.map(\.url) == partial.candidates.map(\.url))
}

@Test func mergingAPartialRescanKeepsUntouchedRowsAndReplacesTheRescannedOnes() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: [rule("a", ["a"]), rule("b", ["b"]), rule("c", ["c"])])
    let shown = catalog.discover(fixture: home)
    try #require(shown.map(\.ruleID) == ["a", "b", "c"])
    // The run cleaned b; c grew meanwhile but wasn't touched, so it keeps the row it showed.
    try FileManager.default.removeItem(at: home.appendingPathComponent("b"))
    try Data(count: 8192).write(to: home.appendingPathComponent("c/more"))
    let fresh = catalog.discovery(home: home, inUse: FixtureNothingInUse(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), access: .granted,
                                  only: ["b"])
    let merged = catalog.merging(fresh, rescanned: ["b"], into: CatalogDiscovery(candidates: shown, notes: [])).candidates
    #expect(merged.map(\.ruleID) == ["a", "c"], "b is gone; a and c stay, in catalog order")
    #expect(merged.first { $0.ruleID == "c" } == shown.first { $0.ruleID == "c" }, "An untouched row is as it was")
}

@Test func mergingOffersSharedSpaceOnceToTheEarlierRuleAsAFullScanDoes() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // Two rules name the same folder: a full scan offers it once, under the first.
    let catalog = Catalog(rules: [rule("first", ["a"]), rule("second", ["a"]), rule("other", ["b"])])
    let shown = catalog.discover(fixture: home)
    try #require(shown.map(\.ruleID) == ["first", "other"])
    let fresh = catalog.discovery(home: home, inUse: FixtureNothingInUse(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), access: .granted,
                                  only: ["second"])
    try #require(fresh.candidates.map(\.ruleID) == ["second"], "Read alone, the later rule finds the folder")
    #expect(catalog.merging(fresh, rescanned: ["second"], into: CatalogDiscovery(candidates: shown, notes: [])).candidates.map(\.ruleID) == ["first", "other"], "Still offered once, by the first rule")
}

@Test func mergingKeepsLeftoversUnlessARescannedRuleNowOffersThem() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: [rule("a", ["a"]), rule("b", ["b"])])
    let found = catalog.discover(fixture: home)
    func makeLeftover(at url: URL) -> Candidate {
        Candidate(ruleID: RemovedAppLeftovers.possiblyRelatedRuleID, action: .trash, url: url, resourceID: "9:" + url.lastPathComponent, isDirectory: true,
                  toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1, allocatedBytes: 1, sizeComplete: true, lastUsed: nil,
                  observedAt: Date(), profile: nil)
    }
    let leftover = makeLeftover(at: found[1].url), elsewhere = makeLeftover(at: home.appendingPathComponent("c"))
    let shown = [found[0], leftover, elsewhere]
    let fresh = catalog.discovery(home: home, inUse: FixtureNothingInUse(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), access: .granted,
                                  only: ["b"])
    let merged = catalog.merging(fresh, rescanned: ["b"], into: CatalogDiscovery(candidates: shown, notes: [])).candidates
    #expect(merged.map(\.ruleID) == ["a", "b", RemovedAppLeftovers.possiblyRelatedRuleID], "The leftover b now offers leaves; the other stays, after the rules")
    #expect(merged.last?.url == elsewhere.url)
}

@Test func theRescanReadsTheRunsRulesAndTheRulesThatShareTheirReading() throws {
    let docker = BuiltInCatalog.rules.filter { if case .docker = $0.items { true } else { false } }
    try #require(docker.count > 1)
    let scope = Catalog(rules: BuiltInCatalog.rules).rescanned(ruleIDs: [docker[0].id, "npm-cache"])
    #expect(scope.isSuperset(of: Set(docker.map(\.id))), "Docker is read once for all its rules")
    #expect(scope.contains("npm-cache"))
    #expect(!scope.contains("yarn-cache"))
}

/// Only the remembered folders the run changed something in, or that sit inside what it removed, are checked again.
@Test func theRescanChecksAgainOnlyTheFoldersTheRunChangedSomethingIn() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: [rule("a", ["a"]), rule("b", ["b"])])
    let found = catalog.discover(fixture: home)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("j.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: { _ in nil }, trash: TrashNeverUsed())
    let result = await run.execute(CatalogApproval(candidates: [found[0]], dryRun: false))
    let folders = [home, home.appendingPathComponent("a/deep"), home.appendingPathComponent("b"), home.appendingPathComponent("c")]
    #expect(result.foldersTouched(among: folders) == [home, home.appendingPathComponent("a/deep")])

    let dryRun = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: { _ in nil },
                                       trash: TrashNeverUsed()).execute(CatalogApproval(candidates: [found[1]], dryRun: true))
    #expect(dryRun.foldersTouched(among: folders).isEmpty, "A dry run changed nothing")
}

/// A row at, inside or holding what the run removed is read again too, so a cleaned item never shows as still there (Decision 80).
@Test func theRescanAlsoReadsRulesWithRowsNestedInWhatTheRunRemoved() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent("a/inner"), withIntermediateDirectories: true)
    try Data(count: 4096).write(to: home.appendingPathComponent("a/inner/blob"))
    let catalog = Catalog(rules: [rule("outer", ["a"]), rule("nested", ["a/inner"]), rule("other", ["b"])])
    let shown = catalog.discover(fixture: home)
    try #require(Set(shown.map(\.ruleID)) == ["outer", "nested", "other"])
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("j.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: { _ in nil }, trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: shown.filter { $0.ruleID == "outer" }, dryRun: false))
    #expect(catalog.rescanned(after: result, shown: shown) == ["outer", "nested"])
}

/// Notes and Full Disk Access rows are the rescanned rules' new ones; every other rule keeps its own.
@Test func mergingReplacesOnlyTheRescannedRulesNotesAndAccess() {
    let a = rule("a", ["a"]), b = rule("b", ["b"])
    let shown = CatalogDiscovery(candidates: [], notes: [CatalogNote(ruleID: "a", text: "kept"), CatalogNote(ruleID: "b", text: "old")], notAccessible: [a, b])
    let fresh = CatalogDiscovery(candidates: [], notes: [CatalogNote(ruleID: "b", text: "new")], notAccessible: [])
    let merged = Catalog(rules: [a, b]).merging(fresh, rescanned: ["b"], into: shown)
    #expect(merged.notes.map(\.text) == ["kept", "new"])
    #expect(merged.notAccessible.map(\.id) == ["a"])
}
