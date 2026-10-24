import Foundation
import Testing
import StillCore

@Test func scanActivityArchiveRejectsRawErrorDescriptionsWithoutReplacingSavedActivity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillActivity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root)
    let now = Date(timeIntervalSince1970: 1000)
    let epoch = try await store.recordingEpoch()
    let valid = ScanActivity(startedAt: now.addingTimeInterval(-2), completedAt: now, outcome: .partial,
        locations: [ScanActivityLocation(path: "/Example/Downloads", observedAt: now, outcome: .partial, entryCount: 2, knownLogicalBytes: 8, reasons: ["readFailed": 1])])
    #expect(try await store.recordActivity(valid, now: now, expectedEpoch: epoch))
    let invalid = ScanActivity(startedAt: now, completedAt: now, outcome: .failed,
        locations: [ScanActivityLocation(path: "/Example/Downloads", observedAt: now, outcome: .failed, reasons: ["Private-file.pdf failed to read": 1])])
    await #expect(throws: (any Error).self) { try await store.recordActivity(invalid, now: now, expectedEpoch: epoch) }
    let reopened = GrowthHistoryStore(directory: root)
    #expect(try await reopened.activities(now: now).map(\.id) == [valid.id])
}

@Test func unavailableScanArchiveDoesNotBecomeAnEmptyHistoryOrReplaceDanglingLink() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillActivity-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = root.appendingPathComponent("aggregates-v1.json")
    let missing = root.appendingPathComponent("Missing-records")
    try FileManager.default.createSymbolicLink(at: archive, withDestinationURL: missing)
    let store = GrowthHistoryStore(directory: root)
    await #expect(throws: (any Error).self) { try await store.activities() }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: archive.path) == missing.path)
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}
