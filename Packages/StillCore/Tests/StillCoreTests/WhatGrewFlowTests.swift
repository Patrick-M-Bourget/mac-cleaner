import Foundation
import Testing
@testable import StillCore

@Test func firstObservationOfAnotherLocationDoesNotCompareUnrelatedScopes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory)
    func observation(_ scope: String, _ time: Double, _ bytes: Int64) -> GrowthSnapshot {
        GrowthSnapshot(fingerprint: .init(scopeID: scope, rootID: scope, volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: "Same name", observedAt: Date(timeIntervalSince1970: time), groups: [.init(id: "root", label: "Root files", logicalBytes: bytes)])
    }
    let first = observation("A", 100, 10)
    _ = try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch())
    let other = observation("B", 200, 500)
    let result = try await store.record(other, now: other.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .firstBaseline)
    #expect(result.from == nil)
    #expect(result.logicalDelta == nil)
    let next = observation("A", 300, 14)
    let comparison = try await store.record(next, now: next.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(comparison.state == .compared)
    #expect(comparison.from == first.observedAt)
    #expect(comparison.logicalDelta == 4)
}

@Test @MainActor func stoppingANewObservationPreservesTheLastUsefulComparison() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory)
    let now = Date()
    let fingerprint = GrowthFingerprint(scopeID: "A", rootID: "A", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    for (age, bytes) in [(20.0, Int64(10)), (10.0, Int64(14))] {
        let observation = GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "A", observedAt: now.addingTimeInterval(-age), groups: [.init(id: "root", label: "Root files", logicalBytes: bytes)])
        _ = try await store.record(observation, now: now, expectedEpoch: try await store.recordingEpoch())
    }
    let session = GrowthHistorySession(store: store)
    await session.load(now: now)
    let selected = try #require(session.comparison?.current?.id)
    session.cancelled()
    #expect(session.comparison?.current?.id == selected)
    #expect(session.comparison?.logicalDelta == 4)
}

@Test func historicalLocationMatchingRejectsSameNamedFoldersAndReplacementRoots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = root.appendingPathComponent("Original/Folder")
    let other = root.appendingPathComponent("Unrelated/Folder")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try Data([1]).write(to: scope.appendingPathComponent("owned.txt"))
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("State"))
    let recorder = GrowthScanRecorder(store: store)
    let token = try await recorder.begin(scope: scope)
    let comparison = try await recorder.complete(try await FolderScanner().scan(scope), token: token)
    let snapshot = try #require(comparison.current)
    #expect(try await recorder.matchesLocation(scope, snapshot: snapshot))
    #expect(try await !recorder.matchesLocation(other, snapshot: snapshot))
    try FileManager.default.moveItem(at: scope, to: root.appendingPathComponent("Moved"))
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    #expect(try await !recorder.matchesLocation(scope, snapshot: snapshot))
}

@Test @MainActor func failedObservationSaveKeepsTheDisplayedComparisonAndReportsFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = root.appendingPathComponent("Folder"), archive = root.appendingPathComponent("History")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    let file = scope.appendingPathComponent("owned.txt")
    try Data([1]).write(to: file)
    let store = GrowthHistoryStore(directory: archive)
    let session = GrowthHistorySession(store: store)
    for bytes in [Data([1]), Data([1, 2, 3])] {
        try bytes.write(to: file)
        let token = try #require(await session.begin(scope))
        await session.complete(try await FolderScanner().scan(scope), token: token)
    }
    let selected = try #require(session.comparison?.current?.id)
    #expect(session.comparison?.logicalDelta == 2)
    let token = try #require(await session.begin(scope))
    // A real unavailable archive at the filesystem boundary, not a fake internal store.
    try Data("unreadable archive".utf8).write(to: archive.appendingPathComponent("aggregates-v1.json"))
    await session.complete(try await FolderScanner().scan(scope), token: token)
    #expect(session.comparison?.current?.id == selected)
    #expect(session.comparison?.logicalDelta == 2)
    #expect(session.error != nil)
}

