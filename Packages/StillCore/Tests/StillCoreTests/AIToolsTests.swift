import Foundation
import Testing
@testable import StillCore

/// A temp home folder; tests never read the real home, `~/.claude`, `~/.codex` or any agent's caches.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillAITools-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

private struct Running: RunningAppChecking {
    var bundleIDs: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { !bundleIDs.isDisjoint(with: owner.bundleIDs) }
}

private func found(_ catalog: Catalog, _ home: URL, now: Date = Date()) -> [String: String] {
    let prefix = home.path + "/"
    return Dictionary(catalog.discover(fixture: home, now: now).map { (String($0.url.path.dropFirst(prefix.count)), $0.ruleID) },
                      uniquingKeysWith: { a, _ in a })
}

// MARK: Cursor and Windsurf

@Test func cursorAndWindsurfOfferOnlyTheirCacheFoldersAndAreRefusedWhileOpen() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for (app, rule) in [("Cursor", "cursor-cache"), ("Windsurf", "windsurf-cache")] {
        let root = "Library/Application Support/\(app)/"
        for folder in ["Cache", "CachedData", "CachedExtensionVSIXs"] { try write(home, root + folder + "/data", bytes: 2_048) }
        for kept in ["User/settings.json", "User/globalStorage/state.vscdb", "extensions/x/package.json", "Backups/1/file"] { try write(home, root + kept) }
        let catalog = Catalog(rules: fixtureRules)
        #expect(found(catalog, home).filter { $0.value == rule }.keys.sorted() == ["Cache", "CachedData", "CachedExtensionVSIXs"].map { root + $0 })
    }
    let catalog = Catalog(rules: fixtureRules)
    let cursor = try #require(catalog.discover(fixture: home).first { $0.ruleID == "cursor-cache" })
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.todesktop.230313mzl4w4u92"])).check(cursor) == .ownerRunning("Cursor"))
    let windsurf = try #require(catalog.discover(fixture: home).first { $0.ruleID == "windsurf-cache" })
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.exafunction.windsurf"])).check(windsurf) == .ownerRunning("Windsurf"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(windsurf) == nil)
}
