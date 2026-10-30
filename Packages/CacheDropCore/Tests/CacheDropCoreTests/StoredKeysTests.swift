import Foundation
import Testing
@testable import CacheDropCore

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
    #expect(record.dryRun == true)
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
    StoredKeysFixture.expectEveryPropertyStored(record, in: try StoredKeysFixture.keys(data, at: ["record"]), renamed: ["dryRun": "previewOnly"], "CleanupRecord")
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
    let dimensions: [StorageTrendsDimension]; let coverages: [StorageTrendsCoverage]; let comparisonStates: [StorageTrendsComparisonState]
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
    let store = StorageTrendsHistoryStore(directory: directory)

    let snapshots = try await store.snapshots(now: now)
    #expect(snapshots.map(\.id) == [UUID(uuidString: "2755AF01-DD05-4F6F-9FA0-63144649ECB3"), UUID(uuidString: "494B9606-49E6-4BF6-81A0-F654A417BAA9")])
    #expect(snapshots.map(\.observedAt) == [at(800_000_000), at(800_090_000)])
    #expect(snapshots.map(\.afterCleanup) == [false, true])
    #expect(snapshots.map(\.sizesOnDisk) == [false, true], "A snapshot saved before sizes on disk (#447) reads as not on disk")
    #expect(snapshots.allSatisfy { $0.scopeLabel == "Known locations" && $0.coverage == .complete })
    #expect(snapshots[0].fingerprint == StorageTrendsFingerprint(scopeID: "catalog:known", rootID: "root-1", volumeID: "vol-a", access: "fullDiskAccess",
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
    #expect(location.logicalBytes == 4_000); #expect(location.allocatedBytes == 4_096); #expect(location.knownLogicalBytes == 3_900); #expect(location.knownAllocatedBytes == 3_968)
    #expect(location.reasons == ["accessDenied": 2, "timeLimit": 1])
    #expect(location.baselineID == UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
    StoredKeysFixture.expectEveryPropertyStored(snapshots[1], in: try StoredKeysFixture.keys(fixture, at: ["entries", "1", "snapshot"]), "StorageTrendsSnapshot")
    StoredKeysFixture.expectEveryPropertyStored(snapshots[0].fingerprint, in: try StoredKeysFixture.keys(fixture, at: ["entries", "0", "snapshot", "fingerprint"]), "StorageTrendsFingerprint")
    StoredKeysFixture.expectEveryPropertyStored(groups[2], in: try StoredKeysFixture.keys(fixture, at: ["entries", "0", "snapshot", "groups", "2"]), "StorageTrendsAggregate")
    StoredKeysFixture.expectEveryPropertyStored(activity, in: try StoredKeysFixture.keys(fixture, at: ["activities", "0"]), "ScanActivity")
    StoredKeysFixture.expectEveryPropertyStored(location, in: try StoredKeysFixture.keys(fixture, at: ["activities", "0", "locations", "0"]), "ScanActivityLocation")
    let empty = activity.locations[1]
    #expect(empty.observedAt == nil && empty.outcome == nil && empty.entryCount == nil && empty.knownAllocatedBytes == nil && empty.reasons.isEmpty && empty.baselineID == nil)

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
    let issueReasons = ["excludedScope", "exclusionUnavailable", "directoryChanged", "timeLimit", "entryLimit", "issueLimit", "depthLimit", "readFailed",
                        "metadataUnavailable", "differentVolume", "accessDenied", "accessRevoked", "locationUnavailable"]
    for reason in issueReasons { #expect(ScanIssue.Reason(rawValue: reason) != nil, "\(reason) is still a scan issue's stored reason") }
    // Every stored reason, the two `ScanActivityLocation(scan:)` writes as literals included, is still accepted when saved.
    let reasons = Dictionary(uniqueKeysWithValues: (issueReasons + ["customExcludedBoundary", "unmeasuredContents"]).map { ($0, 1) })
    let every = ScanActivity(startedAt: at(800_090_030), completedAt: at(800_090_040), outcome: .partial,
                             locations: [ScanActivityLocation(path: "/Users/x/Music", observedAt: at(800_090_035), outcome: .partial, reasons: reasons)])
    #expect(try await store.recordActivity(every, now: now, expectedEpoch: try await store.recordingEpoch()))
    #expect(try await store.activities(now: now, maintain: false).first?.locations.first?.reasons == reasons)
    #expect(enums.categories == [.developer, .browser, .downloads, .system, .models, .updaters, .logs, .icloud, .files, .managed, .leftovers, .apps])
}

