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
    /// new `var x: T? = nil` left out of them compiles and is never saved; this catches it. Add a new field's key to the fixture too.
    static func expectEveryPropertyStored(_ value: Any, in keys: some Collection<String>, _ name: String) {
        let properties = Set(Mirror(reflecting: value).children.compactMap(\.label))
        #expect(properties == Set(keys), "\(name): a stored property and the fixture's keys differ")
    }
    static func keys(_ data: Data, at path: [String]) throws -> [String] {
        var object: Any = try JSONSerialization.jsonObject(with: data)
        for key in path { object = try #require((object as? [String: Any])?[key]) }
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
