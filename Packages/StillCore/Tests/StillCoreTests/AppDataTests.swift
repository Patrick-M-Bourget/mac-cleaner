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
    var jetBrains: [JetBrainsInstall] = []
    func app(bundleID: String) -> InstalledApp? { installed.first { $0.bundleID == bundleID } }
    func app(updaterCacheDirName name: String) -> InstalledApp? { nil }
    func jetBrainsIDEs() -> [JetBrainsInstall] { jetBrains }
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

@Test func theCacheOfAnInstalledJetBrainsVersionIsNeverOfferedEvenWithANewerFolder() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let jetbrains = "Library/Caches/JetBrains/"
    // 2025.1 is left over from an EAP; the installed IDE is 2024.2.
    for folder in ["IntelliJIdea2023.3", "IntelliJIdea2024.2", "IntelliJIdea2025.1"] { try write(home, jetbrains + folder + "/caches/content.dat") }
    let catalog = Catalog(rules: BuiltInCatalog.rules(apps: Apps(jetBrains: [JetBrainsInstall(product: "IntelliJIdea", version: [2024, 2])])))
    #expect(found(catalog, home) == [jetbrains + "IntelliJIdea2023.3": "jetbrains-caches"])
}

@Test func aJetBrainsIDEWhoseInstalledVersionIsUnknownOffersNothing() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let jetbrains = "Library/Caches/JetBrains/"
    for folder in ["PyCharm2023.1", "PyCharm2024.1", "GoLand2023.1", "GoLand2024.1"] { try write(home, jetbrains + folder + "/caches/content.dat") }
    let catalog = Catalog(rules: BuiltInCatalog.rules(apps: Apps(jetBrains: [JetBrainsInstall(product: "PyCharm", version: nil)])))
    #expect(found(catalog, home) == [jetbrains + "GoLand2023.1": "jetbrains-caches"])
}

@Test func anInstalledJetBrainsIDEsVersionIsReadFromItsAppBundle() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    func plist(_ values: [String: String]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0) }
    // product-info.json names the folder the IDE uses.
    try write(home, "IntelliJ IDEA.app/Contents/Info.plist")
    try Data(#"{"name": "IntelliJ IDEA", "dataDirectoryName": "IntelliJIdea2025.2"}"#.utf8)
        .write(to: home.appendingPathComponent("IntelliJ IDEA.app/Contents/Resources/product-info.json").creatingParent())
    #expect(SystemAppLookup.jetBrainsInstall(home.appendingPathComponent("IntelliJ IDEA.app")) == JetBrainsInstall(product: "IntelliJIdea", version: [2025, 2]))
    // Without it, the bundle identifier and short version.
    try plist(["CFBundleIdentifier": "com.jetbrains.pycharm-EAP", "CFBundleShortVersionString": "2025.3.1"])
        .write(to: home.appendingPathComponent("PyCharm.app/Contents/Info.plist").creatingParent())
    #expect(SystemAppLookup.jetBrainsInstall(home.appendingPathComponent("PyCharm.app")) == JetBrainsInstall(product: "PyCharm", version: [2025, 3]))
    try plist(["CFBundleIdentifier": "com.jetbrains.goland", "CFBundleShortVersionString": "unknown"])
        .write(to: home.appendingPathComponent("GoLand.app/Contents/Info.plist").creatingParent())
    #expect(SystemAppLookup.jetBrainsInstall(home.appendingPathComponent("GoLand.app")) == JetBrainsInstall(product: "GoLand", version: nil))
    try plist(["CFBundleIdentifier": "com.example.editor", "CFBundleShortVersionString": "2025.1"])
        .write(to: home.appendingPathComponent("Editor.app/Contents/Info.plist").creatingParent())
    #expect(SystemAppLookup.jetBrainsInstall(home.appendingPathComponent("Editor.app")) == nil)
}

