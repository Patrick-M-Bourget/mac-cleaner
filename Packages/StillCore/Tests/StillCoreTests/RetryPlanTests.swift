import Foundation
import Testing
import StillCore

private struct RetryLocalMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement { .init(allocatedBytes: 4096, locality: .local, cloud: .init(membership: false)) }
}
private struct PartialTrash: TrashOperating {
    let cancellation: CleanupCancellation
    let holding: URL
    func trash(_ target: PlannedTarget) throws -> URL? {
        if target.url.lastPathComponent == "a.pdf" { throw CocoaError(.fileWriteNoPermission) }
        let result = holding.appendingPathComponent(target.url.lastPathComponent)
        try FileManager.default.moveItem(at: target.url, to: result)
        cancellation.cancel()
        return result
    }
}
@Test func partialBatchContinuesThenRetryRechecksOnlyUnfinishedExactIdentities() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRetry-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.pdf", "b.pdf", "c.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let scanner = FolderScanner(supplement: RetryLocalMetadata())
    let original = try await scanner.scan(root), downloads = try DownloadsRoot(url: root)
    var draft = PlanDraft(); _ = draft.selectAll(in: [original], downloads: downloads)
    let approved = try draft.approve(draft.review())
    let holding = root.appendingPathComponent("OwnedHolding")
    try FileManager.default.createDirectory(at: holding, withIntermediateDirectories: true)
    let cancellation = CleanupCancellation()
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal, operation: PartialTrash(cancellation: cancellation, holding: holding), cancellation: cancellation).execute(approved)
    #expect(result.targets.map(\.state) == [.failed, .succeeded, .cancelled])
    try Data([1, 2]).write(to: root.appendingPathComponent("a.pdf"))
    try Data([9]).write(to: root.appendingPathComponent("new.pdf"))
    let fresh = try await scanner.scan(root)
    let retry = RetryPlan.prepare(records: result.targets, scans: [fresh], downloads: downloads)
    #expect(retry.draft.selected.map { $0.url.lastPathComponent } == ["c.pdf"])
    #expect(retry.completedCount == 1)
    #expect(retry.unavailableCount == 1)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("c.pdf").path))
    let newApproval = try retry.draft.approve(retry.draft.review())
    #expect(newApproval.id != approved.id)
    #expect(newApproval.targets.map { $0.url.lastPathComponent } == ["c.pdf"])
    var refined = retry.draft; refined.clear()
    _ = refined.selectAll(in: [fresh], downloads: downloads, restrictingTo: Set(retry.draft.selected.map(\.id)))
    #expect(refined.selected.map { $0.url.lastPathComponent } == ["c.pdf"])
}

private struct CancelAfterIntent: CleanupJournaling {
    let base: SQLiteCleanupJournal
    let cancellation: CleanupCancellation
    func claim(_ batch: CleanupApproval) throws -> Bool { try base.claim(batch) }
    func intent(_ record: CleanupRecord) throws { try base.intent(record); cancellation.cancel() }
    func outcome(_ record: CleanupRecord) throws { try base.outcome(record) }
    func records() throws -> [CleanupRecord] { try base.records() }
}
private struct NoTrash: TrashOperating {
    func trash(_ target: PlannedTarget) throws -> URL? { throw CocoaError(.fileWriteNoPermission) }
}
@Test func cancellationAfterDurableIntentDoesNotStartAnotherNativeOperation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRetry-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("one.pdf"); try Data([1]).write(to: file)
    let scan = try await FolderScanner(supplement: RetryLocalMetadata()).scan(root)
    var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
    let batch = try draft.approve(draft.review()), token = CleanupCancellation()
    let base = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: CancelAfterIntent(base: base, cancellation: token), operation: NoTrash(), cancellation: token).execute(batch)
    #expect(result.targets.map(\.state) == [.cancelled])
    #expect(try base.records().first?.state == .cancelled)
    #expect(try Data(contentsOf: file) == Data([1]))
}

private actor ProgressRecorder {
    var counts: [Int] = []
    func observe(_ progress: CleanupExecutionProgress) { counts.append(progress.resolved) }
}
@Test func progressReportsDurablePerTargetOutcomesWhileUnchangedFailuresContinue() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRetry-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.pdf", "b.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let scan = try await FolderScanner(supplement: RetryLocalMetadata()).scan(root)
    var draft = PlanDraft(); _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
    let batch = try draft.approve(draft.review()), observer = ProgressRecorder()
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal, operation: NoTrash()).execute(batch) { await observer.observe($0) }
    #expect(await observer.counts == [0, 1, 2])
    #expect(result.targets.map(\.state) == [.failed, .failed])
    #expect(try journal.records().map(\.state) == [.failed, .failed])
}