/// Copies a fixture into a fresh store folder as `file`, owner-only as the stores require.
private func storeFolder(with fixture: Data, as file: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stored-keys-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try fixture.write(to: directory.appendingPathComponent(file))
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent(file).path)
    return directory
}
private func json(_ url: URL) throws -> NSDictionary? { try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary }

@Test func rememberedLocationsStillReadWhatWasSavedBeforeThePin() throws {
    let fixture = try StoredKeysFixture.data("scopes")
    let directory = try storeFolder(with: fixture, as: "scopes-v1.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registry = ScopeRegistry(directory: directory)
    let scopes = try registry.list()
    #expect(scopes.map(\.id) == [UUID(uuidString: "C9B4E101-7090-4FD0-AFFB-4937C2235F88"), UUID(uuidString: "21698AE2-FDA7-46CC-A708-8F393EFB35CB")])
    #expect(scopes.map(\.path) == ["/Users/x/Music", "/Users/x/Downloads"])
    #expect(scopes.map(\.isIncluded) == [false, true])
    #expect(scopes.map(\.kind) == [.inspection, .downloads])
    StoredKeysFixture.expectEveryPropertyStored(scopes[0], in: try StoredKeysFixture.keys(fixture, at: ["scopes", "0"]), "RememberedScope")
    // Saving again (the bookmark is kept as read) writes the same file.
    try registry.setIncluded(false, id: scopes[0].id)
    #expect(try json(directory.appendingPathComponent("scopes-v1.json")) == (try JSONSerialization.jsonObject(with: fixture) as? NSDictionary))
}

@Test func protectedItemsStillReadWhatWasSavedBeforeThePin() async throws {
    let fixture = try StoredKeysFixture.data("rules")
    let directory = try storeFolder(with: fixture, as: "rules-v1.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProtectedItemsStore(directory: directory)
    let rules = try await store.policy().rules
    #expect(rules.map(\.id) == [UUID(uuidString: "015E69C6-7BA5-4963-A9E9-648E82CF050B"), UUID(uuidString: "7FF09155-338A-4666-AB36-F198E82C6DBE")])
    #expect(rules.map(\.path) == ["/Users/x/Music", "/Users/x/Music Projects/song.wav"])
    #expect(rules.allSatisfy { $0.volumeID == "00000000-0000-4000-8000-0000000000AA" })
    #expect(rules.map(\.boundary) == [.folder, .file])
    StoredKeysFixture.expectEveryPropertyStored(rules[0], in: try StoredKeysFixture.keys(fixture, at: ["rules", "0"]), "ProtectedItemsRule")
    // The fingerprint Storage trends keeps for these rules depends on the boundary's raw value, so it must not move either.
    #expect(ProtectedItemsPolicy(rules: rules).fingerprint == "path-volume-v1:3af3cc28b5581eea62b5df0f41b68c59c9e9f28805536468aebfff16e8431fd3")
    try await store.remove(UUID())
    #expect(try json(directory.appendingPathComponent("rules-v1.json")) == (try JSONSerialization.jsonObject(with: fixture) as? NSDictionary))
}

private final class MemoryPreferences: MigrationPreferences, @unchecked Sendable {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@Test func settingsKeepTheirStoredKeysAndValues() {
    // Defaults keys, as the app's defaults domain holds them today.
    #expect(PreferenceKeys.dryRun == "CacheDropDryRun")
    #expect(PreferenceKeys.showsMenuBarItem == "CacheDrop.showsMenuBarItem")
    #expect(PreferenceKeys.startAtLogin == "CacheDrop.startAtLogin")
    #expect(FirstRunWelcome.stateKey == "CacheDrop.welcomeState")
    #expect(LegacyStillMigration.completedKey == "CacheDrop.migratedFromStill")
    #expect(RenamedPreferenceKeys.completedKey == "CacheDrop.renamedPreferenceKeys")
    let preferences = MemoryPreferences()
    #expect(FirstRunWelcome(preferences: preferences).shouldShow(migration: nil, stateExisted: false))
    #expect(preferences.values["CacheDrop.welcomeState"] as? String == "pending")
    FirstRunWelcome(preferences: preferences).markSeen()
    #expect(preferences.values["CacheDrop.welcomeState"] as? String == "seen")
    // Raw values stored as values: the appearance file's contents, and each journal record's capacity metric.
    #expect(AppearanceChoice.allCases.map(\.rawValue) == ["Automatic", "Light", "Dark"])
    #expect([CapacityMetric.important, .available].map(\.rawValue) == ["important", "available"])
    #expect([RememberedScope.Kind.downloads, .inspection].map(\.rawValue) == ["downloads", "inspection"])
    #expect([ProtectedItemsRule.Boundary.file, .folder].map(\.rawValue) == ["file", "folder"])
}
