import Foundation
import Testing
import CacheDropCore

@MainActor private final class ScanGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var waiting = false
    private var released = false
    func hold() async {
        if released { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting = true
            entered?.resume(); entered = nil
        }
    }
    func waitUntilHeld() async {
        if waiting { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@Test @MainActor func scanCompletionWaitsForHeldFinalHistoryWrite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropScanLifecycle-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StorageTrendsHistoryStore(directory: root)
    let epoch = try await store.recordingEpoch()
    let date = Date()
    let activity = ScanActivity(startedAt: date, completedAt: date, outcome: .stopped, locations: [.init(path: "/Example")])
    let gate = ScanGate()
    let lifecycle = ScanLifecycle()
    var writeFinished = false
    lifecycle.start {
        await gate.hold()
        _ = try? await store.recordActivity(activity, expectedEpoch: epoch)
        writeFinished = true
    }
    await gate.waitUntilHeld()
    let entered = ScanGate()
    let completion = Task {
        entered.release()
        await lifecycle.waitForCompletion()
        #expect(writeFinished)
    }
    await entered.hold()
    #expect(lifecycle.isRunning)
    #expect(try await store.activities().isEmpty)
    gate.release()
    await completion.value
    #expect(!lifecycle.isRunning)
    #expect(try await store.activities().map(\.id) == [activity.id])
    let saved = try Data(contentsOf: root.appendingPathComponent("aggregates-v1.json"))
    await lifecycle.stopAndWait()
    await lifecycle.stopAndWait()
    #expect(try Data(contentsOf: root.appendingPathComponent("aggregates-v1.json")) == saved)
}

@Test @MainActor func repeatedScanStopWaitsForDiscoveryAndFinalStorageTrendsWrite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropScanLifecycle-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StorageTrendsHistoryStore(directory: root)
    let epoch = try await store.recordingEpoch()
    let date = Date()
    let snapshot = StorageTrendsSnapshot(fingerprint: .init(scopeID: "catalog:example", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: "Known locations", observedAt: date, groups: [.init(id: "files", label: "Files", logicalBytes: 12)])
    let discovery = ScanGate(), finalWrite = ScanGate(), entered = ScanGate()
    let lifecycle = ScanLifecycle()
    var stopped = 0, writeFinished = false
    lifecycle.start(stop: { stopped += 1; discovery.release() }) {
        await discovery.hold()
        await finalWrite.hold()
        _ = try? await store.record(snapshot, expectedEpoch: epoch)
        writeFinished = true
    }
    await discovery.waitUntilHeld()
    let first = Task {
        entered.release()
        await lifecycle.stopAndWait()
        #expect(writeFinished)
    }
    await entered.hold()
    await finalWrite.waitUntilHeld()
    let second = Task { await lifecycle.stopAndWait(); #expect(writeFinished) }
    #expect(lifecycle.isRunning)
    #expect(try await store.snapshots().isEmpty)
    finalWrite.release()
    await first.value
    await second.value
    #expect(stopped == 1)
    #expect(try await store.snapshots().map(\.id) == [snapshot.id])
    let saved = try Data(contentsOf: root.appendingPathComponent("aggregates-v1.json"))
    await lifecycle.stopAndWait()
    #expect(stopped == 1)
    #expect(try Data(contentsOf: root.appendingPathComponent("aggregates-v1.json")) == saved)
}
