import Foundation
import Testing
import StillCore

@Test func completedCompatibleAggregatesCompareAdditionsAndRemovalsWithoutFileRecords() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory)
    let fingerprint = GrowthFingerprint(scopeID: "scope", rootID: "root", volumeID: "volume", access: "complete", rules: "rules1", exclusions: "none", classification: "folders-v1")
    let first = GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Selected folder", observedAt: Date(timeIntervalSince1970: 100), groups: [.init(id: "folder:one", label: "One", logicalBytes: 10), .init(id: "folder:two", label: "Two", logicalBytes: 5)])
    #expect(try await store.record(first, now: first.observedAt).state == .firstBaseline)
    let second = GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Selected folder", observedAt: Date(timeIntervalSince1970: 200), groups: [.init(id: "folder:one", label: "One", logicalBytes: 20)])
    let result = try await store.record(second, now: second.observedAt)
    #expect(result.state == .compared)
    #expect(result.logicalDelta == 5)
    #expect(result.groups.first { $0.id == "folder:one" }?.logicalDelta == 10)
    #expect(result.groups.first { $0.id == "folder:two" }?.logicalDelta == -5)
    #expect(result.from == first.observedAt && result.to == second.observedAt)
    let reopened = GrowthHistoryStore(directory: directory)
    #expect(try await reopened.latest(now: second.observedAt).state == .compared)
}

@Test func incompleteUnknownObservationsNeverReplaceCompletedBaselineAndCoverageChangesAreNotGrowth() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory)
    let original = GrowthFingerprint(scopeID: "scope", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    func snapshot(_ fingerprint: GrowthFingerprint, _ time: Double, _ coverage: GrowthCoverage = .complete) -> GrowthSnapshot {
        GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Folder", observedAt: Date(timeIntervalSince1970: time), groups: [.init(id: "category:files", label: "Files", logicalBytes: 10)], coverage: coverage)
    }
    _ = try await store.record(snapshot(original, 100), now: Date(timeIntervalSince1970: 100))
    for coverage in [GrowthCoverage.partial, .cancelled, .unmeasured] {
        #expect(try await store.record(snapshot(original, 110, coverage), now: Date(timeIntervalSince1970: 110)).state == .unknown)
    }
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 1000)).count == 1)
    for changed in [
        GrowthFingerprint(scopeID: "other", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"),
        GrowthFingerprint(scopeID: "scope", rootID: "new-root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"),
        GrowthFingerprint(scopeID: "scope", rootID: "root", volumeID: "other", access: "complete", rules: "two", exclusions: "custom", classification: "two")
    ] {
        let latest = try await store.record(snapshot(changed, Double(200 + (try await store.snapshots(now: Date(timeIntervalSince1970: 1000)).count))), now: Date(timeIntervalSince1970: 1000))
        #expect(latest.state == .coverageChanged)
        #expect(latest.logicalDelta == nil)
    }
}

@Test func retentionExpiresAtReadAndClearingIsDistinctWhileRecoveryRecordsRemainUntouched() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let journal = directory.appendingPathComponent("unresolved-recovery.sqlite")
    try Data("unresolved".utf8).write(to: journal)
    let fingerprint = GrowthFingerprint(scopeID: "scope", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    let store = GrowthHistoryStore(directory: directory, policy: GrowthRetention(days: 1, baselines: 2))
    for time in [100.0, 200, 300] {
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Folder", observedAt: Date(timeIntervalSince1970: time), groups: [.init(id: "files", label: "Files", logicalBytes: 1)]), now: Date(timeIntervalSince1970: time))
    }
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 300)).count == 2)
    #expect(try await store.latest(now: Date(timeIntervalSince1970: 90000)).state == .missingBaseline)
    try await store.clearCompletedHistory()
    #expect(try await store.latest(now: Date(timeIntervalSince1970: 90000)).state == .clearedBaseline)
    #expect(try Data(contentsOf: journal) == Data("unresolved".utf8))
    try await store.resetHistory()
    #expect(try await store.latest(now: Date(timeIntervalSince1970: 90000)).state == .firstBaseline)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("aggregates-v1.json").path))
    #expect(try Data(contentsOf: journal) == Data("unresolved".utf8))
}

