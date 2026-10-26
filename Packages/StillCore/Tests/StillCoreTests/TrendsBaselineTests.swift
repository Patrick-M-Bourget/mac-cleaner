import Foundation
import Testing
import StillCore

/// #126: Storage trends compares against the newest scan about a day older that isn't a rescan right after a cleanup.
private let hour: Double = 3_600
private let fingerprint = GrowthFingerprint(scopeID: "catalog:home", rootID: "home", volumeID: "volume", access: "per-location", rules: "catalog", exclusions: "none", classification: "catalog")
private func scan(_ hours: Double, _ bytes: Int64, afterCleanup: Bool = false, exclusions: String = "none") -> GrowthSnapshot {
    let print = GrowthFingerprint(scopeID: fingerprint.scopeID, rootID: fingerprint.rootID, volumeID: fingerprint.volumeID, access: fingerprint.access,
                                  rules: fingerprint.rules, exclusions: exclusions, classification: fingerprint.classification)
    return GrowthSnapshot(fingerprint: print, scopeLabel: "Known locations", observedAt: Date(timeIntervalSince1970: 1_000_000 + hours * hour),
                          groups: [GrowthAggregate(id: "location:npm", label: "~/.npm", logicalBytes: bytes, dimension: .location, category: .developer, ruleID: "npm", measured: true)],
                          afterCleanup: afterCleanup)
}
private func record(_ snapshots: [GrowthSnapshot]) async throws -> (GrowthHistoryStore, GrowthComparison, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillTrends-" + UUID().uuidString)
    let store = GrowthHistoryStore(directory: directory)
    var last = GrowthComparison.unknown
    for snapshot in snapshots { last = try await store.record(snapshot, now: snapshot.observedAt, expectedEpoch: try await store.recordingEpoch()) }
    return (store, last, directory)
}

