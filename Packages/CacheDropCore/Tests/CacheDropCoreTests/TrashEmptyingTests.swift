import Foundation
import Testing
@testable import CacheDropCore

// #359, Decision 68: CacheDrop never empties the Trash. It deletes from the Trash only items it moved there itself, and
// only when you ask. Every test uses a temp home whose `.Trash` stands in for the Finder Trash; the real Trash is never
// read or changed.

/// A fixed reading around each item: 4 KB more available after than before.
private let fixtureMeasure: @Sendable (URL) -> CapacitySample? = { _ in
    CapacitySample(available: 1_000_000, total: 10_000_000, volumeID: "fixture", metric: .important, date: Date(timeIntervalSince1970: 0))
}
/// Each item frees 4 KB: every reading after an item's is 4 KB more than the one before it.
private final class FreeingVolume: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func read(_ url: URL) -> CapacitySample? {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return CapacitySample(available: 1_000_000 + Int64(calls / 2) * 4_096, total: 10_000_000, volumeID: "fixture", metric: .important,
                              date: Date(timeIntervalSince1970: Double(calls)))
    }
}

private struct Fixture {
    let home: URL
    let journal: SQLiteCleanupJournal
    let records: [CleanupRecord]
    var trash: URL { home.appendingPathComponent(".Trash") }
    func record(_ name: String) throws -> CleanupRecord { try #require(records.first { $0.originalURL.lastPathComponent == name }) }
    /// Everything in the fixture Trash, by path, with each file's contents.
    func trashListing() throws -> [String: Data] {
        var listing: [String: Data] = [:]
        let enumerator = try #require(FileManager.default.enumerator(atPath: trash.path))
        for case let path as String in enumerator {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: trash.appendingPathComponent(path).path, isDirectory: &isDirectory)
            listing[path] = isDirectory.boolValue ? Data() : try Data(contentsOf: trash.appendingPathComponent(path))
        }
        return listing
    }
    func emptying(measure: @escaping @Sendable (URL) -> CapacitySample? = fixtureMeasure) -> TrashEmptying { TrashEmptying(journal: journal, measure: measure) }
}

/// A fixture home whose `.Trash` holds one file of the user's own, and the Downloads installers a real run moved there.
private func trashedInstallers(_ names: [String] = ["Setup.dmg", "Other.pkg"], dryRun: Bool = false) async throws -> Fixture {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropEmpty-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
    try Data(repeating: 7, count: 500).write(to: home.appendingPathComponent(".Trash/Mine.txt"))
    for name in names { try Data(repeating: 4, count: 3_000).write(to: home.appendingPathComponent("Downloads/" + name)) }
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let executor = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FixtureNothingRunning()), measure: { _ in nil },
                                   trash: FixtureHomeTrash(home: home))
    let result = await executor.execute(CatalogApproval(candidates: candidates, dryRun: dryRun))
    #expect(result.records.count == names.count)
    return Fixture(home: home, journal: journal, records: result.records)
}

@Test func onlyItemsARealRunMovedToTheTrashAndStillThereUnchangedAreOffered() async throws {
    let fixture = try await trashedInstallers()
    defer { try? FileManager.default.removeItem(at: fixture.home) }

    let review = try fixture.emptying().review()

    #expect(Set(review.items.map(\.id)) == Set(fixture.records.map(\.id)))
    // Sizes are the items' recorded sizes, never the whole Trash's.
    #expect(review.bytes == fixture.records.reduce(0) { $0 + $1.recordedBytes })
    #expect(!review.items.contains { $0.originalURL.lastPathComponent == "Mine.txt" })
}

@Test func aDryRunsRecordsOfferNothing() async throws {
    let fixture = try await trashedInstallers(dryRun: true)
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    #expect(try fixture.emptying().review().items.isEmpty)
}

@Test func anItemPutBackGoneFromTheTrashOrChangedThereIsNotOffered() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg", "Other.pkg", "Gone.zip"])
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    #expect(TrashPutBack(journal: fixture.journal).putBack(try fixture.record("Setup.dmg")) == .restored(try fixture.record("Setup.dmg").originalURL))
    // The user emptied it in Finder, or dragged it out.
    try FileManager.default.removeItem(at: fixture.trash.appendingPathComponent("Gone.zip"))
    // Another item of the same name took its place.
    let other = fixture.trash.appendingPathComponent("Other.pkg")
    try FileManager.default.removeItem(at: other)
    try Data(repeating: 1, count: 3_000).write(to: other)

    #expect(try fixture.emptying().review().items.isEmpty)
}

