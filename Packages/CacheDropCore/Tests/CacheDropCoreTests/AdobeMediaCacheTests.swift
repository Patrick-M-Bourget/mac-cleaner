import Foundation
import Testing
@testable import CacheDropCore

// #730: Adobe's media cache moved in Settings › Media Cache, its Peak Files, and Premiere Pro's own cache per version.
// Layouts as observed on Premiere Pro 26.0 (#400); every folder here is a temp fixture.

private func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropAdobe-\(name)-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}
private func write(_ base: URL, _ relative: String, bytes: Int = 100) throws {
    let file = base.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
/// Writes `com.Adobe.Common <version>.plist` as Premiere does once the cache is moved; nil paths leave the key out.
private func settings(_ home: URL, version: String = "26.0", folder: URL?, database: URL?) throws {
    var cache: [String: String] = [:]
    if let folder { cache["FolderPath"] = folder.path + "/" }
    if let database { cache["DatabasePath"] = database.path + "/" }
    let data = try PropertyListSerialization.data(fromPropertyList: ["Media Cache": cache], format: .binary, options: 0)
    try write(home, "Library/Preferences/com.Adobe.Common \(version).plist")
    try data.write(to: home.appendingPathComponent("Library/Preferences/com.Adobe.Common \(version).plist"))
}
private struct Running: RunningAppChecking {
    var processes: [[String]] = []
    func isRunning(_ owner: RuleOwner) -> Bool? { processes.contains(where: owner.matches) }
}
private let common = "Library/Application Support/Adobe/Common/"
private let premiere = ["/Applications/Adobe Premiere Pro 2026/Adobe Premiere Pro 2026.app/Contents/MacOS/Adobe Premiere Pro 2026"]

private func adobe(_ catalog: Catalog, _ home: URL) -> (candidates: [Candidate], notes: [String]) {
    let discovery = catalog.discovery(fixture: home, access: .granted)
    return (discovery.candidates.filter { $0.ruleID == AdobeMediaCache.ruleID }, discovery.notes.filter { $0.ruleID == AdobeMediaCache.ruleID }.map(\.text))
}

@Test func aMovedMediaCacheOffersOnlyAdobesFoldersInEachNamedLocation() throws {
    let home = try temporaryFolder("home"), moved = try temporaryFolder("moved"), database = try temporaryFolder("database")
    defer { for url in [home, moved, database] { try? FileManager.default.removeItem(at: url) } }
    for folder in AdobeMediaCache.cacheFolders { try write(home, common + folder + "/x", bytes: 4_096) }
    try write(home, common + "Motion Graphics Templates/Titles/t.mogrt")
    try write(moved, "Media Cache Files/clip.ims", bytes: 8_192)
    try write(moved, "Peak Files/2026-11-03/clip 48000.pek")
    // The folder the user chose holds their own files too; only Adobe's folders in it are offered.
    try write(moved, "Edit notes.txt")
    try write(moved, "Footage/clip.mov")
    try write(database, "Media Cache/db.mcdb")
    try settings(home, folder: moved, database: database)
    let found = adobe(Catalog(rules: fixtureRules), home)
    let paths = Set(found.candidates.map(\.url.path))
    #expect(paths == Set(AdobeMediaCache.cacheFolders.map { home.appendingPathComponent(common + $0).path }
                         + [moved.appendingPathComponent("Media Cache Files").path, moved.appendingPathComponent("Peak Files").path,
                            database.appendingPathComponent("Media Cache").path]))
    #expect(found.notes.isEmpty)
    for candidate in found.candidates {
        let inMoved = !candidate.url.path.hasPrefix(home.path + "/")
        #expect(candidate.folderSource == (inMoved ? "Set in Adobe settings" : "Default location"))
        // Each moved item is scoped to the folder the settings named, never wider.
        #expect(candidate.scopeRoot?.path == (inMoved ? candidate.url.deletingLastPathComponent().path : home.path))
    }
    #expect(found.candidates.first { $0.url.path.hasPrefix(moved.path) && $0.url.lastPathComponent == "Media Cache Files" }?.logicalBytes == 8_192)
}

@Test func everyVersionsSettingsAreReadAndEachFolderIsListedOnce() throws {
    let home = try temporaryFolder("home"), moved = try temporaryFolder("moved")
    defer { for url in [home, moved] { try? FileManager.default.removeItem(at: url) } }
    try write(home, common + "Media Cache Files/x")
    try write(moved, "Media Cache Files/x")
    // 25.0 and 26.0 name the same folder; 24.0 names the default folder, which is found as the default.
    try settings(home, version: "25.0", folder: moved, database: moved)
    try settings(home, version: "26.0", folder: moved, database: nil)
    try settings(home, version: "24.0", folder: home.appendingPathComponent(common), database: nil)
    #expect(AdobeMediaCache.settings(home: home) == AdobeMediaCache.Settings(folders: [moved], unreadable: false))
    let found = adobe(Catalog(rules: fixtureRules), home)
    #expect(found.candidates.map(\.url.path).sorted() == [home.appendingPathComponent(common + "Media Cache Files").path,
                                                          moved.appendingPathComponent("Media Cache Files").path].sorted())
}

