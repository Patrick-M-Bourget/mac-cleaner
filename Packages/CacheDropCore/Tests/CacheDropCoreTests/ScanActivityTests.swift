import Foundation
import Testing
import CacheDropCore

@Test func scanActivityArchiveRejectsRawErrorDescriptionsWithoutReplacingSavedActivity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
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

@Test func activitySummaryRetainsUnmeasuredCoverageWithoutChildFileNames() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: scope.appendingPathComponent("private-library.photoslibrary"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let scan = try await FolderScanner().scan(scope)
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("State"))
    let now = Date()
    let activity = ScanActivity(startedAt: scan.observedAt.addingTimeInterval(-1), completedAt: now, outcome: .complete, locations: [.init(scan: scan)])
    #expect(try await store.recordActivity(activity, now: now, expectedEpoch: store.recordingEpoch()))
    let location = try #require(try await store.activities(now: now).first?.locations.first)
    #expect(location.reasons["unmeasuredContents"] == 1)
    #expect(location.logicalBytes == nil)
    #expect(location.allocatedBytes == nil)
    let saved = try String(contentsOf: root.appendingPathComponent("State/aggregates-v1.json"), encoding: .utf8)
    #expect(!saved.contains("private-library"))
}

@Test func scanAndGrowthRecordsShareEncodedBudgetAndPreserveLegacyBaseline() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root, policy: .init(bytes: 1400))
    let time = Date(timeIntervalSince1970: 1000)
    let epoch = try await store.recordingEpoch()
    let baseline = GrowthSnapshot(fingerprint: .init(scopeID: "scope", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: "Folder", observedAt: time, groups: [.init(id: "files", label: "Files", logicalBytes: 10)])
    _ = try await store.record(baseline, now: time, expectedEpoch: epoch)
    let file = root.appendingPathComponent("aggregates-v1.json")
    // A genuine pre-activity v1 archive has no activities key.
    var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    legacy.removeValue(forKey: "activities")
    try JSONSerialization.data(withJSONObject: legacy).write(to: file)
    let first = ScanActivity(startedAt: time, completedAt: time, outcome: .partial, locations: [.init(path: "/Example/Downloads", observedAt: time, outcome: .partial, knownLogicalBytes: 4)])
    #expect(try await store.recordActivity(first, now: time, expectedEpoch: epoch))
    #expect(try await store.snapshots(now: time).map(\.id) == [baseline.id])
    for index in 1...8 {
        let now = time.addingTimeInterval(Double(index))
        let activity = ScanActivity(startedAt: now, completedAt: now, outcome: .failed, locations: [.init(path: "/Example/Downloads", outcome: .failed)])
        #expect(try await store.recordActivity(activity, now: now, expectedEpoch: epoch))
    }
    let later = time.addingTimeInterval(10)
    #expect(try Data(contentsOf: file).count <= 1400)
    #expect(try await store.snapshots(now: later).isEmpty)
    let retained = try await GrowthHistoryStore(directory: root, policy: .init(bytes: 1400)).activities(now: later)
    #expect(retained.count < 9)
    #expect(retained.first?.completedAt == time.addingTimeInterval(8))
}

@Test func invalidOrUnwritableActivityArchiveNeverClaimsSavedOrOverwritesUnknownData() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root)
    let epoch = try await store.recordingEpoch()
    let time = Date(timeIntervalSince1970: 1000)
    let activity = ScanActivity(startedAt: time, completedAt: time, outcome: .failed, locations: [.init(path: "/Example/Downloads", outcome: .failed)])
    let file = root.appendingPathComponent("aggregates-v1.json")
    for bytes in [Data("not JSON".utf8), Data("{\"version\":99,\"entries\":[],\"hadHistory\":false,\"cleared\":false}".utf8)] {
        try bytes.write(to: file)
        await #expect(throws: (any Error).self) { try await store.activities(now: time) }
        await #expect(throws: (any Error).self) { try await store.recordActivity(activity, now: time, expectedEpoch: epoch) }
        #expect(try Data(contentsOf: file) == bytes)
    }
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) { try await store.recordActivity(activity, now: time, expectedEpoch: epoch) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: file.path).isEmpty)
}

@Test func oversizedActivityIsRejectedWholeWhileThirtyBaselineLimitIsGlobal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropActivity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root)
    let epoch = try await store.recordingEpoch()
    for index in 0..<31 {
        let time = Date(timeIntervalSince1970: Double(1000 + index))
        let scope = "Scope-\(index)"
        let snapshot = GrowthSnapshot(fingerprint: .init(scopeID: scope, rootID: scope, volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: scope, observedAt: time, groups: [.init(id: "files", label: "Files", logicalBytes: 1)])
        _ = try await store.record(snapshot, now: time, expectedEpoch: epoch)
    }
    let now = Date(timeIntervalSince1970: 1100)
    let snapshots = try await store.snapshots(now: now)
    #expect(snapshots.count == 30)
    #expect(snapshots.first?.scopeLabel == "Scope-1")
    let smallRoot = root.appendingPathComponent("Small")
    let small = GrowthHistoryStore(directory: smallRoot, policy: .init(bytes: 600))
    let smallEpoch = try await small.recordingEpoch()
    let fitting = ScanActivity(startedAt: now, completedAt: now, outcome: .stopped, locations: [.init(path: "/Example")])
    #expect(try await small.recordActivity(fitting, now: now, expectedEpoch: smallEpoch))
    let oversized = ScanActivity(startedAt: now, completedAt: now, outcome: .stopped, locations: [.init(path: "/" + String(repeating: "a", count: 2000))])
    await #expect(throws: (any Error).self) { try await small.recordActivity(oversized, now: now, expectedEpoch: smallEpoch) }
    #expect(try await GrowthHistoryStore(directory: smallRoot, policy: .init(bytes: 600)).activities(now: now).map(\.id) == [fitting.id])
}

@Test func observedSizeSumsCompleteSizesAndMarksKnownMinimums() {
    let date = Date(timeIntervalSince1970: 1000)
    func activity(_ locations: [ScanActivityLocation]) -> ScanActivity { ScanActivity(startedAt: date, completedAt: date, outcome: .complete, locations: locations) }
    #expect(activity([.init(path: "/A", logicalBytes: 10, knownLogicalBytes: 10), .init(path: "/B", logicalBytes: 5)]).observedSize == ScanActivitySize(bytes: 15, complete: true))
    #expect(activity([.init(path: "/A", logicalBytes: 10), .init(path: "/B", knownLogicalBytes: 4)]).observedSize == ScanActivitySize(bytes: 14, complete: false))
    #expect(activity([.init(path: "/A", logicalBytes: 10), .init(path: "/B")]).observedSize == ScanActivitySize(bytes: 10, complete: false))
    #expect(activity([.init(path: "/A"), .init(path: "/B")]).observedSize == nil)
}