@Test func emptyingDeletesOnlyCacheDropsItemsAndHistoryRecordsIt() async throws {
    let fixture = try await trashedInstallers()
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    let volume = FreeingVolume()
    let emptying = fixture.emptying(measure: volume.read)

    let result = emptying.empty(try emptying.review().items, dryRun: false)

    #expect(result.records.count == 2 && result.records.allSatisfy { $0.state == .succeeded })
    #expect(result.records.allSatisfy { $0.outcomeTitle == "Deleted from the Trash" })
    // The user's own trashed file is untouched; nothing else in the Trash changed.
    #expect(try fixture.trashListing() == ["Mine.txt": Data(repeating: 7, count: 500)])
    // Freed space is measured around each item, as a cleanup measures it.
    #expect(result.measuredFreedBytes == Int64(2 * 4_096))
    let history = try fixture.journal.completedHistory()
    let run = try #require(history.completedRuns.first { $0.isEmptyFromTrash })
    #expect(run.title == "Emptied from the Trash · 2 items")
    #expect(run.measuredFreedBytes == Int64(2 * 4_096))
    // #569: its History row leads with that freed space, as a cleanup's does.
    #expect(run.headline == CleanupHistoryRun.Headline(bytes: Int64(2 * 4_096), note: "Freed"))
    #expect(history.emptiedIDs == Set(fixture.records.map(\.id)))
    let trashRun = try #require(history.completedRuns.first { $0.records.contains { $0.id == fixture.records[0].id } })
    #expect(trashRun.trashHeldAllocatedBytes == 0, "What was emptied is no longer held in the Trash")
    #expect(trashRun.emptiedIDs == Set(fixture.records.map(\.id)))
    // Gone for good: nothing is offered again, and it can't be put back.
    #expect(try emptying.review().items.isEmpty)
    #expect(TrashPutBack(journal: fixture.journal).putBack(fixture.records[0]) == .refused(.notInTrash))
}

@Test func oneItemReadsAsOneItem() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg"])
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    let emptying = fixture.emptying()
    _ = emptying.empty(try emptying.review().items, dryRun: false)
    #expect(try fixture.journal.completedHistory().completedRuns.first { $0.isEmptyFromTrash }?.title == "Emptied from the Trash · 1 item")
}

@Test func anItemThatFailsTheChecksWhenEmptyingIsSkippedLeftAloneAndSaysWhy() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg", "Other.pkg", "Gone.zip", "Back.dmg"])
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    let emptying = fixture.emptying()
    let offered = try emptying.review().items
    #expect(offered.count == 4)
    // Between opening the sheet and Empty: one changed, one left the Trash, one was put back.
    let other = fixture.trash.appendingPathComponent("Other.pkg")
    let handle = try FileHandle(forWritingTo: other)
    try handle.seekToEnd(); try handle.write(contentsOf: Data([1])); try handle.close()
    var later = [timeval(tv_sec: 2_000_000_000, tv_usec: 0), timeval(tv_sec: 2_000_000_000, tv_usec: 0)]
    #expect(utimes(other.path, &later) == 0)
    try FileManager.default.moveItem(at: fixture.trash.appendingPathComponent("Gone.zip"), to: fixture.home.appendingPathComponent("Gone.zip"))
    #expect(TrashPutBack(journal: fixture.journal).putBack(try fixture.record("Back.dmg")) == .restored(try fixture.record("Back.dmg").originalURL))
    let before = try fixture.trashListing()

    let result = emptying.empty(offered, dryRun: false)

    func outcome(_ name: String) throws -> CleanupRecord { try #require(result.records.first { $0.originalURL.lastPathComponent == name }) }
    #expect(try outcome("Setup.dmg").state == .succeeded)
    #expect(try outcome("Other.pkg").state == .skipped && outcome("Other.pkg").message == EmptyRefusal.changed.reason)
    #expect(try outcome("Gone.zip").state == .skipped && outcome("Gone.zip").message == EmptyRefusal.notInTrash.reason)
    #expect(try outcome("Back.dmg").state == .skipped && outcome("Back.dmg").message == EmptyRefusal.alreadyPutBack.reason)
    var expected = before; expected["Setup.dmg"] = nil
    #expect(try fixture.trashListing() == expected, "Skipped items are left alone")
    #expect(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("Gone.zip").path))
    #expect(try fixture.journal.completedHistory().completedRuns.first { $0.isEmptyFromTrash }?.title == "Emptied from the Trash · 1 item")

    // Emptied once, never again.
    let again = emptying.empty([try fixture.record("Setup.dmg")], dryRun: false)
    #expect(again.records.first?.message == EmptyRefusal.alreadyEmptied.reason)
}

