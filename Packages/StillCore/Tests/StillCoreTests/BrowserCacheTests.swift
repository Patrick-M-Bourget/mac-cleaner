import Foundation
import Testing
import StillCore

/// A temp home folder; tests never read or write the real home or a real browser profile.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillBrowsers-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

/// Everything a Chrome profile keeps besides its caches, from Codex's protected-data list.
private let chromeProfileData = ["Cookies", "Network/Cookies", "History", "Login Data", "Web Data", "Preferences", "Bookmarks",
                                 "Sessions/Session_1", "Local Storage/leveldb/000003.log", "IndexedDB/https_example.com_0.indexeddb.leveldb/LOG",
                                 "Service Worker/CacheStorage/abc/index", "Service Worker/Database/LOG", "GPUCache/data_0"]

/// A Chrome layout as Chromium documents it on macOS: profile data under Application Support,
/// each profile's caches under the matching folder in ~/Library/Caches.
private func makeChrome(_ home: URL, profiles: [String: Int]) throws {
    try write(home, "Library/Application Support/Google/Chrome/Local State")
    for (profile, bytes) in profiles {
        for item in chromeProfileData { try write(home, "Library/Application Support/Google/Chrome/\(profile)/\(item)") }
        try write(home, "Library/Caches/Google/Chrome/\(profile)/Cache/Cache_Data/index", bytes: bytes)
        try write(home, "Library/Caches/Google/Chrome/\(profile)/Code Cache/js/index", bytes: bytes)
    }
}

@Test func chromeOffersOnlyEachProfilesCacheFolders() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeChrome(home, profiles: ["Default": 4_096, "Profile 1": 8_192])
    let found = Catalog(rules: BuiltInCatalog.rules).discover(home: home)
    let caches = home.appendingPathComponent("Library/Caches/Google/Chrome").path
    #expect(Set(found.map(\.url.path)) == [caches + "/Default/Cache", caches + "/Default/Code Cache",
                                           caches + "/Profile 1/Cache", caches + "/Profile 1/Code Cache"])
    #expect(found.allSatisfy { $0.ruleID == "chrome-cache" && $0.action == .delete && $0.isDirectory })
    #expect(Dictionary(found.map { ($0.url.path, $0.profile) }, uniquingKeysWith: { a, _ in a })[caches + "/Profile 1/Cache"] == "Profile 1")
    #expect(found.filter { $0.profile == "Default" }.map(\.logicalBytes) == [4_096, 4_096])
}

private struct Running: RunningAppChecking {
    let names: Set<String>
    func isRunning(_ owner: RuleOwner) -> Bool? { names.contains(owner.name) }
}

@Test func protectedProfileDataIsNeverACandidate() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeChrome(home, profiles: ["Default": 100])
    // A cache path that leads into profile data instead: a symlinked profile, and a profile kept in the cache root.
    let caches = home.appendingPathComponent("Library/Caches/Google/Chrome")
    try FileManager.default.createSymbolicLink(at: caches.appendingPathComponent("Linked"),
                                               withDestinationURL: home.appendingPathComponent("Library/Application Support/Google/Chrome/Default"))
    try FileManager.default.createDirectory(at: caches.appendingPathComponent("Moved"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: caches.appendingPathComponent("Moved/Cache"),
                                               withDestinationURL: home.appendingPathComponent("Library/Application Support/Google/Chrome/Default"))
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    let found = catalog.discover(home: home)
    #expect(Set(found.map(\.profile)) == ["Default"])
    let data = home.appendingPathComponent("Library/Application Support").path
    #expect(!found.contains { $0.url.path.hasPrefix(data) })
    for item in chromeProfileData { #expect(!found.contains { $0.url.path.contains("/" + item.split(separator: "/")[0]) }) }

    // If profile data turns up inside a cache folder after the scan, the folder is refused just before acting.
    let check = CandidateCheck(catalog: catalog, running: Running(names: []))
    let cache = try #require(found.first { $0.url.lastPathComponent == "Cache" })
    #expect(check.check(cache) == nil)
    try write(home, "Library/Caches/Google/Chrome/Default/Cache/Cookies")
    #expect(check.check(cache) == .protected("Cookies"))
}

@Test func aRunningBrowsersCachesAreRefusedWithAReason() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeChrome(home, profiles: ["Default": 100])
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    let cache = try #require(catalog.discover(home: home).first)
    let refusal = CandidateCheck(catalog: catalog, running: Running(names: ["Google Chrome"])).check(cache)
    #expect(refusal == .ownerRunning("Google Chrome"))
    #expect(refusal?.reason == "Google Chrome is running. Quit it, then scan again.")
    // Still never quits the browser; the user closes it and scans again.
    #expect(CandidateCheck(catalog: catalog, running: Running(names: [])).check(cache) == nil)
}

@Test func chromeIsRecognizedByItsAppAndHelperProcesses() throws {
    let owner = try #require(BuiltInCatalog.rules.first { $0.id == "chrome-cache" }?.owner)
    #expect(owner.bundleIDs == ["com.google.Chrome"])
    #expect(owner.matches(["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]))
    #expect(owner.matches(["/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", "--type=renderer"]))
    #expect(!owner.matches(["/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"]))
}
