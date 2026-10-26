import Foundation
import Testing
@testable import StillCore

/// A temp home folder; tests never read or write the real home, its caches or its logs.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillAppCaches-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

@Test func logsAndCrashReportsAreTheirOwnCategories() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Logs/DiagnosticReports/Editor-2026-10-01.ips", bytes: 300)
    try write(home, "Library/Logs/Editor/main.log", bytes: 200)
    try write(home, "Library/Logs/JetBrains/idea.log")
    let found = Catalog(rules: BuiltInCatalog.rules).discover(home: home)
    let logs = home.appendingPathComponent("Library/Logs").path
    #expect(Dictionary(found.map { ($0.url.path, $0.ruleID) }, uniquingKeysWith: { a, _ in a })
            == [logs + "/DiagnosticReports": "crash-reports", logs + "/Editor": "app-logs", logs + "/JetBrains": "app-logs"])
    #expect(found.allSatisfy { $0.action == .delete })
    let categories = Set(found.compactMap { c in BuiltInCatalog.rules.first { $0.id == c.ruleID }?.category })
    #expect(categories == [.logs])
    #expect(CatalogOverview(catalog: Catalog(rules: BuiltInCatalog.rules), candidates: found).rows.map(\.category) == [.logs])
}

/// Installed apps as LaunchServices would report them; the real Mac's apps are never consulted.
private struct Apps: AppLookup {
    var installed: [InstalledApp] = []
    func app(bundleID: String) -> InstalledApp? { installed.first { $0.bundleID == bundleID } }
}
private let editor = InstalledApp(name: "Editor", bundleID: "com.example.Editor", path: "/Applications/Editor.app")

private struct Running: RunningAppChecking {
    var bundleIDs: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { !bundleIDs.isDisjoint(with: owner.bundleIDs) }
}

/// The built-in catalog with app lookups answered by the fixture.
private func catalogWith(_ apps: Apps) -> Catalog {
    let ids = Set(AppCaches.rules(apps: apps).map(\.id))
    return Catalog(rules: BuiltInCatalog.rules.filter { !ids.contains($0.id) } + AppCaches.rules(apps: apps))
}

@Test func anAppCacheIsRefusedWhileItsOwningAppRuns() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Caches/com.example.Editor/Cache.db", bytes: 4_096)
    let catalog = catalogWith(Apps(installed: [editor]))
    let found = catalog.discover(home: home)
    #expect(found.map(\.url.path) == [home.appendingPathComponent("Library/Caches/com.example.Editor").path])
    let cache = try #require(found.first)
    #expect(cache.ruleID == "app-caches" && cache.action == .delete && cache.profile == "Editor")
    #expect(catalog.owner(for: cache)?.bundleIDs == ["com.example.Editor"])

    let refusal = CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.example.Editor"])).check(cache)
    #expect(refusal == .ownerRunning("Editor"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(cache) == nil)
    // Uninstalled since the scan: the owner can no longer be determined, so the cache is refused.
    #expect(CandidateCheck(catalog: catalogWith(Apps()), running: Running()).check(cache) == .ownerUnknown("com.example.Editor"))
}

@Test func aCacheWhoseOwnerCantBeDeterminedIsNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for folder in ["SomeTool", "com.example.Uninstalled", "com.apple.Safari", "com.apple.bird", "com.patrickbourget.Still", "Codex"] {
        try write(home, "Library/Caches/\(folder)/data")
    }
    let installed = ["com.example.Uninstalled2", "com.apple.Safari", "com.apple.bird", "com.patrickbourget.Still"]
        .map { InstalledApp(name: $0, bundleID: $0, path: "/Applications/\($0).app") }
    #expect(catalogWith(Apps(installed: installed)).discover(home: home).isEmpty)
}

@Test func anAppsHelpersCountAsTheAppRunning() throws {
    let owner = RuleOwner(name: "Editor", bundleIDs: ["com.example.Editor"], paths: ["/Applications/Editor.app"])
    #expect(owner.matches(["/Applications/Editor.app/Contents/Frameworks/Editor Helper.app/Contents/MacOS/Editor Helper", "--type=gpu"]))
    #expect(owner.matches(["/Applications/Editor.app/Contents/MacOS/Editor"]))
    #expect(!owner.matches(["/Applications/Editor.app.old/Contents/MacOS/Editor"]))
    #expect(!owner.matches(["/Applications/Other.app/Contents/MacOS/Other"]))
}

@Test func aFolderAnotherRuleOwnsIsNeverOfferedAgainAsAnAppCache() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for folder in ["com.example.Tool", "com.example.Editor/Cache.noindex", "com.example.Viewer", "com.example.Packed/store"] {
        try write(home, "Library/Caches/\(folder)/data")
    }
    let apps = Apps(installed: ["com.example.Tool", "com.example.Editor", "com.example.Viewer", "com.example.Packed"]
        .map { InstalledApp(name: $0, bundleID: $0, path: "/Applications/\($0).app") })
    func rule(_ id: String, _ locations: [String], action: CleanupAction = .delete, tool: ToolCommand? = nil) -> CleanupRule {
        CleanupRule(id: id, category: .developer, title: id, detail: "", consequence: "", regen: .cache, action: action, locations: locations, owner: nil, tool: tool)
    }
    // One rule owns a whole app folder, one owns a folder inside another, and one is a tool that isn't installed.
    let catalog = Catalog(rules: [rule("whole", ["Library/Caches/com.example.Tool"]), rule("inner", ["Library/Caches/*/Cache.noindex"]),
                                  rule("tool", ["Library/Caches/com.example.Packed"], action: .tool,
                                       tool: ToolCommand(executables: ["/nonexistent/packer"], arguments: ["prune"], timeout: 1))]
                          + AppCaches.rules(apps: apps))
    let found = catalog.discover(home: home)
    let caches = home.appendingPathComponent("Library/Caches").path
    #expect(Dictionary(found.map { ($0.url.path, $0.ruleID) }, uniquingKeysWith: { a, _ in a })
            == [caches + "/com.example.Tool": "whole", caches + "/com.example.Editor/Cache.noindex": "inner", caches + "/com.example.Viewer": "app-caches"])
}

@Test func theBuiltInCatalogsOwnCacheFoldersStayWithTheirRules() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let claimed = ["Library/Caches/Yarn", "Library/Caches/pip", "Library/Caches/CocoaPods", "Library/Caches/pnpm", "Library/Caches/Homebrew",
                   "Library/Caches/Google/Chrome/Default/Cache", "Library/Caches/Firefox/Profiles/ab.default/cache2", "Library/Caches/ccache"]
    for folder in claimed { try write(home, folder + "/data") }
    // Even if each of these folder names were an installed app's, the per-app rule leaves them to their own rules.
    let names = ["Yarn", "pip", "CocoaPods", "pnpm", "Homebrew", "Google", "Firefox", "ccache"]
    let apps = Apps(installed: names.map { InstalledApp(name: $0, bundleID: $0, path: "/Applications/\($0).app") })
    #expect(!catalogWith(apps).discover(home: home, locateTool: { _ in URL(fileURLWithPath: "/bin/echo") }).contains { $0.ruleID == "app-caches" })
}
