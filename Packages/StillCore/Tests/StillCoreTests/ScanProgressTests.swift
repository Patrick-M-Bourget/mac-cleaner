import Foundation
import Darwin
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

private struct ReplacingProgressMetadata: MetadataSupplementReading {
    let target: URL
    func read(_ url: URL) throws -> MetadataSupplement {
        if url.lastPathComponent == target.lastPathComponent {
            let replacement = target.deletingLastPathComponent().appendingPathComponent("replacement")
            try Data([9, 9]).write(to: replacement)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: replacement)
        }
        return MetadataSupplement(allocatedBytes: 4096, locality: .local)
    }
}
@Test func changedIdentityDuringMetadataIsPartialAndNeverPublishedAsStableObservation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("changing.txt")
    try Data([1]).write(to: target)
    let result = try await FolderScanner(supplement: ReplacingProgressMetadata(target: target)).scan(root)
    #expect(!result.isComplete)
    #expect(!result.observations.contains { $0.url.lastPathComponent == target.lastPathComponent })
    #expect(result.totalLogicalBytes == nil)
}

@Test func sparseHardlinkAndUnicodePathsKeepLogicalAllocationAndPackageBoundaries() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent(String(repeating: "é", count: 60) + "-📷.bin")
    let handle = try FileHandle(forWritingTo: createEmpty(file))
    try handle.truncate(atOffset: 64 * 1024 * 1024)
    try handle.close()
    try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("hardlink.bin"))
    let package = root.appendingPathComponent("Protected.app")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
    try Data([1, 2, 3]).write(to: package.appendingPathComponent("unmeasured"))
    let result = try await FolderScanner().scan(root)
    #expect(result.logicalBytes == 64 * 1024 * 1024)
    #expect(result.observations.filter { $0.kind == .file }.count == 2)
    #expect(result.observations.filter(\.isDuplicateResource).count == 1)
    #expect(result.observations.contains { $0.kind == .package })
    #expect(!result.observations.contains { $0.url.lastPathComponent == "unmeasured" })
    #expect(result.totalLogicalBytes == nil)
    #expect(result.allocatedBytes.map { $0 < result.logicalBytes } == true)
}
private func createEmpty(_ url: URL) throws -> URL {
    try Data().write(to: url)
    return url
}

@Test func supportedAPFSCloneKeepsDistinctIdentityWithoutClaimingExclusiveReclaimableBytes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original.bin")
    let clone = root.appendingPathComponent("clone.bin")
    try Data(repeating: 7, count: 16_384).write(to: original)
    let cloned = clonefile(original.path, clone.path, 0) == 0
    print("Owned APFS clone fixture created=\(cloned)")
    guard cloned else {
        // A filesystem without clone support remains a separate qualification gate.
        #expect(!FileManager.default.fileExists(atPath: clone.path))
        return
    }
    let result = try await FolderScanner().scan(root)
    #expect(result.observations.count == 2)
    #expect(Set(result.observations.map(\.resourceID)).count == 2)
    #expect(result.logicalBytes == 32_768)
    #expect(result.observations.allSatisfy { !$0.isDuplicateResource })
}

@Test func filesystemCompressionWhenAvailablePreservesLogicalSizeSemantics() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillProgress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.bin")
    let destination = root.appendingPathComponent("compressed.bin")
    try Data(repeating: 65, count: 1_048_576).write(to: source)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["--hfsCompression", source.path, destination.path]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    var metadata = stat()
    #expect(lstat(destination.path, &metadata) == 0)
    let compressed = metadata.st_flags & UInt32(UF_COMPRESSED) != 0
    print("Owned compression fixture UF_COMPRESSED=\(compressed); unsupported hosts do not qualify compression")
    let result = try await FolderScanner().scan(root)
    #expect(result.logicalBytes == 2_097_152)
    #expect(result.observations.allSatisfy { $0.logicalBytes == 1_048_576 })
    if compressed {
        #expect(result.observations.first { $0.url.lastPathComponent == "compressed.bin" }?.allocatedBytes.map { $0 < 1_048_576 } == true)
    }
}
