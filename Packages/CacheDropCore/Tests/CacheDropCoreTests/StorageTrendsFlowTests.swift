import Foundation
import Testing
@testable import CacheDropCore

@Test func firstObservationOfAnotherLocationDoesNotCompareUnrelatedScopes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StorageTrendsHistoryStore(directory: directory, minimumBaselineAge: 0)
    func observation(_ scope: String, _ time: Double, _ bytes: Int64) -> StorageTrendsSnapshot {
        StorageTrendsSnapshot(fingerprint: .init(scopeID: scope, rootID: scope, volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: "Same name", observedAt: Date(timeIntervalSince1970: time), groups: [.init(id: "root", label: "Root files", logicalBytes: bytes)])
    }
    let first = observation("A", 100, 10)
    _ = try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch())
    let other = observation("B", 200, 500)
    let result = try await store.record(other, now: other.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .firstBaseline)
    #expect(result.from == nil)
    #expect(result.logicalDelta == nil)
    let next = observation("A", 300, 14)
    let comparison = try await store.record(next, now: next.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(comparison.state == .compared)
    #expect(comparison.from == first.observedAt)
    #expect(comparison.logicalDelta == 4)
}

@Test func expiredUnrelatedHistoryDoesNotClaimANewLocationLostItsBaseline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropWhatGrew-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StorageTrendsHistoryStore(directory: directory)
    func observation(_ scope: String, _ date: Date) -> StorageTrendsSnapshot {
        StorageTrendsSnapshot(fingerprint: .init(scopeID: scope, rootID: scope, volumeID: "volume", access: "complete", rules: "one", exclusions: "none", classification: "one"), scopeLabel: scope, observedAt: date, groups: [.init(id: "root", label: "Files", logicalBytes: 1)])
    }
    let old = Date(timeIntervalSince1970: 1000)
    _ = try await store.record(observation("A", old), now: old, expectedEpoch: try await store.recordingEpoch())
    let now = old.addingTimeInterval(91 * 86400)
    let result = try await store.record(observation("B", now), now: now, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .firstBaseline)
    #expect(result.from == nil)
    #expect(result.current?.scopeLabel == "B")
}
