import Foundation
import Testing
import StillCore

private func growthStore() -> (GrowthHistoryStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalogGrowth-" + UUID().uuidString)
    return (GrowthHistoryStore(directory: directory), directory)
}
private let catalogFingerprint = GrowthFingerprint(scopeID: "catalog", rootID: "home", volumeID: "volume", access: "per-location", rules: "catalog", exclusions: "none", classification: "catalog")
private func location(_ id: String, _ category: String, _ bytes: Int64, measured: Bool = true) -> GrowthAggregate {
    GrowthAggregate(id: "location:" + id, label: "~/" + id, logicalBytes: bytes, dimension: .location, category: category, ruleID: id, measured: measured)
}
private func catalogSnapshot(_ time: Double, _ groups: [GrowthAggregate]) -> GrowthSnapshot {
    GrowthSnapshot(fingerprint: catalogFingerprint, scopeLabel: "Known locations", observedAt: Date(timeIntervalSince1970: time), groups: groups)
}

@Test func catalogComparisonReportsGrowthPerLocationAndPerCategory() async throws {
    let (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = catalogSnapshot(100, [location("npm", "developer", 100), location("yarn", "developer", 50), location("chrome", "browser", 10)])
    #expect(try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch()).state == .firstBaseline)
    let second = catalogSnapshot(200, [location("npm", "developer", 400), location("yarn", "developer", 20), location("chrome", "browser", 30)])
    let result = try await store.record(second, now: second.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .compared)
    #expect(result.logicalDelta == 290)
    #expect(result.groups.first { $0.id == "location:npm" }?.logicalDelta == 300)
    #expect(result.groups.first { $0.id == "location:yarn" }?.logicalDelta == -30)
    #expect(result.groups.first { $0.id == "category:developer" }?.logicalDelta == 270)
    #expect(result.groups.first { $0.id == "category:browser" }?.logicalDelta == 20)
    #expect(result.coverageChanges.isEmpty)
}

@Test func aLocationThatBecomesReadableOrUnreadableIsCoverageNeverGrowth() async throws {
    let (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = catalogSnapshot(100, [location("npm", "developer", 100), location("safari", "browser", 0, measured: false), location("mail", "logs", 500)])
    _ = try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch())
    let second = catalogSnapshot(200, [location("npm", "developer", 150), location("safari", "browser", 9_000, measured: true), location("mail", "logs", 0, measured: false)])
    let result = try await store.record(second, now: second.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .compared)
    #expect(result.logicalDelta == 50)
    #expect(result.groups.first { $0.id == "location:safari" } == nil)
    #expect(result.groups.first { $0.id == "location:mail" } == nil)
    #expect(result.groups.first { $0.id == "category:browser" }?.logicalDelta ?? 0 == 0)
    #expect(result.groups.first { $0.id == "category:logs" }?.logicalDelta ?? 0 == 0)
    #expect(Dictionary(uniqueKeysWithValues: result.coverageChanges.map { ($0.id, $0.kind) }) == ["location:safari": .newlyReadable, "location:mail": .newlyUnreadable])
}

@Test func aLocationNewlyScannedOrNoLongerScannedIsCoverageNeverGrowth() async throws {
    let (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = catalogSnapshot(100, [location("npm", "developer", 100), location("gone", "developer", 700)])
    _ = try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch())
    let second = catalogSnapshot(200, [location("npm", "developer", 100), location("new", "models", 5_000)])
    let result = try await store.record(second, now: second.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.logicalDelta == 0)
    #expect(result.groups.first { $0.id == "category:models" }?.logicalDelta ?? 0 == 0)
    #expect(Dictionary(uniqueKeysWithValues: result.coverageChanges.map { ($0.id, $0.kind) }) == ["location:new": .newlyScanned, "location:gone": .noLongerScanned])
}

@Test func unmeasuredLocationsAreLeftOutOfTheRecordedTotal() {
    let snapshot = catalogSnapshot(100, [location("npm", "developer", 100), location("safari", "browser", 40, measured: false)])
    #expect(snapshot.logicalBytes == 100)
}
