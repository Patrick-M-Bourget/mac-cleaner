import Foundation
import Testing
import StillCore

private final class PublicProgressRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ScanProgress] = []
    func append(_ progress: ScanProgress) { lock.lock(); defer { lock.unlock() }; events.append(progress) }
    func snapshot() -> [ScanProgress] { lock.lock(); defer { lock.unlock() }; return events }
}
@Test func scanPublishesBoundedUsefulProgressBeforeCompletedResult() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<600 { try Data([1]).write(to: root.appendingPathComponent("file-\(index)")) }
    let events = PublicProgressRecord()
    let result = try await FolderScanner().scan(root, onProgress: { events.append($0) })
    let progress = events.snapshot()
    #expect(!progress.isEmpty)
    #expect(progress.first?.recentObservations.isEmpty == false)
    #expect(progress.allSatisfy { !$0.isComplete && $0.recentObservations.count <= 256 })
    #expect(progress.map(\.visitedEntries) == progress.map(\.visitedEntries).sorted())
    #expect(result.observations.count == 600)
}

@Test func cancellationRequestAcknowledgesWithoutWaitingForScannerActor() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<50 { try Data([1]).write(to: root.appendingPathComponent("file-\(index)")) }
    let cancellation = ScanCancellation()
    await #expect(throws: CancellationError.self) {
        try await FolderScanner().scan(root, cancellation: cancellation, onProgress: { _ in cancellation.cancel() })
    }
    #expect(cancellation.isCancellationRequested)
}

private struct UnavailableProgressMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement { throw CocoaError(.fileReadNoPermission) }
}
@Test func repeatedMetadataFailuresStayBoundedAndNeverLookComplete() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<100 { try Data([1]).write(to: root.appendingPathComponent("file-\(index)")) }
    let result = try await FolderScanner(supplement: UnavailableProgressMetadata(), maximumIssues: 3).scan(root)
    #expect(result.issues.count <= 4)
    #expect(result.issues.contains { $0.reason == .issueLimit })
    #expect(!result.isComplete)
    #expect(result.totalLogicalBytes == nil)
}
