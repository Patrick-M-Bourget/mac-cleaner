import Foundation
import Testing
import StillCore

private func disposableTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillScanner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func inspectExplicitFolderReportsPathsLogicalBytesAndTime() async throws {
    let root = try disposableTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("Trips", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data(repeating: 42, count: 137).write(to: nested.appendingPathComponent("trip.mov"))
    let started = Date()
    let result = try await FolderScanner().scan(root)
    #expect(result.scope == root)
    #expect(result.observedAt >= started)
    #expect(result.observations.contains { $0.url.lastPathComponent == "trip.mov" && $0.logicalBytes == 137 })
    #expect(result.logicalBytes == 137)
}

@Test func discoveryStaysInScopeAndCountsHardlinkedFilesOnce() async throws {
    let root = try disposableTree()
    let outside = try disposableTree()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
    let file = root.appendingPathComponent("source.bin")
    try Data(repeating: 1, count: 100).write(to: file)
    try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("same-file.bin"))
    try Data(repeating: 2, count: 999).write(to: outside.appendingPathComponent("outside-secret.bin"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside-link"), withDestinationURL: outside)
    let package = root.appendingPathComponent("Protected.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data(repeating: 3, count: 700).write(to: package.appendingPathComponent("private.bin"))
    let result = try await FolderScanner().scan(root)
    #expect(result.logicalBytes == 100)
    #expect(result.observations.contains { $0.url.lastPathComponent == "Protected.app" })
    #expect(result.observations.contains { $0.url.lastPathComponent == "same-file.bin" })
    #expect(!result.observations.contains { $0.url.lastPathComponent == "private.bin" || $0.url.lastPathComponent == "outside-secret.bin" })
}

private struct MissingSupplement: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        MetadataSupplement(allocatedBytes: nil, locality: .unknown)
    }
}

@Test func unknownAllocationAndCloudLocalityRemainUnknown() async throws {
    let root = try disposableTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("document.bin"))
    let result = try await FolderScanner(supplement: MissingSupplement()).scan(root)
    #expect(result.logicalBytes == 100)
    #expect(result.allocatedBytes == nil)
    #expect(result.allocatedUnknownCount == 1)
    #expect(result.observations.first?.previewAvailability == .unknown)
    #expect(result.volumeCapacityBytes != nil)
}

@Test func boundedScanExplainsTruncationAndRejectsSymlinkRoot() async throws {
    let root = try disposableTree()
    let parent = try disposableTree()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: parent) }
    for name in ["a.bin", "b.bin", "c.bin"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let result = try await FolderScanner(maximumEntries: 2).scan(root)
    #expect(result.observations.count == 2)
    #expect(!result.isComplete)
    #expect(result.issues.contains { $0.reason == .entryLimit })
    let link = parent.appendingPathComponent("linked-root")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    await #expect(throws: (any Error).self) { try await FolderScanner().scan(link) }
}

@Test func explicitPreviewRequiresFreshPositiveLocality() async throws {
    let root = try disposableTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([65]).write(to: root.appendingPathComponent("note.txt"))
    let scanner = FolderScanner(supplement: MissingSupplement())
    let result = try await scanner.scan(root)
    let item = try #require(result.observations.first)
    await #expect(throws: (any Error).self) { try await scanner.previewURL(for: item) }
}

@Test func protectedPackageCannotBecomeRecursiveScanRoot() async throws {
    let root = try disposableTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let package = root.appendingPathComponent("Protected.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data([65]).write(to: package.appendingPathComponent("private.bin"))
    await #expect(throws: (any Error).self) { try await FolderScanner().scan(package) }
}
