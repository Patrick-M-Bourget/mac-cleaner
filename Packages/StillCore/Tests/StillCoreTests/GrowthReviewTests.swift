import Foundation
import Testing
import StillCore

@Test func clearAndResetRejectEarlierObservationEvenThroughAnotherStoreInstance() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthReview-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Scope"), history = root.appendingPathComponent("History")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: scope.appendingPathComponent("owned.pdf"))
    let store = GrowthHistoryStore(directory: history), recorder = GrowthScanRecorder(store: store)
    for reset in [false, true] {
        let token = try await recorder.begin(scope: scope)
        let scan = try await FolderScanner().scan(scope)
        let maintenance = GrowthHistoryStore(directory: history)
        if reset { try await maintenance.resetHistory() } else { try await maintenance.clearCompletedHistory() }
        #expect(try await recorder.complete(scan, token: token).state == .unknown)
        let reopened = GrowthHistoryStore(directory: history)
        #expect(try await reopened.snapshots().isEmpty)
        #expect(try await reopened.latest().state == (reset ? .firstBaseline : .clearedBaseline))
    }
}
@Test func aRealFolderNamedLikeTheRootBucketKeepsItsOwnGrowth() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthReview-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Scope"), nested = scope.appendingPathComponent("Files in selected folder")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1, 2]).write(to: scope.appendingPathComponent("root.pdf"))
    let child = nested.appendingPathComponent("child.pdf")
    try Data([3, 4, 5]).write(to: child)
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History")), recorder = GrowthScanRecorder(store: store)
    let firstToken = try await recorder.begin(scope: scope)
    let first = try await recorder.complete(FolderScanner().scan(scope), token: firstToken)
    #expect(first.current?.groups.filter { $0.dimension == .folder }.count == 2)
    #expect(first.current?.logicalBytes == 5)
    try Data([3, 4, 5, 6]).write(to: child)
    let secondToken = try await recorder.begin(scope: scope)
    let second = try await recorder.complete(FolderScanner().scan(scope), token: secondToken)
    #expect(second.state == .compared)
    #expect(second.groups.filter { $0.dimension == .folder }.map(\.logicalDelta).sorted() == [0, 1])
}

private actor DelayedGrowthRecording: GrowthObservationRecording {
    let real: GrowthScanRecorder
    private var firstToken: UUID?
    private var held: CheckedContinuation<Void, any Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    init(store: GrowthHistoryStore) { real = GrowthScanRecorder(store: store) }
    func begin(scope: URL) async throws -> GrowthScanToken { try await real.begin(scope: scope) }
    func complete(_ scan: ScanResult, token: GrowthScanToken) async throws -> GrowthComparison {
        if firstToken == nil {
            firstToken = token.id
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                held = continuation; waiting?.resume(); waiting = nil
            }
        }
        return try await real.complete(scan, token: token)
    }
    func firstCompletionStarted() async {
        if held != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func failOldCompletion() { held?.resume(throwing: CocoaError(.fileReadUnknown)); held = nil }
    func releaseOldCompletion() { held?.resume(); held = nil }
}
@Test @MainActor func aStaleFailedGrowthCompletionCannotReplaceANewerResult() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthReview-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Scope")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: scope.appendingPathComponent("owned.pdf"))
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History"))
    let recording = DelayedGrowthRecording(store: store)
    let session = GrowthHistorySession(store: store, recorder: recording)
    let first = try #require(await session.begin(scope))
    let firstScan = try await FolderScanner().scan(scope)
    let old = Task { await session.complete(firstScan, token: first) }
    await recording.firstCompletionStarted()
    let current = try #require(await session.begin(scope))
    await session.complete(try await FolderScanner().scan(scope), token: current)
    #expect(session.comparison?.state == .firstBaseline)
    await recording.failOldCompletion(); await old.value
    #expect(session.comparison?.state == .firstBaseline)
    #expect(session.error == nil)
}

@Test @MainActor func loadingGrowthAfterRetentionExpiresDropsTheCachedNumericComparison() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthReview-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root)
    let fingerprint = GrowthFingerprint(scopeID: "owned", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    for (time, bytes) in [(100.0, Int64(3)), (200, Int64(8))] {
        let date = Date(timeIntervalSince1970: time)
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Owned", observedAt: date, groups: [.init(id: "root", label: "Root files", logicalBytes: bytes)]), now: date, expectedEpoch: try await store.recordingEpoch())
    }
    let session = GrowthHistorySession(store: store)
    await session.load(now: Date(timeIntervalSince1970: 200))
    #expect(session.comparison?.logicalDelta == 5)
    await session.load(now: Date(timeIntervalSince1970: 200 + 91 * 86400))
    #expect(session.snapshots.isEmpty)
    #expect(session.comparison?.state == .missingBaseline)
    #expect(session.comparison?.logicalDelta == nil)
}

private actor DelayedBeginRecording: GrowthObservationRecording {
    let real: GrowthScanRecorder
    private var first = true
    private var held: CheckedContinuation<Void, any Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    init(store: GrowthHistoryStore) { real = GrowthScanRecorder(store: store) }
    func begin(scope: URL) async throws -> GrowthScanToken {
        let token = try await real.begin(scope: scope)
        if first {
            first = false
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                held = continuation; waiting?.resume(); waiting = nil
            }
        }
        return token
    }
    func complete(_ scan: ScanResult, token: GrowthScanToken) async throws -> GrowthComparison { try await real.complete(scan, token: token) }
    func firstBeginStarted() async { if held != nil { return }; await withCheckedContinuation { waiting = $0 } }
    func failOldBegin() { held?.resume(throwing: CocoaError(.fileReadUnknown)); held = nil }
}
@Test @MainActor func aStaleFailedGrowthBeginCannotReplaceANewerResult() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthReview-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Scope")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History"))
    let recording = DelayedBeginRecording(store: store)
    // The session uses the same real store; only the old metadata request is held.
    let controlled = GrowthHistorySession(store: store, recorder: recording)
    let old = Task { await controlled.begin(scope) }
    await recording.firstBeginStarted()
    let current = try #require(await controlled.begin(scope))
    await controlled.complete(try await FolderScanner().scan(scope), token: current)
    #expect(controlled.comparison?.state == .firstBaseline)
    await recording.failOldBegin(); _ = await old.value
    #expect(controlled.comparison?.state == .firstBaseline)
    #expect(controlled.error == nil)
}

@Test @MainActor func clearingOrResettingAnActiveGrowthSessionCannotResurrectHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthReview-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Scope"), directory = root.appendingPathComponent("History")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: scope.appendingPathComponent("owned.pdf"))
    let store = GrowthHistoryStore(directory: directory)
    for reset in [false, true] {
        let recording = DelayedGrowthRecording(store: store)
        let session = GrowthHistorySession(store: store, recorder: recording)
        let token = try #require(await session.begin(scope))
        let scan = try await FolderScanner().scan(scope)
        let pending = Task { await session.complete(scan, token: token) }
        await recording.firstCompletionStarted()
        if reset { try await session.resetHistory() } else { try await session.clearCompletedHistory() }
        await recording.releaseOldCompletion(); await pending.value
        #expect(session.comparison?.state == (reset ? .firstBaseline : .clearedBaseline))
        #expect(session.snapshots.isEmpty)
        let reopened = GrowthHistoryStore(directory: directory)
        #expect(try await reopened.snapshots().isEmpty)
        #expect(try await reopened.latest().state == (reset ? .firstBaseline : .clearedBaseline))
    }
}
