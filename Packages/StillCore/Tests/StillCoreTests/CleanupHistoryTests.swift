import Foundation
import Testing
import StillCore

/// A Downloads-style Trash batch over the files in `root`, as the executor would claim it.
private struct FixtureBatch { let id: UUID; let records: [CleanupRecord] }
private func fixtureBatch(_ root: URL) -> FixtureBatch {
    let rule = CleanupRule(id: "fixture-files", category: .downloads, title: "Files", detail: "", consequence: "", regen: .userFile, action: .trash, locations: [""], owner: nil, contents: ContentsMatch())
    let id = UUID()
    let candidates = Catalog(rules: [rule]).discover(fixture: root).sorted { $0.url.path < $1.url.path }
    return FixtureBatch(id: id, records: candidates.map { CleanupRecord(batchID: id, approvedAt: Date(), candidate: $0, previewOnly: false) })
}
private func historyApproval(_ root: URL, names: [String]) async throws -> FixtureBatch {
    for name in names { try Data([7]).write(to: root.appendingPathComponent(name)) }
    return fixtureBatch(root)
}
@Test func clearingCompletedRunsPreservesEntireInterruptedBatchAndReplayProtection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHistory-" + UUID().uuidString)
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHistory-" + UUID().uuidString)
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHistory-" + UUID().uuidString)
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
@Test func completedHistorySeparatesPersistedCapacityFromPlannedSizes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let approval = try await historyApproval(root, names: ["local.pdf"])
    let url = root.appendingPathComponent("cleanup.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    #expect(try journal.claim(batchID: approval.id, records: approval.records))
    var record = try #require(approval.records.first); record.state = .succeeded
    try journal.outcome(record)
    let observation = CleanupCapacityObservation(beforeAvailable: 20, afterAvailable: 14, beforeTotal: 100, afterTotal: 100, beforeVolumeID: "owned-volume", afterVolumeID: "owned-volume", beforeMetric: "available", afterMetric: "available", beforeDate: Date(timeIntervalSince1970: 1), afterDate: Date(timeIntervalSince1970: 2))
    try journal.recordCapacity(observation, batchID: approval.id)
    let run = try #require(SQLiteCleanupJournal(url: url, readOnly: true).completedHistory().completedRuns.first)
    #expect(run.capacity?.observedChange == -6)
    #expect(run.plannedLogicalBytes == 1)
}
@Test func deferredCompactionAndByteRetentionPreserveJournalAuthority() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHistory-" + UUID().uuidString)
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
