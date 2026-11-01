import Foundation
import Testing
import CacheDropCore

/// #375: while the rescan after a run runs, the pages keep their rows, minus what the run cleaned.
@Test func theRowsKeptDuringThePostRunRescanLeaveOutWhatTheRunCleaned() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRescan-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    for name in ["cleaned", "skipped", "unchosen"] {
        let folder = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: folder.appendingPathComponent("blob"))
    }
    // The skipped item's owner is open, so the run's check refuses it and it stays on disk.
    struct OnlyBusyOpen: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { owner.name == "Busy" } }
    let rules = ["cleaned", "skipped", "unchosen"].map {
        CleanupRule(id: $0, category: .developer, title: $0, detail: "", consequence: "", regen: .cache, action: .delete, locations: [$0],
                    owner: RuleOwner(name: $0 == "skipped" ? "Busy" : "Idle", executables: ["x"]))
    }
    let catalog = Catalog(rules: rules)
    let shown = catalog.discover(fixture: home)
    let byRule = Dictionary(uniqueKeysWithValues: shown.map { ($0.ruleID, $0) })
    let cleaned = try #require(byRule["cleaned"]), skipped = try #require(byRule["skipped"]), unchosen = try #require(byRule["unchosen"])
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("j.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: OnlyBusyOpen()), measure: { _ in nil }, trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: [cleaned, skipped], dryRun: false))
    #expect(result.cleanedCandidateIDs == [cleaned.id])
    #expect(result.keptDuringRescan(shown).map(\.ruleID).sorted() == ["skipped", "unchosen"])
    #expect(result.keptDuringRescan([unchosen]) == [unchosen])
    // Decision 123 (#556): nothing an app or plug-in owns went, so Applications doesn't wait for the rescan.
    #expect(!result.changesApplications(listing: [unchosen.url, skipped.url]))
    // An item of another rule that Applications lists too (an app in Downloads), or a folder holding one, changes it.
    #expect(result.changesApplications(listing: [cleaned.url]))
    #expect(result.changesApplications(listing: [cleaned.url.appendingPathComponent("blob")]))
}

/// A dry run changed nothing on disk, so every row stays while its rescan runs, though its items leave the selection (#349).
@Test func aDryRunKeepsEveryRowDuringItsRescan() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRescan-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent("item"), withIntermediateDirectories: true)
    try Data(count: 4096).write(to: home.appendingPathComponent("item/blob"))
    let catalog = Catalog(rules: [CleanupRule(id: "item", category: .developer, title: "Item", detail: "", consequence: "", regen: .cache, action: .delete,
                                              locations: ["item"], owner: nil)])
    let shown = catalog.discover(fixture: home)
    try #require(shown.count == 1)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("j.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: { _ in nil }, trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: shown, dryRun: true))
    #expect(result.cleanedCandidateIDs == shown.map(\.id))
    #expect(result.keptDuringRescan(shown) == shown)
}
