import Foundation
import Testing
import CacheDropCore

/// What CacheDrop writes to disk, pinned before any rename (#448): each fixture was written by main before the pin, so a
/// renamed property or case that changes a stored key fails here instead of reading old journals, trends or settings as empty.
enum StoredKeysFixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/StoredKeys"))
        return try Data(contentsOf: url)
    }
    /// Decodes the fixture, then checks that encoding it again writes the same JSON: no key added, dropped or renamed.
    static func decodeAndReencode<Value: Codable>(_ type: Value.Type, _ name: String) throws -> Value {
        let data = try data(name)
        let value = try JSONDecoder().decode(type, from: data)
        let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary
        #expect(again == (try JSONSerialization.jsonObject(with: data) as? NSDictionary), "Encoding \(name) again changed its keys")
        return value
    }
    /// Checks that every stored property of `value` is among `keys`, the fixture's keys for it. With explicit `CodingKeys`, a
    /// new `var x: T? = nil` left out of them compiles and is never saved; this catches it. Add a new field's key to the fixture
    /// too. A rename that keeps its stored key (#449) lists it in `renamed`, property name to stored key.
    static func expectEveryPropertyStored(_ value: Any, in keys: some Collection<String>, renamed: [String: String] = [:], _ name: String) {
        let properties = Set(Mirror(reflecting: value).children.compactMap(\.label).map { renamed[$0] ?? $0 })
        #expect(properties == Set(keys), "\(name): a stored property and the fixture's keys differ")
    }
    static func keys(_ data: Data, at path: [String]) throws -> [String] {
        var object: Any = try JSONSerialization.jsonObject(with: data)
        for key in path {
            if let index = Int(key), let array = object as? [Any] { object = array[index] } else { object = try #require((object as? [String: Any])?[key]) }
        }
        return try #require(object as? [String: Any]).map(\.key)
    }
}

private struct JournalFixture: Codable {
    let record: CleanupRecord
    let laterMeasurements: [LaterMeasurement]
    let targetStates: [CleanupTargetState]
    let recoveryFindings: [RecoveryFinding]
    let cleanupActions: [CleanupAction]
}

