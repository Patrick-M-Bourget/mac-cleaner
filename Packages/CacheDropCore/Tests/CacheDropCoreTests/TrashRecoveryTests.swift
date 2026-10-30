import Foundation
import SQLite3
import Testing
@testable import CacheDropCore

private func fixtureDownloads() throws -> (home: URL, downloads: URL) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropTrashRecovery-\(UUID())").resolvingSymlinksInPath()
    let downloads = home.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    return (home.resolvingSymlinksInPath(), downloads.resolvingSymlinksInPath())
}

@Test func anInterruptedTrashRunIsRecoveredOnTheNextLaunchAndNeverRepeated() throws {
    let (home, downloads) = try fixtureDownloads()
    defer { try? FileManager.default.removeItem(at: home) }
    for name in ["a.dmg", "b.pkg"] { try Data([1, 2]).write(to: downloads.appendingPathComponent(name)) }
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home).sorted { $0.url.path < $1.url.path }
    let approval = CatalogApproval(candidates: candidates, previewOnly: false)
    let url = home.appendingPathComponent("cleanup.sqlite")
    do {
        // The app quits after recording intent for the first item, before any outcome.
        let journal = try SQLiteCleanupJournal(url: url)
        let records = candidates.map { CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: $0, previewOnly: false) }
        #expect(try journal.claim(batchID: approval.id, records: records))
        var started = records[0]; started.state = .intent
        try journal.intent(started)
    }
    let reader = try SQLiteCleanupJournal(url: url, readOnly: true)
    let snapshot = try CleanupRecoverySnapshot(journal: reader)
    #expect(snapshot.interruptedBatches.count == 1)
    #expect(snapshot.unresolvedCount == 1)
    #expect(snapshot.pendingCount == 1)
    #expect(snapshot.interruptedBatches.first?.records.map(\.action) == ["moveToTrash", "moveToTrash"])
    #expect(snapshot.interruptedBatches.first?.records.first?.ruleID == "downloads")
    #expect(try reader.completedHistory().completedRuns.isEmpty)
    #expect(try reader.completedHistory().protectedRecordCount == 2)
    let writer = try SQLiteCleanupJournal(url: url)
    #expect(try writer.claim(batchID: approval.id, records: []) == false)
    #expect(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("a.dmg").path))
}

/// A record written by the Downloads-only Trash flow before the catalog existed.
private let legacyRecord = #"{"action":"moveToTrash","allocatedBytes":4096,"approvedAt":814724718.878114,"batchID":"FD8FB579-0EB5-4CC1-925B-F038F4B44EEB","downloadsResourceID":"16777230:106731990","downloadsURL":"file:\/\/\/private\/tmp\/CacheDropLegacy\/","id":"FD8FB579-0EB5-4CC1-925B-F038F4B44EEB|\/private\/tmp\/CacheDropLegacy\/Setup.dmg|16777230:106731991|moveToTrash","logicalBytes":3,"message":"Operation intent recorded; outcome unresolved","modifiedNanoseconds":849782547,"modifiedSeconds":1793031918,"observedAt":814724718.877688,"originalURL":"file:\/\/\/private\/tmp\/CacheDropLegacy\/Setup.dmg","policyVersion":1,"resourceID":"16777230:106731991","scopeResourceID":"16777230:106731990","scopeURL":"file:\/\/\/private\/tmp\/CacheDropLegacy\/","state":"intent","volumeID":"2CDE06D0-E3BF-4995-9F32-FE90CC292F1B"}"#

@Test func journalsWrittenByTheDownloadsOnlyFlowStillDecodeForRecovery() throws {
    let (home, _) = try fixtureDownloads()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = home.appendingPathComponent("cleanup.sqlite")
    _ = try SQLiteCleanupJournal(url: url)
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    let sql = "INSERT INTO batches VALUES('FD8FB579-0EB5-4CC1-925B-F038F4B44EEB'); INSERT INTO records(id, payload) VALUES('legacy', CAST('\(legacyRecord)' AS BLOB));"
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let reader = try SQLiteCleanupJournal(url: url, readOnly: true)
    let record = try #require(try reader.records().first)
    #expect(record.policyVersion == 1)
    #expect(record.action == "moveToTrash")
    #expect(record.ruleID == nil)
    #expect(record.previewOnly == nil)
    #expect(record.downloadsURL?.path == "/private/tmp/CacheDropLegacy")
    #expect(try CleanupRecoverySnapshot(journal: reader).unresolvedCount == 1)
}

private struct RefusingTrash: TrashMoving {
    var cancellation: CleanupCancellation?
    func moveToTrash(_ url: URL) throws -> URL? { cancellation?.cancel(); throw CocoaError(.fileWriteNoPermission) }
}
private struct FailOutcomeJournal: CleanupJournaling {
    let base: SQLiteCleanupJournal
    func claim(batchID: UUID, records: [CleanupRecord]) throws -> Bool { try base.claim(batchID: batchID, records: records) }
    func intent(_ record: CleanupRecord) throws { try base.intent(record) }
    func outcome(_ record: CleanupRecord) throws { throw CleanupJournalError.unavailable }
    func records() throws -> [CleanupRecord] { try base.records() }
    func append(_ records: [CleanupRecord]) throws { throw CleanupJournalError.unavailable }
}
private func twoInstallers() throws -> (URL, [Candidate]) {
    let (home, downloads) = try fixtureDownloads()
    for name in ["a.dmg", "b.dmg"] { try Data([1]).write(to: downloads.appendingPathComponent(name)) }
    return (home, Catalog(rules: fixtureRules).discover(fixture: home).sorted { $0.url.path < $1.url.path })
}

@Test func anOutcomeThatCannotBeRecordedLeavesADurableIntentAndStopsTheNextItem() async throws {
    let (home, candidates) = try twoInstallers()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = home.appendingPathComponent("journal.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FixtureNothingRunning())
    let result = await CleanupExecutor(journal: FailOutcomeJournal(base: journal), check: check, measure: { _ in nil }, trash: RefusingTrash())
        .execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.unknown, .cancelled])
    #expect(result.journalFailure != nil)
    let recovered = try SQLiteCleanupJournal(url: url).records()
    #expect(recovered.map(\.state) == [.intent, .pending])
    #expect(try CleanupRecoverySnapshot(journal: SQLiteCleanupJournal(url: url, readOnly: true)).unresolvedCount == 1)
}

@Test func cancellingATrashRunRecordsTheRestAsNotStarted() async throws {
    let (home, candidates) = try twoInstallers()
    defer { try? FileManager.default.removeItem(at: home) }
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let cancellation = CleanupCancellation()
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FixtureNothingRunning())
    let result = await CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: RefusingTrash(cancellation: cancellation), cancellation: cancellation)
        .execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.failed, .cancelled])
    #expect(try journal.records().map(\.state) == [.failed, .cancelled])
    #expect(try CleanupRecoverySnapshot(journal: journal).interruptedBatches.isEmpty)
}