@Test func onlyItemsMovedToTheTrashCanBeEmptiedAndARefusalWritesNothing() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg"])
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    var preview = try fixture.record("Setup.dmg"); preview.dryRun = true
    var outside = try fixture.record("Setup.dmg"); outside.trashURL = fixture.home.appendingPathComponent("Downloads/Elsewhere.dmg")
    let count = try fixture.journal.records().count

    let result = fixture.emptying().empty([preview, outside], dryRun: false)

    #expect(result.records.isEmpty)
    #expect(try fixture.journal.records().count == count)
    #expect(FileManager.default.fileExists(atPath: fixture.trash.appendingPathComponent("Setup.dmg").path))
}

@Test func aDryRunChecksEachItemAndChangesNothing() async throws {
    let fixture = try await trashedInstallers()
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    let emptying = fixture.emptying()
    let before = try fixture.trashListing()

    let result = emptying.empty(try emptying.review().items, dryRun: true)

    #expect(result.dryRun && result.measuredFreedBytes == nil)
    #expect(result.records.allSatisfy { $0.wasDryRun && $0.outcomeTitle == "Would delete from the Trash" })
    #expect(try fixture.trashListing() == before)
    let history = try fixture.journal.completedHistory()
    #expect(history.completedRuns.first { $0.isEmptyFromTrash }?.title == "Dry run · Nothing changed")
    #expect(history.emptiedIDs.isEmpty)
    // Still offered, and still put back.
    #expect(try emptying.review().items.count == 2)
    #expect(TrashPutBack(journal: fixture.journal).putBack(fixture.records[0]) == .restored(fixture.records[0].originalURL))
}

/// Without Full Disk Access the Trash can be searched but not listed; emptying, like Put back, only searches it.
@Test func emptyingWorksWhenTheTrashCanBeSearchedButNotRead() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg"])
    try FileManager.default.setAttributes([.posixPermissions: 0o311], ofItemAtPath: fixture.trash.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.trash.path); try? FileManager.default.removeItem(at: fixture.home) }
    let emptying = fixture.emptying()

    let offered = try emptying.review().items
    #expect(offered.count == 1)
    #expect(emptying.empty(offered, dryRun: false).records.first?.state == .succeeded)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.trash.path)
    #expect(try fixture.trashListing() == ["Mine.txt": Data(repeating: 7, count: 500)])
}

@Test func anItemIsFoundByItsRecordedTrashLocationOnly() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg"])
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    // Moved within the Trash, it is no longer where CacheDrop recorded it, so it isn't offered.
    let folder = fixture.trash.appendingPathComponent("Setup.dmg")
    let renamed = fixture.trash.appendingPathComponent("Setup 2.dmg")
    try FileManager.default.moveItem(at: folder, to: renamed)
    #expect(try fixture.emptying().review().items.isEmpty, "Found by its recorded location only")
    try FileManager.default.moveItem(at: renamed, to: folder)
    #expect(try fixture.emptying().review().items.count == 1)
}

/// An emptying stopped before its outcome was recorded is an interrupted cleanup: until it is reviewed its items aren't
/// offered, and the review checks the Trash, where an item still there reads as not removed and is offered again.
@Test func anInterruptedEmptyingIsReviewedLikeAnyInterruptedCleanup() async throws {
    let fixture = try await trashedInstallers(["Setup.dmg"])
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    let original = try fixture.record("Setup.dmg")
    // A journal that loses the outcome: the record stays at intent.
    let losing = OutcomeLosingJournal(fixture.journal)
    _ = TrashEmptying(journal: losing, measure: fixtureMeasure).empty([original], dryRun: false)
    let snapshot = try CleanupRecoverySnapshot(journal: fixture.journal)
    #expect(snapshot.unresolvedCount == 1)
    #expect(try fixture.emptying().review().items.isEmpty)

    let batch = try #require(snapshot.interruptedBatches.first)
    let items = CleanupRecoveryReview(trashFolder: { _ in fixture.trash }).check(batch)
    #expect(items.first?.finding == .gone, "The emptying ran: the item is gone from the Trash")
    try CleanupRecoveryReview().markReviewed(items, in: fixture.journal)
    #expect(try fixture.journal.completedHistory().emptiedIDs == [original.id])
}

/// Records pending and intent, then fails to record the outcome, as a crash would leave it.
private final class OutcomeLosingJournal: CleanupJournaling, @unchecked Sendable {
    let base: SQLiteCleanupJournal
    init(_ base: SQLiteCleanupJournal) { self.base = base }
    func claim(batchID: UUID, records: [CleanupRecord]) throws -> Bool { try base.claim(batchID: batchID, records: records) }
    func intent(_ record: CleanupRecord) throws { try base.intent(record) }
    func outcome(_ record: CleanupRecord) throws { throw CleanupJournalError.unavailable }
    func records() throws -> [CleanupRecord] { try base.records() }
    func append(_ records: [CleanupRecord]) throws { try base.append(records) }
}
