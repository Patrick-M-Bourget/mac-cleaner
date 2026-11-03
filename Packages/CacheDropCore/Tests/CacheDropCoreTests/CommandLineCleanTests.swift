import Foundation
import Testing
@testable import CacheDropCore

// #627: `cachedrop clean` runs Smart clean's plan through the app's executor, checks and journal. A fixture home and a
// fixture journal only; nothing about this Mac is read or changed.

/// Every path under `folder` with its identity and size, to prove a dry run left it exactly as it was.
private func contents(of folder: URL) -> [String: String] {
    var found: [String: String] = [:]
    let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    while let url = walker?.nextObject() as? URL {
        let path = url.path, info = try? FileManager.default.attributesOfItem(atPath: path)
        found[path] = "\(info?[.systemFileNumber] ?? "")/\(info?[.size] ?? "")/\(info?[.modificationDate] ?? "")"
    }
    return found
}

/// A fixture journal beside, never inside, the fixture home.
private func fixtureJournal() throws -> (folder: URL, journal: SQLiteCleanupJournal) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCommandLineJournal-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return (folder, try SQLiteCleanupJournal(url: folder.appendingPathComponent(LocalStateLocation.cleanupJournalName)))
}

@MainActor private func ungated() -> TrialController { TrialController(store: MemoryTrialStore(), gating: false) }

@Suite struct CommandLineCleanTests {
    @Test func asksUnlessYesAndRefusesWithoutATerminal() {
        #expect(CommandLineClean.start(yes: false, dryRun: false, interactive: true) == .ask)
        #expect(CommandLineClean.start(yes: false, dryRun: false, interactive: false) == .refuse)
        #expect(CommandLineClean.start(yes: true, dryRun: false, interactive: false) == .run)
        // A dry run changes nothing on disk, so it needs no confirmation.
        #expect(CommandLineClean.start(yes: false, dryRun: true, interactive: false) == .run)
    }

