import Foundation
import Testing
@testable import CacheDropCore

/// A Downloads-style Trash batch over the files in `root`, as the executor would claim it.
private struct FixtureBatch { let id: UUID; let records: [CleanupRecord] }
private func fixtureBatch(_ root: URL) -> FixtureBatch {
    let id = UUID()
    return FixtureBatch(id: id, records: fixtureCandidates(root, action: .trash).map { CleanupRecord(batchID: id, approvedAt: Date(), candidate: $0, dryRun: false) })
}
/// The files in `root` as a rule with `action` finds them: Downloads-style user files for the Trash, a cache to delete.
private func fixtureCandidates(_ root: URL, action: CleanupAction) -> [Candidate] {
    let rule = CleanupRule(id: "fixture-" + action.rawValue, category: action == .trash ? .downloads : .developer, title: "Files", detail: "", consequence: "",
                           regen: action == .trash ? .userFile : .cache, action: action, locations: [""], owner: nil, contents: ContentsMatch())
    return Catalog(rules: [rule]).discover(fixture: root).sorted { $0.url.path < $1.url.path }
}
private func historyApproval(_ root: URL, names: [String]) async throws -> FixtureBatch {
    for name in names { try Data([7]).write(to: root.appendingPathComponent(name)) }
    return fixtureBatch(root)
}
@Test func clearingCompletedRunsPreservesEntireInterruptedBatchAndReplayProtection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second")
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
    let completed = try await historyApproval(first, names: ["completed.pdf"])
    let interrupted = try await historyApproval(second, names: ["known.pdf", "unknown.pdf"])
    let url = root.appendingPathComponent("cleanup.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    #expect(try journal.claim(batchID: completed.id, records: completed.records))
    var terminal = try #require(completed.records.first)
    terminal.state = .succeeded
    try journal.outcome(terminal)
    #expect(try journal.claim(batchID: interrupted.id, records: interrupted.records))
    for (target, state) in zip(interrupted.records, [CleanupTargetState.succeeded, .intent]) {
        var record = target; record.state = state
        try journal.outcome(record)
    }
    #expect(try journal.completedHistory().completedRuns.count == 1)
    let cleared = try journal.clearCompletedRuns()
    #expect(cleared.removedRecords == 1)
    let reopened = try SQLiteCleanupJournal(url: url)
    #expect(try reopened.records().map(\.state) == [.succeeded, .intent])
    #expect(try reopened.claim(batchID: completed.id, records: completed.records) == false)
    #expect(try Data(contentsOf: first.appendingPathComponent("completed.pdf")) == Data([7]))
}
@Test func resetClearReadsFreshJournalAndCompactionPreservesRecoveryAndReplay() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = root.appendingPathComponent("files")
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false)
    let approved = try await historyApproval(files, names: ["original.pdf"])
    let url = root.appendingPathComponent("cleanup.sqlite")
    let first = try SQLiteCleanupJournal(url: url)
    #expect(try first.completedHistory().protectedRecordCount == 0)
    let second = try SQLiteCleanupJournal(url: url)
    #expect(try second.claim(batchID: approved.id, records: approved.records))
    #expect(throws: CleanupJournalError.self) { try first.clearCompletedRuns(requireNoRecovery: true) }
    var outcome = try #require(approved.records.first)
    outcome.state = .succeeded
    outcome.message = String(repeating: "owned fixture ", count: 80_000)
    try second.outcome(outcome)
    #expect(try first.completedHistory().completedRuns.first?.usesApprovalDate == false)
    #expect(throws: CleanupJournalError.self) { try first.clearCompletedRuns(requireNoRecovery: true, operationInProgress: true) }
    #expect(try first.records().count == 1)
    let before = try first.storageBytes()
    _ = try first.clearCompletedRuns(requireNoRecovery: true)
    let compacted = try first.compact()
    #expect(compacted.completed)
    #expect(compacted.afterBytes < before)
    print("Owned history compaction: before-clear=\(before), before-vacuum=\(compacted.beforeBytes), after=\(compacted.afterBytes) bytes")
    #expect(try SQLiteCleanupJournal(url: url).records().isEmpty)
    #expect(try first.claim(batchID: approved.id, records: approved.records) == false)
    #expect(try Data(contentsOf: files.appendingPathComponent("original.pdf")) == Data([7]))
}
@Test func retentionUsesRecordedOutcomeAgeAndProtectsUnresolved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let approved = try await historyApproval(root, names: ["old.pdf"])
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
    #expect(try journal.claim(batchID: approved.id, records: approved.records))
    var record = try #require(approved.records.first)
    record.state = .cancelled; record.outcomeRecordedAt = Date(timeIntervalSince1970: 0)
    try journal.outcome(record)
    #expect(try journal.retainCompletedRuns(now: Date(timeIntervalSince1970: 100 * 86400)).removedRuns == 1)
    #expect(try journal.claim(batchID: approved.id, records: approved.records) == false)
}
@Test func completedHistoryShowsThePlannedSizeResultsShows() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let approval = try await historyApproval(root, names: ["local.pdf"])
    let url = root.appendingPathComponent("cleanup.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    #expect(try journal.claim(batchID: approval.id, records: approval.records))
    var record = try #require(approval.records.first); record.state = .succeeded
    try journal.outcome(record)
    let run = try #require(SQLiteCleanupJournal(url: url, readOnly: true).completedHistory().completedRuns.first)
    // #312: History shows the size Results showed for the same items, allocated where known.
    #expect(record.allocatedBytes.map { $0 > 1 } == true)
    #expect(run.plannedBytes == record.allocatedBytes)
}
/// #416: an observation built from two readings puts each in its own half.
@Test func capacityObservationFromTwoReadingsKeepsEachInItsHalf() {
    let before = CapacitySample(available: 20, total: 100, volumeID: "before-volume", metric: .important, date: Date(timeIntervalSince1970: 1))
    let after = CapacitySample(available: 14, total: 101, volumeID: "after-volume", metric: .available, date: Date(timeIntervalSince1970: 2))
    let observation = CleanupCapacityObservation(from: before, to: after)
    #expect(observation.beforeAvailable == 20 && observation.afterAvailable == 14)
    #expect(observation.beforeTotal == 100 && observation.afterTotal == 101)
    #expect(observation.beforeVolumeID == "before-volume" && observation.afterVolumeID == "after-volume")
    #expect(observation.beforeMetric == "important" && observation.afterMetric == "available")
    #expect(observation.beforeDate == Date(timeIntervalSince1970: 1) && observation.afterDate == Date(timeIntervalSince1970: 2))
}
/// #416: continuing an observation starts from its after half, as the settle line does from a run's last reading.
@Test func capacityObservationContinuedStartsFromItsAfterHalf() {
    let run = CleanupCapacityObservation(beforeAvailable: 20, afterAvailable: 14, beforeTotal: 100, afterTotal: 101, beforeVolumeID: "first-volume", afterVolumeID: "run-volume",
                                         beforeMetric: "available", afterMetric: "important", beforeDate: Date(timeIntervalSince1970: 1), afterDate: Date(timeIntervalSince1970: 2))
    let now = CapacitySample(available: 30, total: 102, volumeID: "now-volume", metric: .available, date: Date(timeIntervalSince1970: 3))
    let settled = run.continued(to: now)
    #expect(settled.beforeAvailable == 14 && settled.afterAvailable == 30)
    #expect(settled.beforeTotal == 101 && settled.afterTotal == 102)
    #expect(settled.beforeVolumeID == "run-volume" && settled.afterVolumeID == "now-volume")
    #expect(settled.beforeMetric == "important" && settled.afterMetric == "available")
    #expect(settled.beforeDate == Date(timeIntervalSince1970: 2) && settled.afterDate == Date(timeIntervalSince1970: 3))
}
/// #433: History measures freed space as Results does, around each removed item; a Trash move frees nothing yet, so it
/// neither counts nor makes the run's figure unknown.
@Test func historyMeasuresFreedSpaceAroundRemovedItemsAndLeavesTrashMovesOut() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    let caches = root.appendingPathComponent("caches"), downloads = root.appendingPathComponent("downloads")
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([7]).write(to: caches.appendingPathComponent("cache.bin"))
    try Data([7]).write(to: downloads.appendingPathComponent("setup.dmg"))
    let id = UUID()
    let records = (fixtureCandidates(caches, action: .delete) + fixtureCandidates(downloads, action: .trash))
        .map { CleanupRecord(batchID: id, approvedAt: Date(), candidate: $0, dryRun: false) }
    let url = root.appendingPathComponent("cleanup.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    #expect(try journal.claim(batchID: id, records: records))
    for var record in records {
        record.state = .succeeded
        if record.cleanupAction == .delete {
            record.itemCapacity = CleanupCapacityObservation(from: CapacitySample(available: 14, total: 100, volumeID: "v", metric: .important, date: Date(timeIntervalSince1970: 1)),
                                                            to: CapacitySample(available: 20, total: 100, volumeID: "v", metric: .important, date: Date(timeIntervalSince1970: 2)))
        }
        try journal.outcome(record)
    }
    let run = try #require(SQLiteCleanupJournal(url: url, readOnly: true).completedHistory().completedRuns.first)
    #expect(run.measuredFreedBytes == 6)
    #expect(!run.records.movedOnlyToTrash)
}
/// #433: a run that only moved items to the Trash shows no measured freed space, in History as in Results (Decision 66).
@Test func aRunThatOnlyMovedItemsToTheTrashShowsNoMeasuredFreedSpace() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let approval = try await historyApproval(root, names: ["setup.dmg"])
    var record = try #require(approval.records.first)
    #expect(!approval.records.movedOnlyToTrash, "Nothing has moved yet")
    record.state = .succeeded
    #expect([record].movedOnlyToTrash)
}
/// #433: records journaled before the whole-run reading was dropped still carry its key; they still decode.
@Test func aRecordWithTheDroppedWholeRunReadingStillDecodes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = try #require(try await historyApproval(root, names: ["old.pdf"]).records.first)
    var payload = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    let reading = CleanupCapacityObservation(from: CapacitySample(available: 20, total: 100, volumeID: "v", metric: .available, date: Date(timeIntervalSince1970: 1)),
                                             to: CapacitySample(available: 14, total: 100, volumeID: "v", metric: .available, date: Date(timeIntervalSince1970: 2)))
    payload["capacityObservation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reading))
    let decoded = try JSONDecoder().decode(CleanupRecord.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(decoded.id == record.id)
}
@Test func deferredCompactionAndByteRetentionPreserveJournalAuthority() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let approval = try await historyApproval(root, names: ["kept.pdf"])
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
    #expect(try journal.claim(batchID: approval.id, records: approval.records))
    #expect(try journal.retainCompletedRuns(maximumBytes: 0).protectedRecords == 1)
    #expect(try journal.records().count == 1)
    let compacted = try journal.compact(timeout: 0)
    #expect(compacted.completed == false)
    #expect(compacted.beforeBytes == compacted.afterBytes)
    var record = try #require(approval.records.first)
    record.state = .failed; try journal.outcome(record)
    #expect(try journal.retainCompletedRuns(maximumBytes: 0).removedRecords == 1)
    #expect(try journal.claim(batchID: approval.id, records: approval.records) == false)
}
/// #569: a History row leads with the figure Results leads with, the measured freed space, noted "Freed"; a run that only
/// moved items to the Trash leads with what went there, noted "In Trash"; a dry run with what it would affect.
@Test func aHistoryRowLeadsWithTheMeasuredFreedSpaceResultsLeadsWith() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHistory-" + UUID().uuidString)
    let caches = root.appendingPathComponent("caches"), downloads = root.appendingPathComponent("downloads")
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 7, count: 5_000).write(to: caches.appendingPathComponent("cache.bin"))
    try Data(repeating: 7, count: 5_000).write(to: downloads.appendingPathComponent("setup.dmg"))
    let id = UUID()
    func succeeded(_ candidates: [Candidate], freed: Int64?, dryRun: Bool = false) -> [CleanupRecord] {
        candidates.map {
            var record = CleanupRecord(batchID: id, approvedAt: Date(), candidate: $0, dryRun: dryRun)
            record.state = .succeeded
            if let freed {
                record.itemCapacity = CleanupCapacityObservation(from: CapacitySample(available: 1_000, total: 100_000, volumeID: "v", metric: .important, date: Date(timeIntervalSince1970: 1)),
                                                                to: CapacitySample(available: 1_000 + freed, total: 100_000, volumeID: "v", metric: .important, date: Date(timeIntervalSince1970: 2)))
            }
            return record
        }
    }
    let cleaned = CleanupHistoryRun(id: id, records: succeeded(fixtureCandidates(caches, action: .delete), freed: 3_000))
    #expect(cleaned.plannedBytes > 3_000, "The estimate differs from what was measured")
    #expect(cleaned.headline == CleanupHistoryRun.Headline(bytes: 3_000, note: "Freed"))

    let unmeasured = CleanupHistoryRun(id: id, records: succeeded(fixtureCandidates(caches, action: .delete), freed: nil))
    #expect(unmeasured.headline == CleanupHistoryRun.Headline(bytes: nil, note: "Freed"))

    let trashed = CleanupHistoryRun(id: id, records: succeeded(fixtureCandidates(downloads, action: .trash), freed: nil))
    #expect(trashed.headline == CleanupHistoryRun.Headline(bytes: trashed.plannedBytes, note: "In Trash"))

    let preview = CleanupHistoryRun(id: id, records: succeeded(fixtureCandidates(caches, action: .delete), freed: nil, dryRun: true))
    #expect(preview.headline == CleanupHistoryRun.Headline(bytes: preview.plannedBytes, note: "Dry run"))
}
