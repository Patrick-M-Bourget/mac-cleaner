import Foundation
import Testing
@testable import StillCore

/// A temp home folder; tests never read or write the real home, its caches or its apps' data.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillAppData-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

/// Installed apps as LaunchServices would report them; the real Mac's apps are never consulted.
private struct Apps: AppLookup {
    var installed: [InstalledApp] = []
    func app(bundleID: String) -> InstalledApp? { installed.first { $0.bundleID == bundleID } }
    func app(updaterCacheDirName name: String) -> InstalledApp? { nil }
}

/// Which apps and processes are "running" in a test.
private struct Running: RunningAppChecking {
    var bundleIDs: Set<String> = []
    /// Command lines of other running processes.
    var processes: [[String]] = []
    func isRunning(_ owner: RuleOwner) -> Bool? { !bundleIDs.isDisjoint(with: owner.bundleIDs) || processes.contains(where: owner.matches) }
}

private func found(_ catalog: Catalog, _ home: URL, access: FullDiskAccessStatus = .granted) -> [String: String] {
    let prefix = home.path + "/"
    return Dictionary(catalog.discovery(fixture: home, access: access).candidates.map { (String($0.url.path.dropFirst(prefix.count)), $0.ruleID) },
                      uniquingKeysWith: { a, _ in a })
}

// MARK: VS Code

@Test func vsCodeOffersOnlyItsCacheFoldersNeverSettingsOrExtensions() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let code = "Library/Application Support/Code/"
    let caches = ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache"]
    for folder in caches { try write(home, code + folder + "/data", bytes: 2_048) }
    for kept in ["User/settings.json", "User/globalStorage/state.vscdb", "extensions/ms-python/package.json", "Backups/1/file",
                 "logs/main.log", "storage.json"] {
        try write(home, code + kept)
    }
    let catalog = Catalog(rules: fixtureRules)
    #expect(found(catalog, home) == Dictionary(uniqueKeysWithValues: caches.map { (code + $0, "vscode-cache") }))
    let rule = try #require(catalog.rule("vscode-cache"))
    #expect(rule.category == .developer && rule.action == .delete && rule.regen == .cache)
}

@Test func vsCodesCachesAreRefusedWhileVSCodeRuns() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Application Support/Code/CachedExtensionVSIXs/ms-python.vsix")
    let catalog = Catalog(rules: fixtureRules)
    let cache = try #require(catalog.discover(fixture: home).first)
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.microsoft.VSCode"])).check(cache) == .ownerRunning("Visual Studio Code"))
    // Its helpers, and the `code` command, which runs the app's own executable.
    for process in [["/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"],
                    ["/Applications/Visual Studio Code.app/Contents/MacOS/Code", "--wait"]] {
        #expect(CandidateCheck(catalog: catalog, running: Running(processes: [process])).check(cache) == .ownerRunning("Visual Studio Code"))
    }
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(cache) == nil)
}

@Test func vsCodiumKeepsItsOwnCachesUnderItsOwnOwner() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Application Support/VSCodium/CachedData/abc/data")
    try write(home, "Library/Application Support/VSCodium/User/settings.json")
    let catalog = Catalog(rules: fixtureRules)
    #expect(found(catalog, home) == ["Library/Application Support/VSCodium/CachedData": "vscodium-cache"])
    let cache = try #require(catalog.discover(fixture: home).first)
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.vscodium"])).check(cache) == .ownerRunning("VSCodium"))
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.microsoft.VSCode"])).check(cache) == nil)
}

// MARK: JetBrains

@Test func onlyOlderVersionsOfAJetBrainsIDEAreOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let jetbrains = "Library/Caches/JetBrains/"
    for folder in ["IntelliJIdea2023.3", "IntelliJIdea2024.2", "IntelliJIdea2024.10", "PyCharm2024.1", "PyCharmCE2023.1", "PyCharmCE2023.2",
                   "SomeNewIDE2023.1", "SomeNewIDE2024.1", "consentOptions"] {
        try write(home, jetbrains + folder + "/caches/content.dat", bytes: 1_024)
    }
    let catalog = Catalog(rules: fixtureRules)
    // The newest version of each product is the one in use; a product Still doesn't know has no owner to check.
    #expect(found(catalog, home) == [jetbrains + "IntelliJIdea2023.3": "jetbrains-caches", jetbrains + "IntelliJIdea2024.2": "jetbrains-caches",
                                     jetbrains + "PyCharmCE2023.1": "jetbrains-caches"])
    let rule = try #require(catalog.rule("jetbrains-caches"))
    #expect(rule.category == .developer && rule.action == .delete)
    let names = Set(catalog.discover(fixture: home).compactMap(\.appName))
    #expect(names == ["IntelliJ IDEA", "PyCharm"])
}

@Test func anOldJetBrainsCacheIsRefusedWhileThatIDERuns() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for folder in ["IntelliJIdea2023.3", "IntelliJIdea2024.2"] { try write(home, "Library/Caches/JetBrains/\(folder)/caches/content.dat") }
    let catalog = Catalog(rules: fixtureRules)
    let old = try #require(catalog.discover(fixture: home).first)
    #expect(old.url.lastPathComponent == "IntelliJIdea2023.3")
    // Any version of the IDE, from any install (Toolbox or /Applications).
    let idea = ["/Users/me/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea"]
    #expect(CandidateCheck(catalog: catalog, running: Running(processes: [idea])).check(old) == .ownerRunning("IntelliJ IDEA"))
    #expect(CandidateCheck(catalog: catalog, running: Running(processes: [["/Applications/PyCharm.app/Contents/MacOS/pycharm"]])).check(old) == nil)
    // The newer version's folder is gone since the scan: this one may be in use again.
    try FileManager.default.removeItem(at: home.appendingPathComponent("Library/Caches/JetBrains/IntelliJIdea2024.2"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(old) != nil)
}