private extension URL {
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
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

// MARK: Adobe

@Test func adobesMediaCacheIsOfferedAndTheRestOfCommonIsKept() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let common = "Library/Application Support/Adobe/Common/"
    try write(home, common + "Media Cache Files/clip.mov 48000.cfa", bytes: 8_192)
    try write(home, common + "Media Cache/Media Cache Database/db")
    for kept in ["Plug-ins/7.0/MediaCore/effect.bundle/x", "LUTs/look.cube"] { try write(home, common + kept) }
    let catalog = Catalog(rules: fixtureRules)
    #expect(found(catalog, home) == [common + "Media Cache Files": "adobe-media-cache", common + "Media Cache": "adobe-media-cache"])
    let cache = try #require(catalog.discover(fixture: home).first)
    // Every Adobe video app shares it: Premiere, After Effects, Media Encoder, Audition.
    for process in [["/Applications/Adobe Premiere Pro 2025/Adobe Premiere Pro 2025.app/Contents/MacOS/Adobe Premiere Pro 2025"],
                    ["/Applications/Adobe After Effects 2025/Adobe After Effects 2025.app/Contents/MacOS/After Effects"],
                    ["/Applications/Adobe Media Encoder 2025/Adobe Media Encoder 2025.app/Contents/MacOS/Adobe Media Encoder 2025"]] {
        #expect(CandidateCheck(catalog: catalog, running: Running(processes: [process])).check(cache) == .ownerRunning("Adobe video apps"))
    }
    #expect(CandidateCheck(catalog: catalog, running: Running(processes: [["/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app/Contents/MacOS/Adobe Photoshop 2025"]])).check(cache) == nil)
}

// MARK: Sandboxed apps

private let editor = InstalledApp(name: "Editor", bundleID: "com.example.Editor", path: "/Applications/Editor.app")

@Test func aSandboxedAppsContainerOffersOnlyItsCaches() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let container = "Library/Containers/com.example.Editor/Data/"
    try write(home, container + "Library/Caches/com.example.Editor/Cache.db", bytes: 4_096)
    for kept in ["Library/Application Support/Editor/store.sqlite", "Library/Preferences/com.example.Editor.plist", "Documents/draft.txt",
                 "Library/Containers.plist"] {
        try write(home, container + kept)
    }
    // Not installed, macOS's own, Still's own, and a group container: none is offered.
    for other in ["Library/Containers/com.example.Gone/Data/Library/Caches/x", "Library/Containers/com.apple.Notes/Data/Library/Caches/x",
                  "Library/Containers/com.patrickbourget.Still/Data/Library/Caches/x", "Library/Group Containers/group.com.example.Editor/Library/Caches/x"] {
        try write(home, other)
    }
    let installed = [editor, InstalledApp(name: "Notes", bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app"),
                     InstalledApp(name: "Still", bundleID: "com.patrickbourget.Still", path: "/Applications/Still.app")]
    let catalog = Catalog(rules: BuiltInCatalog.rules(apps: Apps(installed: installed)))
    #expect(found(catalog, home) == [container + "Library/Caches": "container-caches"])
    let cache = try #require(catalog.discover(fixture: home).first)
    #expect(cache.appName == "Editor" && cache.action == .delete)
    #expect(catalog.rule("container-caches")?.category == .system)
}

@Test func aContainersCachesAreRefusedWhileItsAppRunsOrOnceItIsUninstalled() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Containers/com.example.Editor/Data/Library/Caches/com.example.Editor/Cache.db")
    let catalog = Catalog(rules: BuiltInCatalog.rules(apps: Apps(installed: [editor])))
    let cache = try #require(catalog.discover(fixture: home).first)
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.example.Editor"])).check(cache) == .ownerRunning("Editor"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(cache) == nil)
    let uninstalled = Catalog(rules: BuiltInCatalog.rules(apps: Apps()))
    #expect(CandidateCheck(catalog: uninstalled, running: Running()).check(cache) == .ownerUnknown("Editor"))
}

@Test func containersAreNeverReadWithoutFullDiskAccess() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Containers/com.example.Editor/Data/Library/Caches/com.example.Editor/Cache.db")
    let catalog = Catalog(rules: BuiltInCatalog.rules(apps: Apps(installed: [editor])))
    // Reading other apps' containers can ask the user for access; without Full Disk Access they're not accessible, never 0.
    let discovery = catalog.discovery(fixture: home, access: .notGranted)
    #expect(discovery.candidates.isEmpty)
    #expect(discovery.notAccessible.map(\.id).contains("container-caches"))
}

// MARK: Rack Extensions

@Test func rackExtensionsAreGuidanceWithTheirSizeAndFolder() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let reason = "Library/Application Support/Propellerhead Software/"
    try write(home, reason + "RackExtensions/com.example.Synth/Synth.dylib", bytes: 8_192)
    try write(home, reason + "Optional REs/com.example.Drums/Drums.dylib", bytes: 4_096)
    let catalog = Catalog(rules: fixtureRules)
    #expect(catalog.discover(fixture: home).isEmpty)
    let finding = try #require(catalog.guidance(fixture: home).first { $0.ruleID == "rack-extensions" })
    guard case .estimate(.measured(let bytes)) = finding.size else { Issue.record("Expected a measured size, got \(finding.size)"); return }
    #expect(bytes >= 12_288)
    #expect(finding.folder?.path == home.appendingPathComponent(reason + "RackExtensions").path)
    let rule = try #require(catalog.rule("rack-extensions"))
    #expect(rule.category == .managed && rule.action == .guidance && rule.guidance?.openTitle == "Open in Finder")
}

