import Foundation
import Testing
import StillCore

private struct ExecutorLocalMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        MetadataSupplement(allocatedBytes: 4096, locality: .local, cloud: CloudMetadata(membership: false))
    }
}
private func approval(_ root: URL) async throws -> CleanupApproval {
    let scan = try await FolderScanner(supplement: ExecutorLocalMetadata()).scan(root)
    var draft = PlanDraft()
    _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
    return try draft.approve(draft.review())
}
private struct RefusingTrash: TrashOperating {
    func trash(_ target: PlannedTarget) throws -> URL? { throw CocoaError(.fileWriteNoPermission) }
}
@Test func changedApprovedFileIsSkippedAndNativeFailurePreservesOtherOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let changed = root.appendingPathComponent("changed.pdf"), unchanged = root.appendingPathComponent("unchanged.pdf")
    try Data([1]).write(to: changed); try Data([2]).write(to: unchanged)
    let batch = try await approval(root)
    try Data([1, 2, 3]).write(to: changed)
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal, operation: RefusingTrash()).execute(batch)
    #expect(result.targets.map(\.state) == [.skipped, .failed])
    #expect(try Data(contentsOf: changed) == Data([1, 2, 3]))
    #expect(try Data(contentsOf: unchanged) == Data([2]))
    #expect(result.trashHeldAllocatedBytes == 0)
    let reopened = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    #expect(try reopened.records().map(\.state) == [.skipped, .failed])
    let replay = await TrashExecutor(journal: reopened, operation: RefusingTrash()).execute(batch)
    #expect(replay.rejectedReplay)
}

@Test func approvedScopeReplacementAndSymlinkTargetsNeverMutateSubstitutes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("Nested/file.pdf")
    try Data([1]).write(to: target)
    let batch = try await approval(root.appendingPathComponent("Nested"))
    try FileManager.default.moveItem(at: root.appendingPathComponent("Nested"), to: root.appendingPathComponent("Old"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
    try Data([9]).write(to: target)
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal).execute(batch)
    #expect(result.targets.map(\.state) == [.skipped])
    #expect(try Data(contentsOf: target) == Data([9]))
    #expect(try Data(contentsOf: root.appendingPathComponent("Old/file.pdf")) == Data([1]))
}

@Test func accessLossAfterApprovalDoesNotMoveOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("private.pdf")
    try Data([1]).write(to: target)
    let batch = try await approval(root)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: target.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path) }
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal).execute(batch)
    #expect(result.targets.map(\.state) == [.skipped])
    #expect(FileManager.default.fileExists(atPath: target.path))
}

@Test func nativeTrashRecordsOnlyExactApprovedPathsAndReturnedLocation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("owned-\(UUID()).pdf")
    try Data([1, 2, 3]).write(to: target)
    let batch = try await approval(root)
    let notApproved = root.appendingPathComponent("new.pdf")
    try Data([8]).write(to: notApproved)
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal).execute(batch)
    #expect(result.targets.map(\.state) == [.succeeded])
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(try Data(contentsOf: notApproved) == Data([8]))
    let record = try #require(result.targets.first)
    let returned = try #require(record.trashURL)
    #expect(try Data(contentsOf: returned) == Data([1, 2, 3]))
    // Delete only this API-returned owned fixture, after proving the exact approved resource identity.
    let values = try returned.resourceValues(forKeys: [.fileResourceIdentifierKey])
    #expect(values.fileResourceIdentifier != nil)
    var info = stat()
    guard lstat(returned.path, &info) == 0, "\(info.st_dev):\(info.st_ino)" == record.resourceID else { throw CleanupValidationError.changedOrProtected }
    try FileManager.default.removeItem(at: returned)
    #expect(try journal.records().first?.trashURL == returned)
}

private struct FailOutcomeJournal: CleanupJournaling {
    let base: SQLiteCleanupJournal
    func claim(_ batch: CleanupApproval) throws -> Bool { try base.claim(batch) }
    func intent(_ record: CleanupRecord) throws { try base.intent(record) }
    func outcome(_ record: CleanupRecord) throws { throw CleanupJournalError.unavailable }
    func records() throws -> [CleanupRecord] { try base.records() }
}
@Test func failedOutcomeCommitLeavesDurableUnresolvedIntentAndStopsNextTarget() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.pdf", "b.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let batch = try await approval(root)
    let url = root.appendingPathComponent("journal.sqlite")
    let journal = try SQLiteCleanupJournal(url: url)
    let result = await TrashExecutor(journal: FailOutcomeJournal(base: journal), operation: RefusingTrash()).execute(batch)
    #expect(result.targets.map(\.state) == [.unknown, .cancelled])
    #expect(result.journalFailure != nil)
    let recovered = try SQLiteCleanupJournal(url: url).records()
    #expect(recovered.map(\.state) == [.intent, .pending])
    #expect(recovered.first?.scopeURL == batch.targets.first?.scopeCanonicalURL)
    #expect(recovered.first?.scopeResourceID == batch.targets.first?.scopeResourceID)
}

private struct StopAfterFirst: TrashOperating {
    let cancellation: CleanupCancellation
    func trash(_ target: PlannedTarget) throws -> URL? { cancellation.cancel(); throw CocoaError(.fileWriteNoPermission) }
}
@Test func cancellationStopsNewTargetsAndPersistsNotStartedOutcome() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.pdf", "b.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let batch = try await approval(root), cancellation = CleanupCancellation()
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal, operation: StopAfterFirst(cancellation: cancellation), cancellation: cancellation).execute(batch)
    #expect(result.targets.map(\.state) == [.failed, .cancelled])
    #expect(try journal.records().map(\.state) == [.failed, .cancelled])
}

private struct SwapBeforeNativeTrash: TrashOperating {
    let keeper: URL
    func trash(_ target: PlannedTarget) throws -> URL? {
        try FileManager.default.moveItem(at: target.url, to: target.url.deletingLastPathComponent().appendingPathComponent("retained.pdf"))
        try FileManager.default.createSymbolicLink(at: target.url, withDestinationURL: keeper)
        return try NativeTrashOperation().trash(target)
    }
}
@Test func nativeBoundaryRejectsTargetSymlinkSwapWithoutMovingSubstitute() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("approved.pdf")
    try Data([1]).write(to: target)
    let batch = try await approval(root)
    let keeper = root.appendingPathComponent("not-approved.pdf")
    try Data([9]).write(to: keeper)
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal, operation: SwapBeforeNativeTrash(keeper: keeper)).execute(batch)
    #expect(result.targets.map(\.state) == [.skipped])
    #expect(try Data(contentsOf: keeper) == Data([9]))
    #expect(try Data(contentsOf: root.appendingPathComponent("retained.pdf")) == Data([1]))
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == keeper.path)
}

private struct MoveThenThrow: TrashOperating {
    func trash(_ target: PlannedTarget) throws -> URL? {
        try FileManager.default.moveItem(at: target.url, to: target.url.deletingLastPathComponent().appendingPathComponent("unresolved.pdf"))
        throw CocoaError(.fileWriteUnknown)
    }
}
@Test func operationThrowWithMissingSourceIsUnknownAndNeverInferredSuccess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExecutor-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.pdf", "b.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let batch = try await approval(root)
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))
    let result = await TrashExecutor(journal: journal, operation: MoveThenThrow()).execute(batch)
    #expect(result.targets.map(\.state) == [.unknown, .cancelled])
    #expect(result.trashHeldAllocatedBytes == nil)
    #expect(result.targets.first?.trashURL == nil)
    #expect(try journal.records().first?.state == .unknown)
}
