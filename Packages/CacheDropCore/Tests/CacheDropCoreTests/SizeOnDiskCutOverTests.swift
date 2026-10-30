import Foundation
import Testing
import CacheDropCore

/// #447 (Decision 94): Storage trends store sizes on disk from now on. A snapshot saved before then is never compared, so trends
/// start again once two new scans exist. Nothing is migrated: older snapshots still decode and age out as before.
private let hour: Double = 3_600
private let fingerprint = StorageTrendsFingerprint(scopeID: "catalog:home", rootID: "home", volumeID: "volume", access: "per-location", rules: "catalog", exclusions: "none", classification: "catalog")
private func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: 1_000_000 + hours * hour) }
private func scan(_ hours: Double, _ bytes: Int64) -> StorageTrendsSnapshot {
    StorageTrendsSnapshot(fingerprint: fingerprint, scopeLabel: "Known locations", observedAt: at(hours),
                   groups: [StorageTrendsAggregate(id: "location:npm", label: "~/.npm", logicalBytes: bytes, dimension: .location, category: .developer, ruleID: "npm", measured: true)])
}
/// A store whose history holds `hours`' scans as saved before #447: the same file, without the snapshots' `onDisk` key.
private func storeWithEarlierScans(_ hours: [Double]) async throws -> (StorageTrendsHistoryStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCutOver-" + UUID().uuidString)
    let store = StorageTrendsHistoryStore(directory: directory)
    for hour in hours { _ = try await store.record(scan(hour, 100), now: at(hour), expectedEpoch: try await store.recordingEpoch()) }
    let file = directory.appendingPathComponent("aggregates-v1.json")
    var archive = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    archive["entries"] = try #require(archive["entries"] as? [[String: Any]]).map { entry in
        var entry = entry, snapshot = entry["snapshot"] as! [String: Any]
        snapshot.removeValue(forKey: "onDisk"); entry["snapshot"] = snapshot; return entry
    }
    try JSONSerialization.data(withJSONObject: archive).write(to: file)
    return (store, directory)
}
private func record(_ snapshot: StorageTrendsSnapshot, in store: StorageTrendsHistoryStore) async throws -> StorageTrendsComparison {
    try await store.record(snapshot, now: snapshot.observedAt, expectedEpoch: try await store.recordingEpoch())
}

@Test func aScanSavedBeforeSizesOnDiskIsNeverTheBaseline() async throws {
    let (store, directory) = try await storeWithEarlierScans([0])
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = try await record(scan(30, 500), in: store)
    #expect(result.state == .waitingForBaseline, "No trends yet: the earlier scan isn't compared")
    #expect(result.from == nil && result.logicalDelta == nil)
}

@Test func beforeANewScanTheLatestEarlierScanShowsNoTrends() async throws {
    let (store, directory) = try await storeWithEarlierScans([0, 30])
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshots = try await store.snapshots(now: at(31))
    #expect(snapshots.count == 2, "Older snapshots still decode")
    #expect(snapshots.allSatisfy { !$0.sizesOnDisk })
    let latest = try await store.comparison(id: try #require(snapshots.last).id, now: at(31))
    #expect(latest.state != .compared && latest.logicalDelta == nil, "Two earlier scans a day apart aren't compared")
    #expect(latest.current?.id == snapshots.last?.id)
}

@Test func trendsStartAgainOnceTwoNewScansADayApartExist() async throws {
    let (store, directory) = try await storeWithEarlierScans([0, 1])
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try await record(scan(30, 400), in: store)
    let result = try await record(scan(55, 650), in: store)
    #expect(result.state == .compared)
    #expect(result.from == at(30), "Compared with the first new scan, never an earlier one")
    #expect(result.logicalDelta == 250)
    #expect(try await store.snapshots(now: at(55)).count == 4, "Nothing is migrated or dropped")
}

@Test func aLegacyCurrentScanIsNeverComparedWithAnEarlierSizeOnDiskScan() async throws {
    let (store, directory) = try await storeWithEarlierScans([0, 30])
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("aggregates-v1.json")
    var archive = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var entries = try #require(archive["entries"] as? [[String: Any]])
    var earlier = try #require(entries[0]["snapshot"] as? [String: Any])
    earlier["onDisk"] = true; entries[0]["snapshot"] = earlier; archive["entries"] = entries
    try JSONSerialization.data(withJSONObject: archive).write(to: file)
    let snapshots = try await store.snapshots(now: at(31))
    #expect(snapshots.map(\.sizesOnDisk) == [true, false])
    let current = try await store.comparison(id: try #require(snapshots.last).id, now: at(31))
    #expect(current.state == .waitingForBaseline)
    #expect(current.from == nil && current.logicalDelta == nil, "A logical size is never compared with a size on disk")
}