@Test func scanCapturePersistsFolderAndCategoryAggregatesButNeverRawFilenamesOrUnmeasuredPackages() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowthScan-" + UUID().uuidString)
    let data = root.appendingPathComponent("State"), scope = root.appendingPathComponent("Selected")
    let folder = scope.appendingPathComponent("Projects")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1, 2, 3]).write(to: folder.appendingPathComponent("private-filename.pdf"))
    let store = GrowthHistoryStore(directory: data)
    let recorder = GrowthScanRecorder(store: store)
    let token = try await recorder.begin(scope: scope)
    let result = try await recorder.complete(try await FolderScanner().scan(scope), token: token)
    #expect(result.state == .firstBaseline)
    #expect(result.current?.logicalBytes == 3)
    #expect(result.current?.groups.contains { $0.label == "Projects" && $0.logicalBytes == 3 } == true)
    #expect(result.current?.groups.contains { $0.label == "Documents" && $0.logicalBytes == 3 } == true)
    let persisted = try String(contentsOf: data.appendingPathComponent("aggregates-v1.json"), encoding: .utf8)
    #expect(!persisted.contains("private-filename"))
    try FileManager.default.createDirectory(at: scope.appendingPathComponent("Library.photoslibrary"), withIntermediateDirectories: true)
    let next = try await recorder.begin(scope: scope)
    #expect(try await recorder.complete(try await FolderScanner().scan(scope), token: next).state == .unknown)
    #expect(try await store.snapshots().count == 1)
}

@Test func aggregateArchiveRejectsCorruptionAndNeverExceedsBytePolicy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory, policy: GrowthRetention(bytes: 1600))
    let fingerprint = GrowthFingerprint(scopeID: "scope", rootID: "root", volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one")
    for i in 0..<10 {
        let date = Date(timeIntervalSince1970: Double(100 + i))
        _ = try await store.record(GrowthSnapshot(fingerprint: fingerprint, scopeLabel: "Folder", observedAt: date, groups: [.init(id: "files", label: "Files", logicalBytes: Int64(i))]), now: date)
    }
    let file = directory.appendingPathComponent("aggregates-v1.json")
    #expect(try Data(contentsOf: file).count <= 1600)
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 120)).count < 10)
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var entries = try #require(json["entries"] as? [[String: Any]])
    var snapshot = try #require(entries[0]["snapshot"] as? [String: Any])
    let groups = try #require(snapshot["groups"] as? [[String: Any]])
    snapshot["groups"] = groups + groups; entries[0]["snapshot"] = snapshot; json["entries"] = entries
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    do { _ = try await GrowthHistoryStore(directory: directory).latest(); Issue.record("Corrupt aggregate archive accepted") }
    catch { }
}

@Test func aggregateStoreRejectsSymlinkedStorageWithoutTouchingItsDestination() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    let destination = directory.appendingPathComponent("Destination"), link = directory.appendingPathComponent("Growth")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    do { try await GrowthHistoryStore(directory: link).clearCompletedHistory(); Issue.record("Symlinked store accepted") }
    catch { }
    #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
}

@Test func cachedScanAndReplacedScopeCannotBecomeCompletedGrowthBaselines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    let scope = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GrowthHistoryStore(directory: root.appendingPathComponent("History")), recorder = GrowthScanRecorder(store: store)
    let previous = try await FolderScanner().scan(scope)
    let token = try await recorder.begin(scope: scope)
    #expect(try await recorder.complete(previous, token: token).state == .unknown)
    let other = root.appendingPathComponent("Original")
    try FileManager.default.moveItem(at: scope, to: other)
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: false)
    #expect(try await recorder.complete(try await FolderScanner().scan(scope), token: token).state == .unknown)
    #expect(try await store.snapshots().isEmpty)
}

@Test func interleavedScopesCompareTheirOwnLatestCompletedObservation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillGrowth-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory)
    func snapshot(_ scope: String, _ time: Double, _ bytes: Int64) -> GrowthSnapshot {
        .init(fingerprint: .init(scopeID: scope, rootID: scope, volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: scope, observedAt: Date(timeIntervalSince1970: time), groups: [.init(id: "files", label: "Files", logicalBytes: bytes)])
    }
    _ = try await store.record(snapshot("A", 100, 3), now: Date(timeIntervalSince1970: 100))
    _ = try await store.record(snapshot("B", 200, 100), now: Date(timeIntervalSince1970: 200))
    let result = try await store.record(snapshot("A", 300, 8), now: Date(timeIntervalSince1970: 300))
    #expect(result.state == .compared && result.logicalDelta == 5)
    #expect(result.from == Date(timeIntervalSince1970: 100))
}
