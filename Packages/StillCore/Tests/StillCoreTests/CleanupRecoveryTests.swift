import Foundation
import Testing
import StillCore

private func recoveryApproval(_ root: URL) async throws -> CleanupApproval {
    let scan = try await FolderScanner().scan(root)
    var plan = PlanDraft()
    let downloads = try DownloadsRoot(url: root)
    _ = plan.selectAll(in: [scan], downloads: downloads)
    return try plan.approve(plan.review())
}
@Test func reopeningIntentWithMissingOriginalRemainsUnresolvedAndReadOnly() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("owned.pdf")
    try Data([7]).write(to: original)
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    do {
        let journal = try SQLiteCleanupJournal(url: url)
        #expect(try journal.claim(approval))
        var record = CleanupRecord(batch: approval, target: try #require(approval.targets.first))
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<7 { try Data([UInt8(index)]).write(to: root.appendingPathComponent("file-\(index).pdf")) }
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    do {
        let journal = try SQLiteCleanupJournal(url: url)
        #expect(try journal.claim(approval))
        let states: [CleanupTargetState] = [.succeeded, .failed, .skipped, .cancelled, .pending, .intent, .unknown]
        for (target, state) in zip(approval.targets, states) {
            var record = CleanupRecord(batch: approval, target: target)
            record.state = state
            try journal.outcome(record)
        }
    }
    let reopened = try SQLiteCleanupJournal(url: url)
    let snapshot = try CleanupRecoverySnapshot(journal: reopened)
    #expect(snapshot.interruptedBatches.count == 1)
    #expect(snapshot.unresolvedCount == 2)
    #expect(snapshot.pendingCount == 1)
    #expect(snapshot.knownResultCount == 4)
    #expect(snapshot.interruptedBatches.first?.records.map(\.state) == [.succeeded, .failed, .skipped, .cancelled, .pending, .intent, .unknown])
    #expect(snapshot.interruptedBatches.first?.records.allSatisfy { $0.trashURL == nil } == true)
    #expect(try reopened.claim(approval) == false)
}

@Test func readOnlyRecoveryOpenCannotCreateOrClaimAndPreservesRecords() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("owned.pdf"))
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    #expect(throws: CleanupJournalError.self) { try SQLiteCleanupJournal(url: url, readOnly: true) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    do { let writer = try SQLiteCleanupJournal(url: url); #expect(try writer.claim(approval)) }
    let reader = try SQLiteCleanupJournal(url: url, readOnly: true)
    #expect(try CleanupRecoverySnapshot(journal: reader).pendingCount == 1)
    #expect(throws: CleanupJournalError.self) { try reader.claim(approval) }
    var changed = try #require(try reader.records().first)
    changed.state = .succeeded
    #expect(throws: CleanupJournalError.self) { try reader.outcome(changed) }
    #expect(try reader.records().first?.state == .pending)
}

@Test func unreadableRecoveryJournalNeverBecomesAnEmptySuccessfulSnapshot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("journal.sqlite")
    let corrupt = Data("owned corrupt database fixture".utf8)
    try corrupt.write(to: url)
    #expect(throws: CleanupJournalError.self) { try SQLiteCleanupJournal(url: url, readOnly: true) }
    #expect(try Data(contentsOf: url) == corrupt)
}

@Test func ordinarySessionChoicesAndCompletedBatchesAreNotRecoveryAuthority() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRecovery-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("owned.pdf"))
    let approval = try await recoveryApproval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    #expect(try CleanupRecoverySnapshot(journal: journal).interruptedBatches.isEmpty)
    #expect(try journal.claim(approval))
    var record = CleanupRecord(batch: approval, target: try #require(approval.targets.first))
    record.state = .succeeded; record.message = "Recorded success; current location not inspected"
    record.trashURL = root.appendingPathComponent("missing-returned-location")
    try journal.outcome(record)
    #expect(try CleanupRecoverySnapshot(journal: SQLiteCleanupJournal(url: url, readOnly: true)).interruptedBatches.isEmpty)
    #expect(try journal.records().first?.state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: record.trashURL!.path))
}