@Test func theBaselineIsTheNewestScanAtLeastADayOlderNotTheOneJustBefore() async throws {
    let (_, result, directory) = try await record([scan(0, 100), scan(10, 300), scan(30, 500), scan(48, 900), scan(49, 950)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .compared)
    // 49 h: the scans at 48 h and 30 h are too recent; 10 h is the newest at least a day older.
    #expect(result.from == Date(timeIntervalSince1970: 1_000_000 + 10 * hour))
    #expect(result.logicalDelta == 650)
}

@Test func aScanJustUnderADayOlderStillCountsAsADayOld() async throws {
    // A daily check at about the same time each day compares with the day before.
    let (_, result, directory) = try await record([scan(0, 100), scan(23, 400)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .compared)
    #expect(GrowthHistoryStore.minimumBaselineAge >= 20 * hour && GrowthHistoryStore.minimumBaselineAge <= 24 * hour)
}

@Test func aRescanRightAfterACleanupIsNeverTheBaseline() async throws {
    let (_, result, directory) = try await record([scan(0, 1_000), scan(1, 100, afterCleanup: true), scan(30, 200)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .compared)
    #expect(result.from == Date(timeIntervalSince1970: 1_000_000))
    #expect(result.logicalDelta == -800)
}

@Test func aRescanRightAfterACleanupIsStillTheLatestScan() async throws {
    let (store, result, directory) = try await record([scan(0, 1_000), scan(30, 100, afterCleanup: true)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .compared && result.logicalDelta == -900)
    #expect(try await store.latest(now: Date(timeIntervalSince1970: 1_000_000 + 30 * hour)).current?.afterCleanup == true)
}

@Test func withOnlyRecentScansTheBaselineIsRecordedAndTrendsWaitForTomorrow() async throws {
    let (store, result, directory) = try await record([scan(0, 100), scan(0.1, 200), scan(2, 300)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .waitingForBaseline)
    #expect(result.from == nil && result.logicalDelta == nil)
    #expect(try await store.latest(now: Date(timeIntervalSince1970: 1_000_000 + 2 * hour)).state == .waitingForBaseline)
}

@Test func onlyCleanupRescansOlderThanADayAlsoWaitForTomorrow() async throws {
    let (_, result, directory) = try await record([scan(0, 100, afterCleanup: true), scan(30, 200)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .waitingForBaseline)
}

@Test func aSettingsChangeAfterTheBaselineStillStartsANewBaseline() async throws {
    let (_, result, directory) = try await record([scan(0, 100), scan(30, 200, exclusions: "changed")])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .coverageChanged)
    // An hour later, the newest day-old scan is still from before the change.
    let (_, later, other) = try await record([scan(0, 100), scan(30, 200, exclusions: "changed"), scan(31, 300, exclusions: "changed")])
    defer { try? FileManager.default.removeItem(at: other) }
    #expect(later.state == .coverageChanged)
}

@Test func scansRecordedBeforeTheCleanupMarkerExistedDecodeAsOrdinaryScans() throws {
    let data = Data(#"{"id":"\#(UUID().uuidString)","fingerprint":{"scopeID":"s","rootID":"r","volumeID":"v","access":"a","rules":"r","exclusions":"e","classification":"c"},"scopeLabel":"Known locations","observedAt":0,"groups":[{"id":"g","label":"G","logicalBytes":1,"dimension":"location"}],"coverage":"complete"}"#.utf8)
    let snapshot = try JSONDecoder().decode(GrowthSnapshot.self, from: data)
    #expect(snapshot.afterCleanup == false)
}

// MARK: Retention (#146)

@Test func manyRescansWithinAnHourNeverPushOutYesterdaysBaseline() async throws {
    // ⌘R, the Full Disk Access rescan and post-cleanup rescans: 40 scans within an hour, a day after the last one.
    let rescans = (0..<40).map { scan(24 + Double($0) * 1.5 / 60, 200 + Int64($0), afterCleanup: $0 % 3 == 0) }
    let (store, result, directory) = try await record([scan(0, 100)] + rescans)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(result.state == .compared)
    #expect(result.from == Date(timeIntervalSince1970: 1_000_000))
    let now = Date(timeIntervalSince1970: 1_000_000 + 25 * hour)
    #expect(try await store.snapshots(now: now).count <= 30)
    #expect(try await store.latest(now: now).from == Date(timeIntervalSince1970: 1_000_000))
}

@Test func olderHistoryThinsToOneScanADay() async throws {
    // Three scans a day for 15 days: 45 scans, more than the 30 kept.
    let days = 15
    let scans = (0..<days).flatMap { day in [8.0, 12, 18].map { scan(Double(day) * 24 + $0, 100) } }
    let (store, _, directory) = try await record(scans)
    defer { try? FileManager.default.removeItem(at: directory) }
    let kept = try await store.snapshots(now: try #require(scans.last).observedAt)
    #expect(kept.count <= 30)
    // Every day still has a scan, and the newest few are all kept.
    let calendar = Calendar.current
    #expect(Set(kept.map { calendar.startOfDay(for: $0.observedAt) }) == Set(scans.map { calendar.startOfDay(for: $0.observedAt) }))
    #expect(kept.suffix(5).map(\.observedAt) == scans.suffix(5).map(\.observedAt))
}

@Test func scansOlderThan90DaysAreStillDropped() async throws {
    let (store, result, directory) = try await record([scan(0, 100), scan(91 * 24, 200)])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 1_000_000 + 91 * 24 * hour)).count == 1)
    #expect(result.state == .missingBaseline || result.state == .firstBaseline)
}

@Test func theHistoryStillFitsItsSizeLimit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillTrends-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory, policy: GrowthRetention(bytes: 4_000))
    for index in 0..<20 {
        let snapshot = scan(Double(index) * 24, 100)
        _ = try await store.record(snapshot, now: snapshot.observedAt, expectedEpoch: try await store.recordingEpoch())
    }
    let size = try #require(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("aggregates-v1.json").path)[.size] as? Int)
    #expect(size <= 4_000)
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 1_000_000 + 19 * 24 * hour)).count < 20)
}
