import Foundation
import Testing
@testable import StillCore

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

private let legacyState = ["cleanup.sqlite": "journal", "Scopes/scopes.json": "bookmarks", "Exclusions/exclusions.json": "excluded"]

private func legacyFixture(_ support: URL) throws {
    for (relative, text) in legacyState { try write(text, "Still/" + relative, in: support) }
}

@Test func stillsStateAndPreferencesAreCopiedWhenCacheDropHasNone() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences,
                                         legacyPreferences: { ["Still.showsMenuBarItem": false, "StillDryRun": true] })
    #expect(migration.run() == .copied)
    for (relative, text) in legacyState {
        #expect(read("CacheDrop/" + relative, in: support) == text)
        #expect(read("Still/" + relative, in: support) == text) // copied, never moved
    }
    #expect(preferences.object(forKey: "Still.showsMenuBarItem") as? Bool == false)
    #expect(preferences.object(forKey: "StillDryRun") as? Bool == true)
}

@Test func cacheDropsOwnStateAndPreferencesAreNeverOverwritten() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    try write("cachedrop journal", "CacheDrop/cleanup.sqlite", in: support)
    let preferences = Preferences(["StillDryRun": false])
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] })
    #expect(migration.run() == .cacheDropHasState)
    #expect(read("CacheDrop/cleanup.sqlite", in: support) == "cachedrop journal")
    #expect(read("CacheDrop/Scopes/scopes.json", in: support) == nil)
    #expect(preferences.object(forKey: "StillDryRun") as? Bool == false)
}

@Test func aFailedCopyLeavesStillsDataAndCacheDropEmptyAndIsTriedAgain() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    let failing = LegacyStillMigration(applicationSupport: support, fileManager: FailingCopies(), preferences: preferences,
                                       legacyPreferences: { ["StillDryRun": true] })
    #expect(failing.run() == .failed)
    for (relative, text) in legacyState { #expect(read("Still/" + relative, in: support) == text) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: support.path) == ["Still"]) // no CacheDrop, no staging copy
    #expect(preferences.values.isEmpty) // nothing copied, nothing recorded
    let retry = LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] })
    #expect(retry.run() == .copied)
}

@Test func theMigrationRunsOnce() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    try legacyFixture(support)
    let preferences = Preferences()
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { ["StillDryRun": true] })
    #expect(migration.run() == .copied)
    // CacheDrop's state is then forgotten (Reset) and Still's changes: nothing is copied again.
    try FileManager.default.removeItem(at: support.appendingPathComponent("CacheDrop"))
    preferences.set(nil, forKey: "StillDryRun")
    #expect(migration.run() == .alreadyDone)
    #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("CacheDrop").path))
    #expect(preferences.object(forKey: "StillDryRun") == nil)
}

@Test func nothingIsCopiedWhenStillLeftNothing() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    let preferences = Preferences()
    #expect(LegacyStillMigration(applicationSupport: support, preferences: preferences, legacyPreferences: { nil }).run() == .nothingToCopy)
    #expect(try FileManager.default.contentsOfDirectory(atPath: support.path).isEmpty)
    #expect(preferences.object(forKey: LegacyStillMigration.completedKey) as? Bool == true)
}

@Test func stillsLoginLaunchIsNotCarriedOver() throws {
    let support = try applicationSupport()
    defer { try? FileManager.default.removeItem(at: support) }
    let preferences = Preferences()
    let migration = LegacyStillMigration(applicationSupport: support, preferences: preferences,
                                         legacyPreferences: { ["Still.startAtLogin": true, "Still.showsMenuBarItem": false] })
    #expect(migration.run() == .copied)
    #expect(preferences.object(forKey: "Still.startAtLogin") == nil)
    #expect(preferences.object(forKey: "Still.showsMenuBarItem") as? Bool == false)
}
