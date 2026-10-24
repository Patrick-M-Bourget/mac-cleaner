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

@Test func readOnlyActivityHistoryExcludesExpiredRecordsWithoutRewritingArchive() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillActivity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root)
    let then = Date(timeIntervalSince1970: 1000)
    let epoch = try await store.recordingEpoch()
    let activity = ScanActivity(startedAt: then, completedAt: then, outcome: .complete,
        locations: [ScanActivityLocation(path: "/Example/Downloads", observedAt: then, outcome: .complete, entryCount: 0, logicalBytes: 0, allocatedBytes: 0)])
    #expect(try await store.recordActivity(activity, now: then, expectedEpoch: epoch))
    let file = root.appendingPathComponent("aggregates-v1.json")
    let original = try Data(contentsOf: file)
    #expect(try await store.activities(now: then.addingTimeInterval(91 * 86400), maintain: false).isEmpty)
    #expect(try Data(contentsOf: file) == original)
}

@Test func activityArchiveRetainsMoreThanThirtyActivitiesAndClearRejectsLateWrites() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillActivity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root)
    let epoch = try await store.recordingEpoch()
    var latest: ScanActivity!
    for index in 0..<35 {
        let time = Date(timeIntervalSince1970: Double(1000 + index))
        latest = ScanActivity(startedAt: time, completedAt: time, outcome: .stopped,
            locations: [ScanActivityLocation(path: "/Example/One"), ScanActivityLocation(path: "/Example/Two")])
        #expect(try await store.recordActivity(latest, now: time, expectedEpoch: epoch))
    }
    let now = Date(timeIntervalSince1970: 1100)
    let reopened = GrowthHistoryStore(directory: root)
    #expect(try await reopened.activities(now: now).count == 35)
    #expect(try await reopened.activities(now: now).first?.id == latest.id)
    try await reopened.clearCompletedHistory()
    #expect(try await store.activities(now: now).isEmpty)
    #expect(try await store.recordActivity(latest, now: now, expectedEpoch: epoch) == false)
    #expect(try await reopened.activities(now: now).isEmpty)
    #expect(try await store.recordActivity(latest, now: now, expectedEpoch: reopened.recordingEpoch()))
}
