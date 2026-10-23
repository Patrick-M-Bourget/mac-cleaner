import Foundation
import Testing
import StillCore

private func historyApproval(_ root: URL, names: [String]) async throws -> CleanupApproval {
    for name in names { try Data([7]).write(to: root.appendingPathComponent(name)) }
    let scan = try await FolderScanner().scan(root)
    var draft = PlanDraft()
    _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
    return try draft.approve(draft.review())
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
    #expect(try journal.claim(completed))
    var terminal = CleanupRecord(batch: completed, target: try #require(completed.targets.first))
    terminal.state = .succeeded
    try journal.outcome(terminal)
    #expect(try journal.claim(interrupted))
    for (target, state) in zip(interrupted.targets, [CleanupTargetState.succeeded, .intent]) {
        var record = CleanupRecord(batch: interrupted, target: target); record.state = state
        try journal.outcome(record)
    }
    #expect(try journal.completedHistory().completedRuns.count == 1)
    let cleared = try journal.clearCompletedRuns()
    #expect(cleared.removedRecords == 1)
    let reopened = try SQLiteCleanupJournal(url: url)
    #expect(try reopened.records().map(\.state) == [.succeeded, .intent])
    #expect(try reopened.claim(completed) == false)
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
    #expect(try second.claim(approved))
    #expect(throws: CleanupJournalError.self) { try first.clearCompletedRuns(requireNoRecovery: true) }
    var outcome = CleanupRecord(batch: approved, target: try #require(approved.targets.first))
    outcome.state = .succeeded
    outcome.message = String(repeating: "owned fixture ", count: 80_000)
    try second.outcome(outcome)
    #expect(try first.completedHistory().completedRuns.first?.usesApprovalDate == false)
    let before = try first.storageBytes()
    _ = try first.clearCompletedRuns(requireNoRecovery: true)
    let compacted = try first.compact()
    #expect(compacted.completed)
    #expect(compacted.afterBytes < before)
    #expect(try SQLiteCleanupJournal(url: url).records().isEmpty)
    #expect(try first.claim(approved) == false)
    #expect(try Data(contentsOf: files.appendingPathComponent("original.pdf")) == Data([7]))
}
@Test func retentionUsesRecordedOutcomeAgeAndProtectsUnresolved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let approved = try await historyApproval(root, names: ["old.pdf"])
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
    #expect(try journal.claim(approved))
    var record = CleanupRecord(batch: approved, target: try #require(approved.targets.first))
    record.state = .cancelled; record.outcomeRecordedAt = Date(timeIntervalSince1970: 0)
    try journal.outcome(record)
    #expect(try journal.retainCompletedRuns(now: Date(timeIntervalSince1970: 100 * 86400)).removedRuns == 1)
    #expect(try journal.claim(approved) == false)
}
