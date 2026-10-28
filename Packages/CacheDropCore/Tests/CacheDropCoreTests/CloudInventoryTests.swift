import Foundation
import Testing
import CacheDropCore

private struct CloudFixtureMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        switch url.lastPathComponent {
        case "current.bin":
            return .init(allocatedBytes: 200, locality: .local, cloud: .init(membership: true, downloadState: .current, uploaded: nil))
        case "placeholder.bin":
            return .init(allocatedBytes: 10, locality: .nonlocal, cloud: .init(membership: true, downloadState: .notDownloaded, uploaded: true))
        default:
            return .init(allocatedBytes: nil, locality: .unknown, cloud: .init(membership: nil, downloadState: .unknown, uploaded: nil))
        }
    }
}

@Test func cloudBreakdownSeparatesLocalAllocationFromCloudLogicalSizeAndUnknowns() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCloudInventory-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["current.bin", "placeholder.bin", "unknown.bin"] {
        try Data(repeating: 1, count: 1_000).write(to: root.appendingPathComponent(name))
    }
    let scan = try await FolderScanner(supplement: CloudFixtureMetadata()).scan(root)
    let report = scan.cloudInventory
    #expect(report.localItemCount == 1)
    #expect(report.localAllocatedBytes == 200)
    #expect(report.cloudOnlyItemCount == 1)
    #expect(report.cloudOnlyLogicalBytes == 1_000)
    #expect(report.unknownMembershipCount == 1)
    #expect(report.items.first { $0.url.lastPathComponent == "current.bin" }?.cloud.uploaded == nil)
    #expect(report.evictionAvailable == false)
}

private struct DeniedCloudScope: ScanAccessChecking {
    func check(_ url: URL) throws { throw ScanAccessFailure.denied }
}

@Test func unreadableCloudScopeDoesNotClaimZeroCloudAllocation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCloudDenied-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let result = try await FolderScanner(access: DeniedCloudScope()).scan(root)
    #expect(!result.cloudInventory.isComplete)
    #expect(result.cloudInventory.localAllocatedBytes == nil)
    #expect(result.cloudInventory.cloudOnlyLogicalBytes == nil)
}

@Test func nativeExistingOrdinaryFileGetsExplicitNonCloudMembership() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropOrdinaryMetadata-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([65]).write(to: root.appendingPathComponent("ordinary.txt"))
    let result = try await FolderScanner().scan(root)
    let item = try #require(result.observations.first)
    #expect(item.cloud.membership == false)
    #expect(item.previewAvailability == .local)
}

private struct UndecidedCloudMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        switch url.lastPathComponent {
        case "membership.bin":
            return .init(allocatedBytes: 10, locality: .local, cloud: .init(membership: nil))
        case "current.bin":
            return .init(allocatedBytes: 200, locality: .local, cloud: .init(membership: true, downloadState: .current))
        default:
            return .init(allocatedBytes: 10, locality: .local, cloud: .init(membership: true, downloadState: .unknown))
        }
    }
}

private func cloudReport(_ names: [String]) async throws -> CloudInventoryReport {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCloudUnknown-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in names { try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent(name)) }
    return try await FolderScanner(supplement: UndecidedCloudMetadata()).scan(root).cloudInventory
}

/// #331: the Overview row reads "Unknown" and adds one plain line saying why.
@Test func unknownCloudTotalSaysWhyInOnePlainLine() async throws {
    let known = try await cloudReport(["current.bin"])
    #expect(!known.totalIsUnknown)
    #expect(known.unknownReason == nil)

    let state = try await cloudReport(["current.bin", "a.bin", "b.bin", "c.bin"])
    #expect(state.totalIsUnknown)
    #expect(state.unknownReason == "CacheDrop couldn't tell whether 3 files are downloaded.")

    let membership = try await cloudReport(["current.bin", "membership.bin"])
    #expect(membership.totalIsUnknown)
    #expect(membership.unknownReason == "CacheDrop couldn't tell whether 1 file is in iCloud.")

    let both = try await cloudReport(["membership.bin", "a.bin"])
    #expect(both.unknownReason == "CacheDrop couldn't tell whether 1 file is in iCloud, or whether 1 file is downloaded.")
}