    /// The app's journal file, which both write and History reads: a stored name.
    @Test func bothWriteTheAppsJournal() { #expect(LocalStateLocation.cleanupJournalName == "cleanup.sqlite") }

    @Test @MainActor func aDryRunChangesNothingAndHistoryShowsIt() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let before = contents(of: home)
        let report = SmartCleanReport.run(sources)
        #expect(report.picked.count == 2, "The npm cache and the old installer")
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, trash: TrashNeverUsed(), trial: ungated(), license: .none)
        guard case .ran(let result) = outcome else { Issue.record("Refused: \(outcome)"); return }
        #expect(contents(of: home) == before, "Nothing under the fixture home changed")
        #expect(result.dryRun && result.records.count == 2 && result.records.allSatisfy(\.wasDryRun))
        #expect(result.records.allSatisfy { $0.message.hasPrefix("Dry run: would ") }, "Each item logs what would happen")
        // History reads the same journal the app writes.
        let history = CleanupHistorySnapshot(records: try journal.records())
        #expect(history.completedRuns.map(\.id) == [result.batchID])
        #expect(history.completedRuns.first?.title == "Dry run · Nothing changed")
    }

    @Test @MainActor func aRunCleansThroughTheExecutorAndReportsMeasuredFreedSpace() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        let volume = FixtureVolume()
        // Read before and after each item: the npm cache frees 40 KB; the installer's Trash move frees nothing yet.
        let report = SmartCleanReport.run(sources)
        let order = report.picked.map { $0.candidate.url.lastPathComponent }
        volume.freedPerRead = order.flatMap { $0 == "Old Setup.dmg" ? [Int64(0), 0] : [0, 40_000] }
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, trash: FixtureHomeTrash(home: home),
                                                 trial: ungated(), license: .none, measure: volume.read)
        guard case .ran(let result) = outcome else { Issue.record("Refused: \(outcome)"); return }
        #expect(result.records.allSatisfy { $0.state == .succeeded })
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache").path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/Old Setup.dmg").path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Downloads/New Setup.dmg").path), "Only the plan's items")
        #expect(result.measuredFreedBytes == 40_000)
        let run = try #require(CleanupHistorySnapshot(records: try journal.records()).completedRuns.first)
        #expect(run.id == result.batchID && run.headline == .init(bytes: 40_000, note: "Freed"))
        let shown = CommandLineReport.Clean(result, home: home)
        #expect(shown.measuredFreed?.bytes == 40_000 && shown.measuredFreed?.kind == "measured")
        #expect(shown.text.contains("Measured freed space: " + SizeFormatter.text(Int64(40_000))))
        // The JSON keys are a contract for scripts and agents.
        let json = try #require(try JSONSerialization.jsonObject(with: Data(CommandLineReport.json(shown).utf8)) as? [String: Any])
        #expect(Set(json.keys) == ["home", "dryRun", "measuredFreed", "toTrash", "items"])
        #expect(Set(try #require((json["items"] as? [[String: Any]])?.first).keys) == ["path", "action", "state", "outcome"])
    }

    @Test @MainActor func eachItemIsCheckedAgainJustBeforeActing() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let report = SmartCleanReport.run(sources)
        // The npm cache is replaced after the plan was made: a different item now sits at its path.
        let cache = home.appendingPathComponent(".npm/_cacache")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache.appendingPathComponent("content-v2"), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 10).write(to: cache.appendingPathComponent("content-v2/blob"))
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, trash: FixtureHomeTrash(home: home),
                                                 trial: ungated(), license: .none, measure: FixtureSameVolume().read)
        guard case .ran(let result) = outcome else { Issue.record("Refused: \(outcome)"); return }
        let record = try #require(result.records.first { $0.originalURL.lastPathComponent == "_cacache" })
        #expect(record.state == .skipped)
        #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("content-v2/blob").path), "The new item stays")
    }

    /// Decision 135: the command line follows the app's trial. A plan bigger than what's left never runs; a dry run is never
    /// blocked; a run that fits counts what it removed.
    @Test @MainActor func theTrialGatesCleanupAsInTheApp() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        let report = SmartCleanReport.run(sources)
        let before = contents(of: home)
        let used = MemoryTrialStore(Trial.freeBytes - 1_000)
        let nearlyUsed = TrialController(store: used, gating: true)
        let refused = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, trash: FixtureHomeTrash(home: home),
                                                 trial: nearlyUsed, license: .none, measure: FixtureSameVolume().read)
        guard case .refused(let reason) = refused else { Issue.record("Ran past the trial"); return }
        #expect(reason.hasPrefix("This cleanup is "), "The review sheet's line")
        #expect(try contents(of: home) == before && journal.records().isEmpty, "Nothing changed, nothing claimed")
        let dry = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, trash: TrashNeverUsed(),
                                             trial: nearlyUsed, license: .none, measure: FixtureSameVolume().read)
        guard case .ran = dry else { Issue.record("A dry run was blocked"); return }
        #expect(used.used == Trial.freeBytes - 1_000, "A dry run counts nothing")

        let fresh = MemoryTrialStore(0)
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, trash: FixtureHomeTrash(home: home),
                                                 trial: TrialController(store: fresh, gating: true), license: .none, measure: FixtureSameVolume().read)
        guard case .ran(let result) = outcome else { Issue.record("Refused a plan that fits"); return }
        let approval = CatalogApproval(candidates: report.picked.map(\.candidate), dryRun: false)
        #expect(fresh.used == result.trialBytes(of: approval, catalog: sources.catalog) && (fresh.used ?? 0) > 0)
    }

    /// An unfinished cleanup in the journal (interrupted, or still running in the app) is reviewed in the app first.
    @Test @MainActor func anInterruptedCleanupIsReviewedFirst() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let report = SmartCleanReport.run(sources)
        let earlier = CatalogApproval(candidates: [try #require(report.picked.first?.candidate)], dryRun: false)
        _ = try journal.claim(batchID: earlier.id, records: earlier.candidates.map { CleanupRecord(batchID: earlier.id, approvedAt: earlier.approvedAt, candidate: $0, dryRun: false) })
        let before = contents(of: home)
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, trash: TrashNeverUsed(), trial: ungated(), license: .none)
        guard case .refused(let reason) = outcome else { Issue.record("Ran with an interrupted cleanup"); return }
        #expect(reason == "Review the interrupted cleanup in CacheDrop before cleaning again.")
        #expect(try contents(of: home) == before && journal.records().count == 1)
    }
}
