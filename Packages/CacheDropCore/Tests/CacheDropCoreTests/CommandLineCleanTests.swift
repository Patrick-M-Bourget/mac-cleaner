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

/// The cleanup lock's file in the fixture journal's folder.
private func lock(in folder: URL) -> URL { folder.appendingPathComponent(LocalStateLocation.cleanupLockName) }
private let testVerifier = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [])

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
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(), licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false)
        guard case .ran(let result, _) = outcome else { Issue.record("Refused: \(outcome)"); return }
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
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: FixtureHomeTrash(home: home),
                                                 licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false, measure: volume.read)
        guard case .ran(let result, _) = outcome else { Issue.record("Refused: \(outcome)"); return }
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
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: FixtureHomeTrash(home: home),
                                                 licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false, measure: FixtureSameVolume().read)
        guard case .ran(let result, _) = outcome else { Issue.record("Refused: \(outcome)"); return }
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
        let refused = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: FixtureHomeTrash(home: home),
                                                 licenseStore: MemoryLicenseKeyStore(), trialStore: used, gating: true, measure: FixtureSameVolume().read)
        guard case .refused(let reason) = refused else { Issue.record("Ran past the trial"); return }
        #expect(reason.hasPrefix("This cleanup is "), "The review sheet's line")
        #expect(try contents(of: home) == before && journal.records().isEmpty, "Nothing changed, nothing claimed")
        let dry = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(),
                                             licenseStore: MemoryLicenseKeyStore(), trialStore: used, gating: true, measure: FixtureSameVolume().read)
        guard case .ran = dry else { Issue.record("A dry run was blocked"); return }
        #expect(used.used == Trial.freeBytes - 1_000, "A dry run counts nothing")

        let fresh = MemoryTrialStore(0)
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: FixtureHomeTrash(home: home),
                                                 licenseStore: MemoryLicenseKeyStore(), trialStore: fresh, gating: true, measure: FixtureSameVolume().read)
        guard case .ran(let result, _) = outcome else { Issue.record("Refused a plan that fits"); return }
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
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(), licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false)
        guard case .refused(let reason) = outcome else { Issue.record("Ran with an interrupted cleanup"); return }
        #expect(reason == CommandLineClean.Refusal.interrupted && reason == "Review the interrupted cleanup in CacheDrop before cleaning again.")
        #expect(try contents(of: home) == before && journal.records().count == 1)
    }

    /// One cleanup at a time with the app (#627): while another holds the lock, nothing runs and nothing is claimed; the
    /// run releases it when it ends.
    @Test @MainActor func aCleanupRunningElsewhereRefusesAndChangesNothing() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let report = SmartCleanReport.run(sources), before = contents(of: home)
        var other = try CleanupLock.acquire(at: lock(in: folder))
        #expect(other != nil)
        let refused = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(),
                                                 licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false)
        guard case .refused(let reason) = refused else { Issue.record("Ran beside another cleanup"); return }
        #expect(reason == "A cleanup is already running, so nothing was changed.")
        #expect(try contents(of: home) == before && journal.records().isEmpty)
        other = nil
        let ran = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(),
                                             licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false)
        guard case .ran = ran else { Issue.record("Refused once the other ended: \(ran)"); return }
        #expect(try CleanupLock.acquire(at: lock(in: folder)) != nil, "Released when the run ended")
    }

    /// The tool is signed apart from the app, so a Keychain read can fail where the app's wouldn't (#627). With gating on, a
    /// license or trial it can't read refuses rather than reading as no license or a fresh 2 GB (Decision 137), and a trial
    /// item the app hasn't made yet refuses without making one. A dry run counts nothing, so it reads neither.
    @Test @MainActor func aLicenseOrTrialThatCantBeReadRefusesAndChangesNothing() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let report = SmartCleanReport.run(sources), before = contents(of: home)
        func refusal(_ license: MemoryLicenseKeyStore, _ trial: MemoryTrialStore) async -> String? {
            let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(),
                                                     licenseStore: license, trialStore: trial, gating: true, verifier: testVerifier, measure: FixtureSameVolume().read)
            if case .refused(let reason) = outcome { return reason }
            return nil
        }
        let unreadableLicense = MemoryLicenseKeyStore(); unreadableLicense.failReads = true
        #expect(await refusal(unreadableLicense, MemoryTrialStore(0)) == "CacheDrop couldn’t read the license on this Mac, so nothing was changed.")
        let unreadableTrial = MemoryTrialStore(0); unreadableTrial.failReads = true
        #expect(await refusal(MemoryLicenseKeyStore(), unreadableTrial) == "CacheDrop couldn’t read the free trial, so nothing was changed.")
        let missing = MemoryTrialStore()
        #expect(await refusal(MemoryLicenseKeyStore(), missing) == "Open CacheDrop once first, so it can keep the free trial’s count. Nothing was changed.")
        #expect(missing.writes == 0 && missing.used == nil, "The tool never makes the trial's item")
        #expect(try contents(of: home) == before && journal.records().isEmpty, "Nothing changed, nothing claimed")

        let unread = MemoryTrialStore(); unread.failReads = true
        let dry = await CommandLineClean.run(report, sources: sources, dryRun: true, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(),
                                             licenseStore: unreadableLicense, trialStore: unread, gating: true, verifier: testVerifier)
        guard case .ran = dry else { Issue.record("A dry run was blocked: \(dry)"); return }
        #expect(unread.reads == 0 && unread.writes == 0)
    }

    /// #722: `clean` refuses on the license or trial before asking "Clean up … now? [y/N]", with `run`'s own lines, so a
    /// "y" is never answered by a refusal it could have known. It reads only the license and trial: no lock, no journal,
    /// no writes, so it works while a cleanup runs elsewhere; `run` checks them again under the lock.
    @Test @MainActor func theLicenseAndTrialRefusalsAreKnownBeforeAsking() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        let report = SmartCleanReport.run(sources)
        let other = try CleanupLock.acquire(at: lock(in: folder))
        #expect(other != nil, "A cleanup runs elsewhere the whole time")
        func before(_ license: MemoryLicenseKeyStore, _ trial: MemoryTrialStore, dryRun: Bool = false, gating: Bool = true) -> String? {
            CommandLineClean.refusalBeforeAsking(report, sources: sources, dryRun: dryRun, licenseStore: license, trialStore: trial, gating: gating, verifier: testVerifier)
        }
        let unreadableLicense = MemoryLicenseKeyStore(); unreadableLicense.failReads = true
        #expect(before(unreadableLicense, MemoryTrialStore(0)) == CommandLineClean.Refusal.licenseUnreadable)
        let unreadableTrial = MemoryTrialStore(0); unreadableTrial.failReads = true
        #expect(before(MemoryLicenseKeyStore(), unreadableTrial) == CommandLineClean.Refusal.trialUnreadable)
        let missing = MemoryTrialStore()
        #expect(before(MemoryLicenseKeyStore(), missing) == CommandLineClean.Refusal.trialMissing)
        #expect(missing.writes == 0 && missing.used == nil, "Never makes the trial's item")
        let used = MemoryTrialStore(Trial.freeBytes - 1_000)
        let over = try #require(before(MemoryLicenseKeyStore(), used))
        #expect(over.hasPrefix("This cleanup is ") && over.hasSuffix(LicensePrice.buyURL.absoluteString + "."), "The review sheet's line, then where to buy")
        #expect(used.writes == 0 && used.used == Trial.freeBytes - 1_000)

        // Asked only when the run could go ahead: a plan that fits, an active license, a dry run, no gating.
        let fresh = MemoryTrialStore(0)
        #expect(before(MemoryLicenseKeyStore(), fresh) == nil && fresh.writes == 0)
        #expect(before(MemoryLicenseKeyStore(LicenseTestKeyPair.vector), MemoryTrialStore()) == nil)
        let unread = MemoryTrialStore(); unread.failReads = true
        #expect(before(unreadableLicense, unread, dryRun: true) == nil && before(unreadableLicense, unread, gating: false) == nil)
        #expect(unread.reads == 0)
        #expect(try journal.records().isEmpty, "Nothing claimed")

        // `run` takes the lock first, so here it says the cleanup elsewhere.
        let outcome = await CommandLineClean.run(report, sources: sources, dryRun: false, journal: journal, lock: lock(in: folder), trash: TrashNeverUsed(),
                                                 licenseStore: MemoryLicenseKeyStore(), trialStore: used, gating: true, verifier: testVerifier)
        guard case .refused(let busy) = outcome else { Issue.record("Ran beside another cleanup"); return }
        #expect(busy == CommandLineClean.Refusal.busy)
        withExtendedLifetime(other) {}
    }

    /// An active license needs no trial item, and its runs count nothing toward the trial.
    @Test @MainActor func anActiveLicenseCleansWithoutTheTrial() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        let trial = MemoryTrialStore(Trial.freeBytes)
        let outcome = await CommandLineClean.run(SmartCleanReport.run(sources), sources: sources, dryRun: false, journal: journal, lock: lock(in: folder),
                                                 trash: FixtureHomeTrash(home: home), licenseStore: MemoryLicenseKeyStore(LicenseTestKeyPair.vector),
                                                 trialStore: trial, gating: true, verifier: testVerifier, measure: FixtureSameVolume().read)
        guard case .ran(_, let notice) = outcome else { Issue.record("Refused a licensed run: \(outcome)"); return }
        #expect(notice == nil && trial.reads == 0 && trial.writes == 0)
    }

    /// A trial count that couldn't be saved is said (Decision 62), on standard error by the tool.
    @Test @MainActor func aTrialCountThatWasntSavedIsSaid() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        let trial = MemoryTrialStore(0); trial.failWrites = true
        let outcome = await CommandLineClean.run(SmartCleanReport.run(sources), sources: sources, dryRun: false, journal: journal, lock: lock(in: folder),
                                                 trash: FixtureHomeTrash(home: home), licenseStore: MemoryLicenseKeyStore(), trialStore: trial, gating: true,
                                                 verifier: testVerifier, measure: FixtureSameVolume().read)
        guard case .ran(_, let notice) = outcome else { Issue.record("Refused: \(outcome)"); return }
        #expect(notice == "The free trial’s count wasn’t saved")
    }

    /// `--json` always prints a report: an empty one when there's nothing to clean, and a dry run's carries its size.
    @Test @MainActor func theJSONSaysADryRunsSizeAndWhenThereIsNothingToClean() async throws {
        let (home, sources) = try commandLineFixture()
        let (folder, journal) = try fixtureJournal()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: folder) }
        func keys(_ report: CommandLineReport.Clean) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(CommandLineReport.json(report).utf8)) as? [String: Any])
        }
        let nothing = try keys(CommandLineReport.Clean(nothingToCleanIn: home, dryRun: false))
        #expect(Set(nothing.keys) == ["home", "dryRun", "toTrash", "items"] && (nothing["items"] as? [Any])?.isEmpty == true)
        #expect(Set(try keys(CommandLineReport.Clean(nothingToCleanIn: home, dryRun: true)).keys) == ["home", "dryRun", "toTrash", "wouldBeAffected", "items"])
        let outcome = await CommandLineClean.run(SmartCleanReport.run(sources), sources: sources, dryRun: true, journal: journal, lock: lock(in: folder),
                                                 trash: TrashNeverUsed(), licenseStore: MemoryLicenseKeyStore(), trialStore: MemoryTrialStore(), gating: false)
        guard case .ran(let result, _) = outcome else { Issue.record("Refused: \(outcome)"); return }
        let shown = CommandLineReport.Clean(result, home: home)
        let size = try #require(try keys(shown)["wouldBeAffected"] as? [String: Any])
        let affected = result.records.reduce(Int64(0)) { $0 + $1.recordedBytes }
        #expect(affected > 0 && (size["bytes"] as? NSNumber)?.int64Value == affected)
        #expect(shown.text.hasPrefix("Dry run · Nothing changed · " + SizeFormatter.text(affected)))
    }
}