@Test @MainActor func partialObservationDoesNotReplaceAUsefulComparison() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = root.appendingPathComponent("Folder")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    for name in ["one.txt", "two.txt"] { try Data([1]).write(to: scope.appendingPathComponent(name)) }
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History"))
    let session = GrowthHistorySession(store: store)
    for _ in 0..<2 {
        let token = try #require(await session.begin(scope))
        await session.complete(try await FolderScanner().scan(scope), token: token)
    }
    let selected = try #require(session.comparison?.current?.id)
    let token = try #require(await session.begin(scope))
    let partial = try await FolderScanner(maximumEntries: 1).scan(scope)
    #expect(!partial.isComplete)
    await session.complete(partial, token: token)
    #expect(session.comparison?.current?.id == selected)
    #expect(session.comparison?.state == .compared)
    #expect(try await store.snapshots().count == 2)
}

@Test @MainActor func unavailableLocationDoesNotEraseTheRetainedComparison() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = root.appendingPathComponent("Folder")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    let session = GrowthHistorySession(store: GrowthHistoryStore(directory: root.appendingPathComponent("History")))
    let token = try #require(await session.begin(scope))
    await session.complete(try await FolderScanner().scan(scope), token: token)
    let selected = try #require(session.comparison?.current?.id)
    try FileManager.default.removeItem(at: scope)
    #expect(await session.begin(scope) == nil)
    #expect(session.comparison?.current?.id == selected)
    #expect(session.error != nil)
}

@Test @MainActor func partialScanCannotKeepANumericComparisonWhoseHistoryHasExpired() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = root.appendingPathComponent("Folder")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    for name in ["one.txt", "two.txt"] { try Data([1]).write(to: scope.appendingPathComponent(name)) }
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History"))
    let past = Date().addingTimeInterval(-91 * 86400)
    let fingerprint = GrowthFingerprint(scopeID: "A", rootID: "A", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    for (offset, bytes) in [(0.0, Int64(1)), (1.0, Int64(3))] {
        let date = past.addingTimeInterval(offset)
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Folder", observedAt: date, groups: [.init(id: "root", label: "Files", logicalBytes: bytes)]), now: date, expectedEpoch: try await store.recordingEpoch())
    }
    let session = GrowthHistorySession(store: store)
    await session.load(now: past.addingTimeInterval(2))
    #expect(session.comparison?.logicalDelta == 2)
    let token = try #require(await session.begin(scope))
    await session.complete(try await FolderScanner(maximumEntries: 1).scan(scope), token: token)
    #expect(session.snapshots.isEmpty)
    #expect(session.comparison?.state == .missingBaseline)
    #expect(session.comparison?.logicalDelta == nil)
}

@Test @MainActor func partialScanRevalidatesComparisonWhenOnlyItsOlderEndpointExpires() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = root.appendingPathComponent("Folder")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    for name in ["one.txt", "two.txt"] { try Data([1]).write(to: scope.appendingPathComponent(name)) }
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History"))
    let now = Date()
    let fingerprint = GrowthFingerprint(scopeID: "A", rootID: "A", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    let older = now.addingTimeInterval(-91 * 86400)
    let newer = now.addingTimeInterval(-89 * 86400)
    for (date, bytes) in [(older, Int64(1)), (newer, Int64(3))] {
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Folder", observedAt: date, groups: [.init(id: "root", label: "Files", logicalBytes: bytes)]), now: date, expectedEpoch: try await store.recordingEpoch())
    }
    let session = GrowthHistorySession(store: store)
    await session.load(now: newer)
    #expect(session.comparison?.logicalDelta == 2)
    let selected = try #require(session.comparison?.current?.id)
    let token = try #require(await session.begin(scope))
    await session.complete(try await FolderScanner(maximumEntries: 1).scan(scope), token: token)
    #expect(session.snapshots.count == 1)
    #expect(session.comparison?.current?.id == selected)
    #expect(session.comparison?.state == .missingBaseline)
    #expect(session.comparison?.logicalDelta == nil)
}

@Test func expiredUnrelatedHistoryDoesNotClaimANewLocationLostItsBaseline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory)
    func observation(_ scope: String, _ date: Date) -> GrowthSnapshot {
        GrowthSnapshot(fingerprint: .init(scopeID: scope, rootID: scope, volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: scope, observedAt: date, groups: [.init(id: "root", label: "Files", logicalBytes: 1)])
    }
    let old = Date(timeIntervalSince1970: 1000)
    _ = try await store.record(observation("A", old), now: old, expectedEpoch: try await store.recordingEpoch())
    let now = old.addingTimeInterval(91 * 86400)
    let result = try await store.record(observation("B", now), now: now, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .firstBaseline)
    #expect(result.from == nil)
    #expect(result.current?.scopeLabel == "B")
}