// MARK: Audio production (#139)

@Test func abletonsDecodingCacheIsOfferedAndRefusedWhileLiveRuns() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Caches/Ableton/Cache/Decoding/loop.mp3.wav", bytes: 8_192)
    // The User Library and Packs are the user's content, never a cache.
    for kept in ["Music/Ableton/User Library/Presets/a.adv", "Music/Ableton/Factory Packs/Core Library/b.wav"] { try write(home, kept) }
    let catalog = Catalog(rules: fixtureRules)
    #expect(found(catalog, home) == ["Library/Caches/Ableton/Cache": "ableton-cache"])
    let rule = try #require(catalog.rule("ableton-cache"))
    #expect(rule.action == .delete && rule.regen == .cache)
    let cache = try #require(catalog.discover(fixture: home).first)
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.ableton.live"])).check(cache) == .ownerRunning("Ableton Live"))
    #expect(CandidateCheck(catalog: catalog, running: Running(processes: [["/Applications/Ableton Live 12 Suite.app/Contents/MacOS/Live"]])).check(cache) == .ownerRunning("Ableton Live"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(cache) == nil)
}

@Test func soundLibrariesPacksAndSamplesAreGuidanceThatOpensTheirOwnManager() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // The fixture home stands in for the system root, so `/Library/...` is read here too.
    try write(home, "Library/Application Support/Logic/Alchemy Samples/a.wav", bytes: 8_192)
    try write(home, "Library/Audio/Apple Loops/Apple/01 Hip Hop/b.caf", bytes: 4_096)
    try write(home, "Library/Audio/Apple Loops/User Loops/SingleFiles/c.aif", bytes: 2_048)
    try write(home, "Music/Ableton/Factory Packs/Core Library/d.wav", bytes: 4_096)
    try write(home, "Splice/sounds/packs/Drums/e.wav", bytes: 4_096)
    let catalog = Catalog(rules: fixtureRules)
    // Libraries and content are never offered for deletion.
    #expect(catalog.discover(fixture: home).isEmpty)
    let findings = catalog.guidance(fixture: home)
    let expected: [(id: String, bytes: Int64, folder: String, app: String, place: String)] = [
        ("logic-sound-library", 14_336, "Library/Application Support/Logic", "com.apple.logic10", "Logic Pro"),
        ("ableton-packs", 4_096, "Music/Ableton/Factory Packs", "com.ableton.live", "Ableton Live"),
        ("splice-samples", 4_096, "Splice", "com.splice.Splice", "Splice"),
    ]
    for item in expected {
        let finding = try #require(findings.first { $0.ruleID == item.id })
        guard case .estimate(.measured(let bytes)) = finding.size else { Issue.record("Expected a measured size for \(item.id), got \(finding.size)"); continue }
        #expect(bytes >= item.bytes)
        #expect(finding.folder?.path == home.appendingPathComponent(item.folder).path)
        let rule = try #require(catalog.rule(item.id))
        #expect(rule.category == .managed && rule.action == .guidance && rule.guidance?.openTitle == "Open " + item.place)
        #expect(catalog.target(for: finding) == .app(bundleID: item.app))
    }
}

/// Opens folders only, as on a Mac where the managing app isn't installed; records what it was asked to open.
private actor NoAppsInstalled: GuidanceOpening {
    private(set) var targets: [GuidanceTarget] = []
    func open(_ target: GuidanceTarget) async -> Bool {
        targets.append(target)
        if case .folder = target { return true }
        return false
    }
}

@Test func withoutItsManagingAppGuidanceRevealsTheFolderInFinder() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // GarageBand alone: Logic Pro, whose Sound Library Manager the row opens, isn't installed.
    try write(home, "Library/Audio/Apple Loops/Apple/Apple Loops for GarageBand/a.caf", bytes: 4_096)
    let catalog = Catalog(rules: fixtureRules)
    let finding = try #require(catalog.guidance(fixture: home).first { $0.ruleID == "logic-sound-library" })
    let opener = NoAppsInstalled()
    #expect(await catalog.open(finding, using: opener))
    #expect(await opener.targets == [.app(bundleID: "com.apple.logic10"), .folder(home.appendingPathComponent("Library/Audio/Apple Loops/Apple"))])
}
