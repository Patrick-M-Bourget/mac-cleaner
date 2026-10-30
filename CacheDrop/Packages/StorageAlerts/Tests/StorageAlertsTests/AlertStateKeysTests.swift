import Foundation
import Testing
import StorageAlerts

/// The alert state file, pinned before any rename (#448): the fixture was written by main's `AlertStateStore` before the pin,
/// so a renamed property that changes a stored key fails here instead of resetting alert suppression.
@Test func alertStateStillReadsWhatWasSavedBeforeThePin() throws {
    let url = try #require(Bundle.module.url(forResource: "alert-state", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try Data(contentsOf: url)
    let policy = try JSONDecoder().decode(AlertPolicy.self, from: fixture)
    #expect(policy.enabled)
    #expect(policy.thresholdBytes == 50_000_000_000)
    #expect(policy.notificationRequestIdentifiers == ["request-1"])
    #expect(policy.canRemind, "The current volume reads back")
    #expect(policy.pendingSubmission != nil, "vol-b's reservation reads back")
    #expect(policy.snoozedUntil == nil, "Only vol-a, not the current volume, is snoozed")

    // Encoding it again writes the same keys, the private episodes' included.
    let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(policy)) as? NSDictionary
    let stored = try #require(try JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    #expect(again == stored)

    // Every stored property has a key in the fixture: a new field left out of CodingKeys would never be saved.
    let mirror = Mirror(reflecting: policy)
    #expect(Set(mirror.children.compactMap(\.label)) == Set(stored.allKeys.compactMap { $0 as? String }))
    let episodes = try #require(mirror.children.first { $0.label == "episodes" }?.value as? [String: Any])
    let episodeKeys = Set(try #require(stored["episodes"] as? [String: [String: Any]]).values.flatMap(\.keys))
    #expect(Set(Mirror(reflecting: try #require(episodes["vol-a"])).children.compactMap(\.label)) == episodeKeys)

    // The store reads it too, settling the reservation it finds after a restart.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("alert-state-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try fixture.write(to: file)
    #expect(try AlertStateStore(url: file).load().pendingSubmission == nil)
}