@Test func settingsThatCantBeReadOfferNoMovedCacheButTheDefaultStays() throws {
    let home = try temporaryFolder("home")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, common + "Media Cache Files/x")
    try write(home, "Library/Preferences/com.Adobe.Common 26.0.plist")
    let found = adobe(Catalog(rules: fixtureRules), home)
    #expect(found.candidates.map(\.url.lastPathComponent) == ["Media Cache Files"])
    #expect(found.notes == ["CacheDrop couldn’t read Adobe’s media cache settings, so a moved media cache isn’t offered."])
    // A path that can't be followed is unreadable too, never guessed at.
    let data = try PropertyListSerialization.data(fromPropertyList: ["Media Cache": ["FolderPath": "Media/../Cache"]], format: .xml, options: 0)
    try data.write(to: home.appendingPathComponent("Library/Preferences/com.Adobe.Common 26.0.plist"))
    #expect(AdobeMediaCache.settings(home: home).unreadable)
    // Settings that never moved the cache say nothing.
    try PropertyListSerialization.data(fromPropertyList: ["Other": 1], format: .xml, options: 0)
        .write(to: home.appendingPathComponent("Library/Preferences/com.Adobe.Common 26.0.plist"))
    #expect(adobe(Catalog(rules: fixtureRules), home).notes.isEmpty)
}

@Test func aMovedCacheThatIsGoneOrOnAnUnmountedDriveIsExplained() throws {
    let home = try temporaryFolder("home")
    defer { try? FileManager.default.removeItem(at: home) }
    let gone = home.appendingPathComponent("Desktop/custom-media-cache")
    let unmounted = URL(fileURLWithPath: "/Volumes/CacheDrop-Fixture-\(UUID())/Media Cache")
    try settings(home, folder: gone, database: unmounted)
    #expect(adobe(Catalog(rules: fixtureRules), home).notes == [
        "Adobe settings name ~/Desktop/custom-media-cache as the media cache, but there’s no folder there, so it isn’t offered.",
        "Adobe settings name \(unmounted.path) as the media cache, which is on a drive that isn’t connected, so it isn’t offered.",
    ])
}

@Test func aMovedCacheOnANetworkDriveIsLeftOutAtTheScanAndTheCheck() throws {
    let home = try temporaryFolder("home"), moved = try temporaryFolder("moved")
    defer { for url in [home, moved] { try? FileManager.default.removeItem(at: url) } }
    try write(moved, "Media Cache Files/x")
    try settings(home, folder: moved, database: nil)
    let catalog = Catalog(rules: fixtureRules), rule = try #require(catalog.rule(AdobeMediaCache.ruleID))
    let remote = catalog.movedAdobeMediaCaches(rule, home: home, sizer: KnownLocationSizer(), isLocal: { _ in false })
    #expect(remote.candidates.isEmpty)
    #expect(remote.notes.map(\.text) == ["Adobe settings name \(moved.path) as the media cache, which is on a network drive, so it isn’t offered."])
    // A moved cache in iCloud Drive (a synced Desktop) is explained once and never offered.
    let synced = catalog.movedAdobeMediaCaches(rule, home: home, sizer: KnownLocationSizer(), isInICloud: { _ in true })
    #expect(synced.candidates.isEmpty)
    #expect(synced.notes.map(\.text) == ["Adobe settings name \(moved.path) as the media cache, which is in iCloud Drive, so it isn’t offered."])
    // A drive whose kind can't be read is left out the same way.
    #expect(AdobeMediaCache.place(of: moved, isLocal: { _ in nil }) == .network)
    let item = try #require(adobe(catalog, home).candidates.first)
    #expect(AdobeMediaCache.refusal(for: item, root: moved, home: home, isLocal: { _ in false }) == .notACache("It is on a network drive, so it is kept."))
}

