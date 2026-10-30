import Foundation
import Testing
@testable import CacheDropCore

/// An Application Support folder in a temp directory; nothing touches the real one.
private func applicationSupport() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("StillMigration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ relative: String, in root: URL) throws {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func read(_ relative: String, in root: URL) -> String? {
    (try? Data(contentsOf: root.appendingPathComponent(relative))).flatMap { String(data: $0, encoding: .utf8) }
}

/// Preferences held in memory, so tests never write to the user's defaults.
private final class Preferences: MigrationPreferences, @unchecked Sendable {
    var values: [String: Any]
    init(_ values: [String: Any] = [:]) { self.values = values }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// Fails every copy, as a full disk or an unreadable file would.
private final class FailingCopies: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

private let legacyState = ["Growth/history.json": "growth", "Scopes/scopes.json": "bookmarks", "Exclusions/exclusions.json": "excluded"]

private func legacyFixture(_ support: URL) throws {
    for (relative, text) in legacyState { try write(text, "Still/" + relative, in: support) }
}

@Test func stillsStateAndPreferencesAreCopiedWhenCacheDropHasNone() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences,
                                         legacyPreferences: { ["Still.showsMenuBarItem": false, "StillDryRun": true] }, running: StillRunning(answer: false))
    #expect(migration.run() == .copied)
    for (relative, text) in legacyState {
        #expect(read("CacheDrop/" + relative, in: support) == text)
        #expect(read("Still/" + relative, in: support) == text) // copied, never moved
    }
    // Carried over under CacheDrop's own key names (#150).
    #expect(preferences.object(forKey: "CacheDrop.showsMenuBarItem") as? Bool == false)
    #expect(preferences.object(forKey: "CacheDropDryRun") as? Bool == true)
    #expect(preferences.object(forKey: "Still.showsMenuBarItem") == nil)
    #expect(preferences.object(forKey: "StillDryRun") == nil)
}

@Test func cacheDropsOwnStateAndPreferencesAreNeverOverwritten() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    try write("cachedrop journal", "CacheDrop/cleanup.sqlite", in: support)
    let preferences = Preferences(["CacheDropDryRun": false])
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] }, running: StillRunning(answer: false))
    #expect(migration.run() == .cacheDropHasState)
    #expect(read("CacheDrop/cleanup.sqlite", in: support) == "cachedrop journal")
    #expect(read("CacheDrop/Scopes/scopes.json", in: support) == nil)
    #expect(preferences.object(forKey: "CacheDropDryRun") as? Bool == false)
}

@Test func aFailedCopyLeavesStillsDataAndCacheDropEmptyAndIsTriedAgain() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    let failing = LegacyStillMigration(applicationSupport: support, fileManager: FailingCopies(), preferences: preferences,
                                       legacyPreferences: { ["StillDryRun": true] }, running: StillRunning(answer: false))
    #expect(failing.run() == .failed)
    for (relative, text) in legacyState { #expect(read("Still/" + relative, in: support) == text) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: support.path) == ["Still"]) // no CacheDrop, no staging copy
    #expect(preferences.values.isEmpty) // nothing copied, nothing recorded
    let retry = LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] }, running: StillRunning(answer: false))
    #expect(retry.run() == .copied)
}

@Test func theMigrationRunsOnce() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] }, running: StillRunning(answer: false))
    #expect(migration.run() == .copied)
    // CacheDrop's state is then forgotten (Reset) and Still's changes: nothing is copied again.
    try FileManager.default.removeItem(at: support.appendingPathComponent("CacheDrop"))
    preferences.set(nil, forKey: "CacheDropDryRun")
    #expect(migration.run() == .alreadyDone)
    #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("CacheDrop").path))
    #expect(preferences.object(forKey: "CacheDropDryRun") == nil)
}

@Test func nothingIsCopiedWhenStillLeftNothing() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    let preferences = Preferences()
    #expect(LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { nil }, running: StillRunning(answer: false)).run() == .nothingToCopy)
    #expect(try FileManager.default.contentsOfDirectory(atPath: support.path).isEmpty)
    #expect(preferences.object(forKey: LegacyStillMigration.completedKey) as? Bool == true)
}

@Test func stillsLoginLaunchIsNotCarriedOver() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    let preferences = Preferences()
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences,
                                         legacyPreferences: { ["Still.startAtLogin": true, "Still.showsMenuBarItem": false] }, running: StillRunning(answer: false))
    #expect(migration.run() == .copied)
    #expect(preferences.object(forKey: "Still.startAtLogin") == nil)
    #expect(preferences.object(forKey: "CacheDrop.startAtLogin") == nil)
    #expect(preferences.object(forKey: "CacheDrop.showsMenuBarItem") as? Bool == false)
}

/// Whether Still's app is running, as the test says.
private struct StillRunning: RunningAppChecking {
    let answer: Bool?
    func isRunning(_ owner: RuleOwner) -> Bool? { owner.bundleIDs == [LegacyStillMigration.legacyDomain] ? answer : false }
}

@Test func theMigrationWaitsWhileStillIsRunningAndRetriesOnTheNextLaunch() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    func migration(_ answer: Bool?) -> LegacyStillMigration {
        LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] }, running: StillRunning(answer: answer))
    }
    // Running, or unknown: Still could be writing its journal, so nothing is copied or recorded.
    for answer in [true, nil] as [Bool?] {
        #expect(migration(answer).run() == .stillRunning)
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.path) == ["Still"])
        #expect(preferences.values.isEmpty)
    }
    #expect(migration(false).run() == .copied)
    #expect(read("CacheDrop/Scopes/scopes.json", in: support) == "bookmarks")
}

@Test func theCopiedJournalHoldsEveryRecordIncludingThoseStillInItsWriteAheadLog() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    let home = support.appendingPathComponent("home").resolvingSymlinksInPath()
    for name in ["a.dmg", "b.pkg", "c.dmg"] { try write("x", "Downloads/" + name, in: home) }
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home)
    #expect(candidates.count == 3)
    let legacy = support.appendingPathComponent("Still")
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let journal = try SQLiteCleanupJournal(url: legacy.appendingPathComponent("cleanup.sqlite"))
    let batch = UUID()
    #expect(try journal.claim(batchID: batch, records: candidates.map { CleanupRecord(batchID: batch, approvedAt: Date(), candidate: $0, dryRun: false) }))
    // Still's connection stays open, so its records are still in the write-ahead log, not the main file.
    let wal = try FileManager.default.attributesOfItem(atPath: legacy.appendingPathComponent("cleanup.sqlite-wal").path)[.size] as? Int
    #expect((wal ?? 0) > 0)
    let migration = LegacyStillMigration(applicationSupport: support, preferences: Preferences(), legacyPreferences: { nil }, running: StillRunning(answer: false))
    #expect(withExtendedLifetime(journal) { migration.run() } == .copied)
    let copy = try SQLiteCleanupJournal(url: support.appendingPathComponent("CacheDrop/cleanup.sqlite"), readOnly: true)
    #expect(try copy.records().count == 3)
    #expect(try journal.records().count == 3) // Still's journal is untouched.
}
