import Foundation
import Testing
import CacheDropCore

/// A Downloads-style Trash batch over the files in `root`, as the executor would claim it.
private struct FixtureBatch { let id: UUID; let records: [CleanupRecord] }
private func fixtureBatch(_ root: URL) -> FixtureBatch {
    let rule = CleanupRule(id: "fixture-files", category: .downloads, title: "Files", detail: "", consequence: "", regen: .userFile, action: .trash, locations: [""], owner: nil, contents: ContentsMatch())
    let id = UUID()
    let candidates = Catalog(rules: [rule]).discover(fixture: root).sorted { $0.url.path < $1.url.path }
    return FixtureBatch(id: id, records: candidates.map { CleanupRecord(batchID: id, approvedAt: Date(), candidate: $0, previewOnly: false) })
}
private func recoveryApproval(_ root: URL) async throws -> FixtureBatch { fixtureBatch(root) }
@Test func reopeningIntentWithMissingOriginalRemainsUnresolvedAndReadOnly() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("owned.pdf")
    try Data([7]).write(to: original)
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    do {
        let journal = try SQLiteCleanupJournal(url: url)
        #expect(try journal.claim(batchID: approval.id, records: approval.records))
        var record = try #require(approval.records.first)
        record.state = .intent; record.message = "Intent committed"
        try journal.intent(record)
    }
    let holding = root.appendingPathComponent("owned-holding.pdf")
    try FileManager.default.moveItem(at: original, to: holding)
    let reopened = try SQLiteCleanupJournal(url: url)
    let snapshot = try CleanupRecoverySnapshot(journal: reopened)
    #expect(snapshot.unresolvedCount == 1)
    #expect(snapshot.pendingCount == 0)
    #expect(snapshot.interruptedBatches.first?.records.first?.state == .intent)
    #expect(snapshot.interruptedBatches.first?.records.first?.trashURL == nil)
    _ = try CleanupRecoverySnapshot(journal: reopened)
    #expect(try reopened.records().first?.state == .intent)
    #expect(!FileManager.default.fileExists(atPath: original.path))
    #expect(try Data(contentsOf: holding) == Data([7]))
}

@Test func interruptedBatchKeepsTerminalFactsSeparateFromPendingAndUnknown() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<7 { try Data([UInt8(index)]).write(to: root.appendingPathComponent("file-\(index).pdf")) }
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    do {
        let journal = try SQLiteCleanupJournal(url: url)
        #expect(try journal.claim(batchID: approval.id, records: approval.records))
        let states: [CleanupTargetState] = [.succeeded, .failed, .skipped, .cancelled, .pending, .intent, .unknown]
        for (target, state) in zip(approval.records, states) {
            var record = target
            record.state = state
            try journal.outcome(record)
        }
    }
    let reopened = try SQLiteCleanupJournal(url: url)
    let snapshot = try CleanupRecoverySnapshot(journal: reopened)
    #expect(snapshot.interruptedBatches.count == 1)
    #expect(snapshot.unresolvedCount == 2)
    #expect(snapshot.pendingCount == 1)
    #expect(snapshot.interruptedBatches.first?.records.map(\.state) == [.succeeded, .failed, .skipped, .cancelled, .pending, .intent, .unknown])
    #expect(snapshot.interruptedBatches.first?.records.allSatisfy { $0.trashURL == nil } == true)
    #expect(try reopened.claim(batchID: approval.id, records: approval.records) == false)
}

@Test func readOnlyRecoveryOpenCannotCreateOrClaimAndPreservesRecords() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("owned.pdf"))
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    #expect(throws: CleanupJournalError.self) { try SQLiteCleanupJournal(url: url, readOnly: true) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    do { let writer = try SQLiteCleanupJournal(url: url); #expect(try writer.claim(batchID: approval.id, records: approval.records)) }
    let reader = try SQLiteCleanupJournal(url: url, readOnly: true)
    #expect(try CleanupRecoverySnapshot(journal: reader).pendingCount == 1)
    #expect(throws: CleanupJournalError.self) { try reader.claim(batchID: approval.id, records: approval.records) }
    var changed = try #require(try reader.records().first)
    changed.state = .succeeded
    #expect(throws: CleanupJournalError.self) { try reader.outcome(changed) }
    #expect(try reader.records().first?.state == .pending)
}

@Test func unreadableRecoveryJournalNeverBecomesAnEmptySuccessfulSnapshot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("journal.sqlite")
    let corrupt = Data("owned corrupt database fixture".utf8)
    try corrupt.write(to: url)
    #expect(throws: CleanupJournalError.self) { try SQLiteCleanupJournal(url: url, readOnly: true) }
    #expect(try Data(contentsOf: url) == corrupt)
}

@Test func ordinarySessionChoicesAndCompletedBatchesAreNotRecoveryAuthority() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("owned.pdf"))
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    #expect(try CleanupRecoverySnapshot(journal: journal).interruptedBatches.isEmpty)
    #expect(try journal.claim(batchID: approval.id, records: approval.records))
    var record = try #require(approval.records.first)
    record.state = .succeeded; record.message = "Recorded success; current location not inspected"
    record.trashURL = root.appendingPathComponent("missing-returned-location")
    try journal.outcome(record)
    #expect(try CleanupRecoverySnapshot(journal: SQLiteCleanupJournal(url: url, readOnly: true)).interruptedBatches.isEmpty)
    #expect(try journal.records().first?.state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: record.trashURL!.path))
}
