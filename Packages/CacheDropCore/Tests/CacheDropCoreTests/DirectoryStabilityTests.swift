import Foundation
import Testing
import CacheDropCore

private final class MutatingDirectoryMetadata: MetadataSupplementReading, @unchecked Sendable {
    let directory: URL
    let repeated: Bool
    private let lock = NSLock()
    private var count = 0
    init(_ directory: URL, repeated: Bool = false) { self.directory = directory; self.repeated = repeated }
    func read(_ url: URL) throws -> MetadataSupplement {
        lock.lock(); defer { lock.unlock() }
        if url.lastPathComponent == "trigger.txt" {
            count += 1
            if count == 1 && !repeated { try Data([4]).write(to: directory.appendingPathComponent("arrived.txt")) }
            if repeated { try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(100 + count))], ofItemAtPath: directory.path) }
        }
        return .init(allocatedBytes: 3, locality: .local, cloud: .init(membership: false))
    }
}
private final class StabilityProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var last: ScanPhase?
    func observe(_ progress: ScanProgress) { lock.lock(); defer { lock.unlock() }; if progress.phase == .rechecking && last != .rechecking { count += 1 }; last = progress.phase }
    var rechecks: Int { lock.lock(); defer { lock.unlock() }; return count }
}
@Test func oneChangingDirectoryGetsOneBoundedRecheckThenPublishesStableLatestContents() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    let nested = root.appendingPathComponent("Nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1, 2, 3]).write(to: nested.appendingPathComponent("trigger.txt"))
    let progress = StabilityProgress()
    let result = try await FolderScanner(supplement: MutatingDirectoryMetadata(nested)).scan(root, onProgress: { progress.observe($0) })
    #expect(result.isComplete)
    #expect(result.logicalBytes == 4)
    #expect(result.observations.contains { $0.url.lastPathComponent == "arrived.txt" })
    #expect(progress.rechecks == 1)
}

@Test func repeatedDirectoryChangesStayPartialAndUnmeasured() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
    let result = try await FolderScanner(supplement: MutatingDirectoryMetadata(scope, repeated: true)).scan(scope)
    #expect(!result.isComplete && result.totalLogicalBytes == nil)
    #expect(result.issues.contains { $0.reason == .directoryChanged })
}

private final class ReplacingScopeMetadata: MetadataSupplementReading, @unchecked Sendable {
    let scope: URL
    private let lock = NSLock()
    private var replaced = false
    init(_ scope: URL) { self.scope = scope }
    func read(_ url: URL) throws -> MetadataSupplement {
        lock.lock(); defer { lock.unlock() }
        if !replaced {
            replaced = true
            try FileManager.default.moveItem(at: scope, to: scope.appendingPathExtension("previous"))
            try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: false)
            try Data([9]).write(to: scope.appendingPathComponent("substitute.txt"))
        }
        return .init(allocatedBytes: 1, locality: .local)
    }
}
@Test func replacingTheSelectedDirectoryNeverRebasesScopeAuthorityDuringRecheck() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope); try? FileManager.default.removeItem(at: scope.appendingPathExtension("previous")) }
    try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
    let progress = StabilityProgress()
    let result = try await FolderScanner(supplement: ReplacingScopeMetadata(scope)).scan(scope, onProgress: { progress.observe($0) })
    #expect(!result.isComplete && result.totalLogicalBytes == nil)
    #expect(result.issues.contains { $0.reason == .locationUnavailable })
    #expect(!result.observations.contains { $0.url.lastPathComponent == "substitute.txt" })
    #expect(progress.rechecks == 0)
}
@Test func cancellationAtRecheckBoundaryNeverPublishesACompletedObservation() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope) }
    try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
    let cancellation = ScanCancellation()
    do {
        _ = try await FolderScanner(supplement: MutatingDirectoryMetadata(scope)).scan(scope, cancellation: cancellation, onProgress: { if $0.phase == .rechecking { cancellation.cancel() } })
        Issue.record("Cancelled recheck published a result")
    } catch is CancellationError { }
}
@Test func recheckSharesOriginalEntryBudgetRatherThanDoublingRetainedWork() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope) }
    try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
    let result = try await FolderScanner(supplement: MutatingDirectoryMetadata(scope), maximumEntries: 2).scan(scope)
    #expect(!result.isComplete)
    #expect(result.issues.contains { $0.reason == .entryLimit })
    #expect(result.observations.count <= 2)
}

private struct SlowStabilityMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement { Thread.sleep(forTimeInterval: 0.02); return .init(allocatedBytes: 1, locality: .local) }
}
@Test func returningMetadataCallBeyondDeadlineLeavesCoverageUnknown() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope) }
    try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
    let result = try await FolderScanner(supplement: SlowStabilityMetadata(), maximumDuration: 0.001).scan(scope)
    #expect(!result.isComplete && result.totalLogicalBytes == nil)
    #expect(result.issues.contains { $0.reason == .timeLimit })
}

private final class SymlinkReplacingDirectoryMetadata: MetadataSupplementReading, @unchecked Sendable {
    let nested, moved, external: URL
    private let lock = NSLock()
    private var replaced = false
    init(nested: URL, moved: URL, external: URL) { self.nested = nested; self.moved = moved; self.external = external }
    func read(_ url: URL) throws -> MetadataSupplement {
        lock.lock(); defer { lock.unlock() }
        if !replaced {
            replaced = true
            try FileManager.default.moveItem(at: nested, to: moved)
            try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: external)
        }
        return .init(allocatedBytes: 1, locality: .local)
    }
}
@Test func replacedAncestorSymlinkIsNotTraversedDuringTheSingleRecheck() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    let scope = base.appendingPathComponent("Selected"), external = base.appendingPathComponent("Outside")
    let nested = scope.appendingPathComponent("Nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try Data([1]).write(to: nested.appendingPathComponent("trigger.txt"))
    let sentinel = external.appendingPathComponent("foreign-only.txt")
    try Data([9, 9, 9]).write(to: sentinel)
    let result = try await FolderScanner(supplement: SymlinkReplacingDirectoryMetadata(nested: nested, moved: base.appendingPathComponent("Original"), external: external)).scan(scope)
    #expect(result.isComplete)
    #expect(result.logicalBytes == 0)
    #expect(result.observations.contains { $0.kind == .symbolicLink })
    #expect(!result.observations.contains { $0.kind == .file })
    #expect(try Data(contentsOf: sentinel) == Data([9, 9, 9]))
}

@Test func rootReplacementAfterRecheckAnnouncementCannotRebaseTheSecondPass() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropStability-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope); try? FileManager.default.removeItem(at: scope.appendingPathExtension("previous")) }
    try Data([1]).write(to: scope.appendingPathComponent("trigger.txt"))
    let result = try await FolderScanner(supplement: MutatingDirectoryMetadata(scope)).scan(scope, onProgress: { progress in
        if progress.phase == .rechecking && progress.retainedObservations == 0 {
            do {
                try FileManager.default.moveItem(at: scope, to: scope.appendingPathExtension("previous"))
                try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: false)
                try Data([9]).write(to: scope.appendingPathComponent("substitute.txt"))
            } catch { Issue.record("Owned replacement fixture failed: \(error)") }
        }
    })
    #expect(!result.isComplete)
    #expect(result.issues.contains { $0.reason == .locationUnavailable })
    #expect(!result.observations.contains { $0.url.lastPathComponent == "substitute.txt" })
}