@Test func theCleanupJournalStillReadsARecordWrittenBeforeThePin() throws {
    let fixture = try StoredKeysFixture.decodeAndReencode(JournalFixture.self, "journal")
    let at = { (s: TimeInterval) in Date(timeIntervalSinceReferenceDate: s) }
    let record = fixture.record
    #expect(record.id == "npm-cache|/Users/x/.npm/_cacache")
    #expect(record.batchID == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    #expect(record.originalURL.path == "/Users/x/.npm/_cacache")
    #expect(record.resourceID == "res-1")
    #expect(record.logicalBytes == 123_456)
    #expect(record.allocatedBytes == 131_072)
    #expect(record.state == .succeeded)
    #expect(record.trashURL?.path == "/Users/x/.Trash/_cacache")
    #expect(record.message == "Moved")
    #expect(record.observedAt == at(800_000_001))
    #expect(record.scopeURL.path == "/Users/x/.npm")
    #expect(record.scopeResourceID == "res-scope")
    #expect(record.volumeID == "vol-a")
    #expect(record.downloadsURL?.path == "/Users/x/Downloads")
    #expect(record.downloadsResourceID == "res-dl")
    #expect(record.modifiedSeconds == 799_999_999)
    #expect(record.modifiedNanoseconds == 42)
    #expect(record.action == "moveToTrash")
    #expect(record.cleanupAction == .trash)
    #expect(record.policyVersion == 3)
    #expect(record.outcomeRecordedAt == at(800_000_002))
    #expect(record.approvedAt == at(800_000_000))
    #expect(record.ruleID == "npm-cache")
    #expect(record.previewOnly == true)
    #expect(record.toolOutput == "pruned 3 images")
    #expect(record.partlyRemoved == false)
    #expect(record.itemName == "Llama 3")
    #expect(record.toolItem == "UDID-1")
    #expect(record.putBackOf == "trash-1")
    #expect(record.emptyOf == "trash-2")
    #expect(record.mayStillBeFinishing == true)
    #expect(record.laterMeasurement == LaterMeasurement(measuredAt: at(800_000_300), finding: .remaining(bytes: 77), afterSeconds: 300))
    #expect(record.reviewOf == "interrupted-1")
    #expect(record.recoveryFinding == .inTrash)

    let data = try StoredKeysFixture.data("journal")
    StoredKeysFixture.expectEveryPropertyStored(record, in: try StoredKeysFixture.keys(data, at: ["record"]), "CleanupRecord")
    StoredKeysFixture.expectEveryPropertyStored(try #require(record.itemCapacity), in: try StoredKeysFixture.keys(data, at: ["record", "itemCapacity"]), "CleanupCapacityObservation")
    StoredKeysFixture.expectEveryPropertyStored(try #require(record.laterMeasurement), in: try StoredKeysFixture.keys(data, at: ["record", "laterMeasurement"]), "LaterMeasurement")

    let item = try #require(record.itemCapacity)
    #expect(item.beforeAvailable == 1_000); #expect(item.afterAvailable == 2_000)
    #expect(item.beforeTotal == 10_000); #expect(item.afterTotal == 10_001)
    #expect(item.beforeVolumeID == "vol-a"); #expect(item.afterVolumeID == "vol-b")
    #expect(item.beforeMetric == "importantUsage"); #expect(item.afterMetric == "available")
    #expect(item.beforeDate == at(800_000_000)); #expect(item.afterDate == at(800_000_010))
    let settled = try #require(record.settledCapacity)
    #expect(settled.beforeAvailable == nil); #expect(settled.afterAvailable == 3_000)
    #expect(settled.beforeTotal == nil); #expect(settled.afterTotal == 10_002)
    #expect(settled.beforeVolumeID == nil); #expect(settled.afterVolumeID == "vol-c")
    #expect(settled.beforeMetric == "available"); #expect(settled.afterMetric == "importantUsage")
    #expect(settled.beforeDate == at(800_000_020)); #expect(settled.afterDate == at(800_000_080))

    #expect(fixture.laterMeasurements == [LaterMeasurement(measuredAt: at(800_000_060), finding: .gone, afterSeconds: 60),
                                          LaterMeasurement(measuredAt: at(800_000_300), finding: .remaining(bytes: 77), afterSeconds: 300),
                                          LaterMeasurement(measuredAt: at(800_000_900), finding: .unmeasured, afterSeconds: 900)])
    #expect(fixture.targetStates == [.pending, .intent, .succeeded, .failed, .skipped, .cancelled, .unknown])
    #expect(fixture.recoveryFindings == [.notStarted, .atOriginalLocation, .inTrash, .gone, .unknown])
    #expect(fixture.cleanupActions == [.delete, .trash, .tool, .evict, .guidance])
}

private struct TrendsEnumsFixture: Codable {
    let dimensions: [GrowthDimension]; let coverages: [GrowthCoverage]; let comparisonStates: [GrowthComparisonState]
    let scanOutcomes: [ScanActivityOutcome]; let categories: [CatalogCategory]
}

