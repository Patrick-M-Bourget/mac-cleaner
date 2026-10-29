import Foundation
import Darwin
import Testing
import CacheDropCore

/// #309: an interrupted cleanup is checked against disk, then marked reviewed.
private struct InterruptedRun {
    let home: URL, downloads: URL, trash: URL, journal: SQLiteCleanupJournal
    let review: CleanupRecoveryReview
    func batch() throws -> CleanupRecoveryBatch { try #require(try CleanupRecoverySnapshot(journal: journal).interruptedBatches.first) }
    func url(_ name: String) -> URL { downloads.appendingPathComponent(name) }
}

/// Installers in a fixture Downloads, approved for the Trash and claimed; `started` names get an intent record,
/// `unknown` ones an unknown outcome. The fixture's `.Trash` stands in for the Trash.
private func interruptedRun(_ names: [String], started: Set<String>, unknown: Set<String> = []) throws -> InterruptedRun {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRecoveryReview-\(UUID())").resolvingSymlinksInPath()
    let downloads = home.appendingPathComponent("Downloads"), trash = home.appendingPathComponent(".Trash")
    for folder in [downloads, trash] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    for name in names { try Data(name.utf8).write(to: downloads.appendingPathComponent(name)) }
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home).filter { $0.url.deletingLastPathComponent().lastPathComponent == "Downloads" }
        .sorted { $0.url.path < $1.url.path }
    let approval = CatalogApproval(candidates: candidates, previewOnly: false)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("cleanup.sqlite"))
    let records = candidates.map { CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: $0, previewOnly: false) }
    #expect(try journal.claim(batchID: approval.id, records: records))
    for var record in records where started.contains(record.originalURL.lastPathComponent) || unknown.contains(record.originalURL.lastPathComponent) {
        record.state = .intent; record.message = "Started; outcome not yet recorded"
        try journal.intent(record)
        if unknown.contains(record.originalURL.lastPathComponent) {
            record.state = .unknown; record.message = "Move to Trash may be incomplete. Review it before cleaning again."
            try journal.outcome(record)
        }
    }
    return InterruptedRun(home: home, downloads: downloads, trash: trash, journal: journal, review: CleanupRecoveryReview(trashFolder: { _ in trash }))
}

@Test func eachUnresolvedItemIsCheckedAgainstItsPathAndTheTrash() throws {
    let run = try interruptedRun(["a.dmg", "b.dmg", "c.dmg", "d.dmg", "e.dmg"], started: ["a.dmg", "b.dmg", "c.dmg"], unknown: ["d.dmg"])
    defer { try? FileManager.default.removeItem(at: run.home) }
    // b reached the Trash under another name, c is gone, and d's place holds a different file.
    try FileManager.default.moveItem(at: run.url("b.dmg"), to: run.trash.appendingPathComponent("b 2.dmg"))
    try FileManager.default.removeItem(at: run.url("c.dmg"))
    try FileManager.default.removeItem(at: run.url("d.dmg"))
    try Data("other".utf8).write(to: run.url("d.dmg"))

    let items = run.review.check(try run.batch())
    #expect(items.map(\.record.originalURL.lastPathComponent) == ["a.dmg", "b.dmg", "c.dmg", "d.dmg", "e.dmg"])
    #expect(items.map(\.finding) == [.atOriginalLocation, .inTrash, .gone, .unknown, .notStarted])
    #expect(items[1].foundURL?.lastPathComponent == "b 2.dmg")
    #expect(items.map(\.title) == ["Not removed", "Moved to Trash", "Removed", "Unknown", "Not started"])
    #expect(items[4].detail == "It never started. Nothing was changed.")
    #expect(items.filter(\.needsConfirmation).map(\.record.originalURL.lastPathComponent) == ["d.dmg"])
}

@Test func markingReviewedAppendsFindingsSoTheRunIsNoLongerInterruptedAndResetWorks() throws {
    let run = try interruptedRun(["a.dmg", "b.dmg", "c.dmg", "d.dmg", "e.dmg"], started: ["a.dmg", "b.dmg", "c.dmg"], unknown: ["d.dmg"])
    defer { try? FileManager.default.removeItem(at: run.home) }
    try FileManager.default.moveItem(at: run.url("b.dmg"), to: run.trash.appendingPathComponent("b 2.dmg"))
    try FileManager.default.removeItem(at: run.url("c.dmg"))
    try FileManager.default.removeItem(at: run.url("d.dmg"))
    try Data("other".utf8).write(to: run.url("d.dmg"))
    let before = try run.journal.records()
    #expect(try run.journal.completedHistory().protectedRecordCount == 5)

    try run.review.markReviewed(run.review.check(try run.batch()), in: run.journal)

    // The original records are unchanged; one reviewed record per item is appended.
    let after = try run.journal.records()
    #expect(after.count == before.count + 5)
    #expect(after.prefix(before.count).map(\.state) == before.map(\.state))
    #expect(after.prefix(before.count).map(\.message) == before.map(\.message))
    #expect(try CleanupRecoverySnapshot(journal: run.journal).interruptedBatches.isEmpty)

    // History shows the run with its findings, under the original items.
    let history = try run.journal.completedHistory()
    #expect(history.protectedRecordCount == 0)
    let shown = try #require(history.completedRuns.first)
    #expect(history.completedRuns.count == 1)
    #expect(shown.records.map(\.id) == before.map(\.id))
    #expect(shown.records.map(\.outcomeTitle) == ["Not removed", "Moved to Trash", "Removed", "Unknown", "Not started"])
    #expect(shown.records.map(\.canPutBack) == [false, true, false, false, false])
    #expect(shown.records[1].trashURL?.lastPathComponent == "b 2.dmg")
    #expect(shown.trashHeldAllocatedBytes == shown.records[1].allocatedBytes)

    // Reset is no longer refused, and clearing takes the reviewed records with the run.
    let cleared = try run.journal.clearCompletedRuns(requireNoRecovery: true)
    #expect(cleared.removedRuns == 1)
    #expect(try run.journal.records().isEmpty)
}

@Test func aBatchIsMarkedReviewedOnlyOnce() throws {
    let run = try interruptedRun(["a.dmg"], started: ["a.dmg"])
    defer { try? FileManager.default.removeItem(at: run.home) }
    let items = run.review.check(try run.batch())
    try run.review.markReviewed(items, in: run.journal)
    #expect(throws: (any Error).self) { try run.review.markReviewed(items, in: run.journal) }
    #expect(try run.journal.records().count == 2)
}

@Test func aGoneItemWhoseTrashCantBeCheckedStaysUnknown() throws {
    let run = try interruptedRun(["a.dmg"], started: ["a.dmg"])
    defer { try? FileManager.default.removeItem(at: run.home) }
    try FileManager.default.removeItem(at: run.url("a.dmg"))
    let items = CleanupRecoveryReview(trashFolder: { _ in nil }).check(try run.batch())
    #expect(items.map(\.finding) == [.unknown])
    #expect(items.first?.needsConfirmation == true)
}