@Test func theCheckRefusesAMovedFolderTheSettingsNoLongerNameOrWhileAnAdobeVideoAppRuns() throws {
    let home = try temporaryFolder("home"), moved = try temporaryFolder("moved"), elsewhere = try temporaryFolder("elsewhere")
    defer { for url in [home, moved, elsewhere] { try? FileManager.default.removeItem(at: url) } }
    try write(home, common + "Peak Files/x")
    try write(moved, "Media Cache Files/x")
    try settings(home, folder: moved, database: nil)
    let catalog = Catalog(rules: fixtureRules)
    let found = adobe(catalog, home).candidates
    let movedItem = try #require(found.first { $0.url.path.hasPrefix(moved.path) }), peak = try #require(found.first { $0.url.lastPathComponent == "Peak Files" })
    let check = CandidateCheck(catalog: catalog, running: Running(), home: home)
    #expect(check.check(movedItem) == nil)
    #expect(check.check(peak) == nil)
    #expect(CandidateCheck(catalog: catalog, running: Running(processes: [premiere]), home: home).check(movedItem) == .ownerRunning("Adobe video apps"))
    try settings(home, folder: elsewhere, database: nil)
    #expect(check.check(movedItem) == .notACache("Adobe settings no longer name this folder, so it is kept."))
    // The default folder doesn't depend on the settings.
    #expect(check.check(peak) == nil)
}

@Test func premiereProsCacheIsOfferedPerVersionAndItsSettingsAndProjectsNever() throws {
    let home = try temporaryFolder("home")
    defer { try? FileManager.default.removeItem(at: home) }
    for version in ["25.0", "26.0"] { try write(home, "Library/Caches/Adobe/Premiere Pro/\(version)/Typesupport/x", bytes: 2_048) }
    for kept in ["Library/Preferences/Adobe/Premiere Pro/26.0/EssentialSound/x", "Documents/Adobe/Premiere Pro/26.0/testing.prproj",
                 "Documents/Adobe/Premiere Pro/26.0/Adobe Premiere Pro Auto-Save/testing.prproj", "Library/Caches/Adobe/CCX Welcome/x"] {
        try write(home, kept)
    }
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discovery(fixture: home, access: .granted).candidates.filter { $0.url.path.contains("/Adobe/") }
    #expect(found.map(\.ruleID) == ["premiere-pro-cache", "premiere-pro-cache"])
    #expect(found.compactMap(\.itemName).sorted() == ["Premiere Pro 25.0", "Premiere Pro 26.0"])
    let item = try #require(found.first)
    #expect(CandidateCheck(catalog: catalog, running: Running(processes: [premiere]), home: home).check(item) == .ownerRunning("Adobe video apps"))
}

@Test func smartCleanTakesTheMediaCacheAndPremiereProsCache() throws {
    let home = try temporaryFolder("home"), moved = try temporaryFolder("moved")
    defer { for url in [home, moved] { try? FileManager.default.removeItem(at: url) } }
    try write(home, common + "Peak Files/x")
    try write(moved, "Media Cache/db.mcdb")
    try write(home, "Library/Caches/Adobe/Premiere Pro/26.0/Typesupport/x")
    try settings(home, folder: nil, database: moved)
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discovery(fixture: home, access: .granted).candidates.filter { $0.ruleID == AdobeMediaCache.ruleID || $0.ruleID == "premiere-pro-cache" }
    #expect(found.count == 3)
    for candidate in found { #expect(RecommendedPlan.recommends(candidate, rule: try #require(catalog.rule(candidate.ruleID)), now: Date())) }
}

@Test func cleaningAMovedCacheRemovesOnlyAdobesFolderAndKeepsTheChosenFolder() async throws {
    let home = try temporaryFolder("home"), moved = try temporaryFolder("moved")
    defer { for url in [home, moved] { try? FileManager.default.removeItem(at: url) } }
    try write(moved, "Media Cache Files/clip.ims", bytes: 4_096)
    try write(moved, "Edit notes.txt")
    try settings(home, folder: moved, database: nil)
    let catalog = Catalog(rules: fixtureRules)
    let item = try #require(adobe(catalog, home).candidates.first)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: Running(), home: home), measure: { _ in nil }, trash: TrashNeverUsed())
    #expect(try #require(await run.execute(CatalogApproval(candidates: [item], dryRun: false)).records.first).state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: moved.appendingPathComponent("Media Cache Files").path))
    #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Edit notes.txt").path))
}

// #733, Decision 164: photo and video apps' rules have their own category, listed after App caches and Audio software.
@Test func photoAndVideoFollowsAppCachesAndAudioSoftware() throws {
    var order: [CatalogCategory] = []
    for rule in fixtureRules where !order.contains(rule.category) { order.append(rule.category) }
    let system = try #require(order.firstIndex(of: .system))
    #expect(Array(order[system...].prefix(3)) == [.system, .audio, .photoVideo])
    let catalog = Catalog(rules: fixtureRules)
    for id in [AdobeMediaCache.ruleID, "premiere-pro-cache"] { #expect(catalog.rule(id)?.category == .photoVideo) }
    #expect(CatalogCategory.photoVideo.overviewTitle == "Photo and video")
    #expect(CatalogCategory(rawValue: "photo-video") == .photoVideo)
}