@Test func storageTrendsStillReadAHistoryWrittenBeforeThePin() async throws {
    let at = { (s: TimeInterval) in Date(timeIntervalSinceReferenceDate: s) }
    let now = at(800_090_100)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stored-keys-trends-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let file = directory.appendingPathComponent("aggregates-v1.json")
    let fixture = try StoredKeysFixture.data("trends")
    try fixture.write(to: file)
    let store = GrowthHistoryStore(directory: directory)

    let snapshots = try await store.snapshots(now: now)
    #expect(snapshots.map(\.id) == [UUID(uuidString: "2755AF01-DD05-4F6F-9FA0-63144649ECB3"), UUID(uuidString: "494B9606-49E6-4BF6-81A0-F654A417BAA9")])
    #expect(snapshots.map(\.observedAt) == [at(800_000_000), at(800_090_000)])
    #expect(snapshots.map(\.afterCleanup) == [false, true])
    #expect(snapshots.allSatisfy { $0.scopeLabel == "Known locations" && $0.coverage == .complete })
    #expect(snapshots[0].fingerprint == GrowthFingerprint(scopeID: "catalog:known", rootID: "root-1", volumeID: "vol-a", access: "fullDiskAccess",
                                                          rules: "rules-v7", exclusions: "excl-1", classification: "class-2"))
    let groups = snapshots[0].groups
    #expect(groups.map(\.id) == ["folder:/Users/x/Library/Caches", "category:developer", "location:npm-cache"])
    #expect(groups.map(\.label) == ["Caches", "Developer caches and build files", "npm cache"])
    #expect(groups.map(\.logicalBytes) == [1_000, 2_000, 3_000])
    #expect(groups.map(\.dimension) == [.folder, .category, .location])
    #expect(groups.map(\.category) == [nil, .developer, .developer])
    #expect(groups.map(\.ruleID) == [nil, nil, "npm-cache"])
    #expect(groups.map(\.measured) == [nil, nil, false])
    #expect(try await store.comparison(id: snapshots[0].id, now: now).state == .firstBaseline, "The first entry's origin reads back")

    let activity = try #require(try await store.activities(now: now, maintain: false).first)
    #expect(activity.id == UUID(uuidString: "12345678-1234-1234-1234-123456789ABC"))
    #expect(activity.startedAt == at(800_090_000)); #expect(activity.completedAt == at(800_090_020))
    #expect(activity.outcome == .stopped)
    #expect(activity.locations.map(\.path) == ["/Users/x/Library/Caches", "/Users/x/Downloads"])
    let location = activity.locations[0]
    #expect(location.observedAt == at(800_090_010)); #expect(location.outcome == .partial); #expect(location.entryCount == 12)
    #expect(location.logicalBytes == 4_000); #expect(location.allocatedBytes == 4_096); #expect(location.knownLogicalBytes == 3_900)
    #expect(location.reasons == ["accessDenied": 2, "timeLimit": 1])
    #expect(location.baselineID == UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
    StoredKeysFixture.expectEveryPropertyStored(snapshots[0], in: try StoredKeysFixture.keys(fixture, at: ["entries", "0", "snapshot"]), "GrowthSnapshot")
    StoredKeysFixture.expectEveryPropertyStored(snapshots[0].fingerprint, in: try StoredKeysFixture.keys(fixture, at: ["entries", "0", "snapshot", "fingerprint"]), "GrowthFingerprint")
    StoredKeysFixture.expectEveryPropertyStored(groups[2], in: try StoredKeysFixture.keys(fixture, at: ["entries", "0", "snapshot", "groups", "2"]), "GrowthAggregate")
    StoredKeysFixture.expectEveryPropertyStored(activity, in: try StoredKeysFixture.keys(fixture, at: ["activities", "0"]), "ScanActivity")
    StoredKeysFixture.expectEveryPropertyStored(location, in: try StoredKeysFixture.keys(fixture, at: ["activities", "0", "locations", "0"]), "ScanActivityLocation")
    let empty = activity.locations[1]
    #expect(empty.observedAt == nil && empty.outcome == nil && empty.entryCount == nil && empty.reasons.isEmpty && empty.baselineID == nil)

    // Saving it again writes the same keys: the store re-records the same scan in place.
    try await store.recordActivity(activity, now: now, expectedEpoch: try await store.recordingEpoch())
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? NSDictionary
    #expect(saved == (try JSONSerialization.jsonObject(with: fixture) as? NSDictionary), "Saving the history again changed its keys")

    let enums = try StoredKeysFixture.decodeAndReencode(TrendsEnumsFixture.self, "trends-enums")
    #expect(enums.dimensions == [.folder, .category, .location])
    #expect(enums.coverages == [.complete, .partial, .cancelled, .unmeasured])
    #expect(enums.comparisonStates == [.firstBaseline, .clearedBaseline, .missingBaseline, .coverageChanged, .unknown, .compared, .waitingForBaseline])
    #expect(enums.scanOutcomes == [.complete, .partial, .stopped, .failed])
    // A scan's `reasons` are keyed by these raw values, and a history with a key it doesn't know reads as corrupt.
    for reason in ["excludedScope", "exclusionUnavailable", "directoryChanged", "timeLimit", "entryLimit", "issueLimit", "depthLimit", "readFailed",
                   "metadataUnavailable", "differentVolume", "accessDenied", "accessRevoked", "locationUnavailable"] {
        #expect(ScanIssue.Reason(rawValue: reason) != nil, "\(reason) is still a scan issue's stored reason")
    }
    #expect(enums.categories == [.developer, .browser, .downloads, .system, .models, .updaters, .logs, .icloud, .files, .managed, .leftovers, .apps])
}
