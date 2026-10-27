import Foundation
import Testing
@testable import CacheDropCore

// #173: leftovers of apps that are no longer installed. Every test uses a temp home; installed apps, receipts and running
// processes come from fixtures, so tests never ask Launch Services, Spotlight or pkgutil about this Mac.

private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRemovedApps-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

/// Installed apps as Launch Services and Spotlight would report them, other volumes included; nil reads as unknown.
private struct Apps: AppPresence {
    var installed: [InstalledApp]? = []
    /// Bundle IDs only Launch Services knows (an app Spotlight doesn't index).
    var registered: Set<String> = []
    func installedApps() -> [InstalledApp]? { installed }
    func isRegistered(bundleID: String) -> Bool { registered.contains(bundleID) }
}
private struct Receipts: InstallerReceiptReading {
    var all: [InstallerReceipt] = []
    func receipts() -> [InstallerReceipt] { all }
}
private let editor = InstalledApp(name: "Editor", bundleID: "com.here.editor", path: "/Applications/Editor.app")

private func scan(_ home: URL, apps: Apps = Apps(), receipts: Receipts = Receipts(), exclusions: ExclusionPolicy = ExclusionPolicy()) -> [Candidate] {
    RemovedAppLeftovers.scan(home: home, apps: apps, receipts: receipts, exclusions: exclusions)
}
private func names(_ found: [Candidate]) -> Set<String> { Set(found.map(\.url.lastPathComponent)) }

@Test func itemsNamedByARemovedAppsBundleIDAreItsConfirmedLeftovers() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Preferences/com.gone.synth.plist")
    try write(home, "Library/Caches/com.gone.synth/Cache.db", bytes: 2_000)
    try write(home, "Library/Saved Application State/com.gone.synth.savedState/data.data")
    try write(home, "Library/Containers/com.gone.synth/Data/x")
    try write(home, "Library/HTTPStorages/com.gone.synth.binarycookies")

    let found = scan(home)

    #expect(names(found) == ["com.gone.synth.plist", "com.gone.synth", "com.gone.synth.savedState", "com.gone.synth.binarycookies"])
    #expect(found.count == 5)
    #expect(found.allSatisfy { $0.ruleID == RemovedAppLeftovers.ruleID && $0.action == .trash })
    #expect(found.allSatisfy { $0.leftover?.evidence == .bundleID && $0.leftover?.bundleID == "com.gone.synth" })
    #expect(Set(found.compactMap(\.appName)) == ["Synth"], "Grouped per app")
    #expect(found.first { $0.url.lastPathComponent == "com.gone.synth" && $0.isDirectory }?.estimatedBytes ?? 0 >= 2_000)
}

@Test func anAppFoundAnywhereIsNotRemovedSoItsItemsAreNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Preferences/com.here.editor.plist")
    try write(home, "Library/Caches/com.elsewhere.player/x")
    try write(home, "Library/Caches/com.known.tool/x")
    let onOtherVolume = InstalledApp(name: "Player", bundleID: "com.Elsewhere.Player", path: "/Volumes/External/Applications/Player.app")
    // Spotlight lists Editor and Player (on another volume, with other capitalisation); only Launch Services knows the tool.
    let apps = Apps(installed: [editor, onOtherVolume], registered: ["com.known.tool"])

    #expect(scan(home, apps: apps).isEmpty)
}

@Test func whenInstalledAppsCantBeListedNothingIsOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Preferences/com.gone.synth.plist")

    #expect(scan(home, apps: Apps(installed: nil)).isEmpty)
}

@Test func anItemOfAMakerWithAnInstalledAppIsNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // A helper, extension or agent of Editor's maker may belong to Editor, which is installed.
    try write(home, "Library/Preferences/com.here.editor.helper.plist")
    try write(home, "Library/Group Containers/ABCDE12345.com.here.shared/x")
    try write(home, "Library/Preferences/com.gone.synth.plist")

    #expect(names(scan(home, apps: Apps(installed: [editor]))) == ["com.gone.synth.plist"])
}

@Test func applesOwnLicenseAndExcludedItemsAreNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // None of these apps is installed, yet none of their items is offered.
    for relative in ["Library/Preferences/com.apple.gone.plist", "Library/Group Containers/group.com.apple.notes/x",
                     "Library/Caches/com.patrickbourget.CacheDrop/x", "Library/Preferences/com.patrickbourget.Still.plist",
                     "Library/Preferences/com.paceap.eden.iLokLicenseManager.plist", "Library/Application Support/com.paceap.pace/x",
                     "Library/Preferences/com.steinberg.eLicenser.plist", "Library/Caches/com.gone.licensemanager/x",
                     "Library/Caches/com.gone.excluded/x"] {
        try write(home, relative)
    }
    let excluded = try ExclusionRule.capture(home.appendingPathComponent("Library/Caches/com.gone.excluded"))

    #expect(scan(home, exclusions: ExclusionPolicy(rules: [excluded])).isEmpty)
}

@Test func aLaunchAgentWhoseProgramIsStillThereIsNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let program = home.appendingPathComponent("Tools/updater")
    try write(home, "Tools/updater")
    let agents = home.appendingPathComponent("Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    for (label, path) in [("com.gone.keeper", program.path), ("com.gone.stale", home.appendingPathComponent("Tools/missing").path)] {
        let plist: [String: Any] = ["Label": label, "ProgramArguments": [path, "--run"]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agents.appendingPathComponent(label + ".plist"))
    }

    #expect(names(scan(home)) == ["com.gone.stale.plist"])
}

@Test func whatAReceiptOfARemovedAppListsIsItsConfirmedLeftovers() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Application Support/FooData/presets.db")
    try write(home, "Library/Application Support/BarData/x")
    try write(home, "Library/Application Support/MovedData/x")
    let support = home.appendingPathComponent("Library/Application Support").path
    // Bar.app is still where its receipt put it; Moved.app was moved, and Spotlight finds it elsewhere.
    try write(home, "Applications/Bar.app/Contents/Info.plist")
    let receipts = Receipts(all: [
        InstallerReceipt(id: "com.foocorp.foo.pkg", apps: [home.path + "/Applications/Foo.app"], paths: [support + "/FooData/presets.db"]),
        InstallerReceipt(id: "com.barcorp.bar.pkg", apps: [home.path + "/Applications/Bar.app"], paths: [support + "/BarData"]),
        InstallerReceipt(id: "com.movedcorp.moved.pkg", apps: [home.path + "/Applications/Moved.app"], paths: [support + "/MovedData"]),
    ])
    let moved = InstalledApp(name: "Moved", bundleID: "com.movedcorp.moved", path: "/Volumes/Other/Moved.app")

    let found = scan(home, apps: Apps(installed: [moved]), receipts: receipts)

    #expect(names(found) == ["FooData"])
    #expect(found.first?.ruleID == RemovedAppLeftovers.ruleID)
    #expect(found.first?.leftover?.evidence == .receipt("com.foocorp.foo.pkg"))
    #expect(found.first?.appName == "Foo")
}

@Test func aNameOnlyMatchIsPossiblyRelatedWithItsReasonAndNeverTickedWithItsGroup() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Preferences/com.gone.synth.plist")
    // Its saved window state shows com.gone.synth was an app's (#251).
    try write(home, "Library/Saved Application State/com.gone.synth.savedState/data.data")
    try write(home, "Library/Application Support/Gone/x")
    try write(home, "Library/Logs/Synth/x")
    // Named like Editor's maker or Editor itself, which is installed; or like no removed app at all.
    try write(home, "Library/Application Support/Here/x")
    try write(home, "Library/Caches/Editor/x")
    try write(home, "Library/Application Support/Unrelated/x")

    let found = scan(home, apps: Apps(installed: [editor]))
    let possible = found.filter { $0.ruleID == RemovedAppLeftovers.possiblyRelatedRuleID }

    #expect(names(possible) == ["Gone", "Synth"])
    #expect(names(found) == ["com.gone.synth.plist", "com.gone.synth.savedState", "Gone", "Synth"])
    #expect(possible.allSatisfy { $0.appName == "Synth" && $0.leftover?.reason?.contains("com.gone.synth") == true })
    #expect(RemovedAppLeftovers.rules.first { $0.id == RemovedAppLeftovers.possiblyRelatedRuleID }?.selectedOneByOne == true)
    #expect(RemovedAppLeftovers.rules.first { $0.id == RemovedAppLeftovers.ruleID }?.selectedOneByOne == false)
}

/// Running apps by bundle ID; a process counts for an owner whose bundle ID prefixes match it.
private struct Running: RunningAppChecking {
    var bundleIDs: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? {
        bundleIDs.contains { id in owner.bundleIDs.contains(id) || owner.bundleIDPrefixes.contains { id.lowercased().hasPrefix($0) } }
    }
}
private func check(_ home: URL, running: Running = Running(), apps: Apps = Apps()) -> CandidateCheck {
    CandidateCheck(catalog: Catalog(rules: fixtureRules), running: running, inUse: FixtureNothingInUse(), home: home, apps: apps)
}

@Test func aRunningProcessOfTheMakerBlocksTheWholeGroup() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Containers/com.gone.synth/Data/x")
    try write(home, "Library/Application Support/Gone/x")
    let found = scan(home)
    #expect(found.count == 2)

    // Another app of the same maker is running, though Synth itself is gone.
    let blocked = check(home, running: Running(bundleIDs: ["com.gone.Updater"]))
    #expect(found.map(blocked.check) == [.ownerRunning("Gone"), .ownerRunning("Gone")])
    #expect(found.allSatisfy { Catalog(rules: fixtureRules).owner(for: $0)?.name == "Gone" })
    #expect(found.map(check(home, running: Running(bundleIDs: ["com.other.app"])).check) == [nil, nil])
}

@Test func anAppInstalledAgainSinceTheScanKeepsItsLeftovers() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Preferences/com.gone.synth.plist")
    let found = try #require(scan(home).first)
    let synth = InstalledApp(name: "Synth", bundleID: "com.gone.synth", path: "/Volumes/Backup/Synth.app")

    #expect(check(home, apps: Apps(installed: [synth])).check(found) == .appInstalled("Synth"))
    #expect(check(home, apps: Apps(registered: ["com.gone.synth"])).check(found) == .appInstalled("Synth"))
    #expect(check(home, apps: Apps(installed: nil)).check(found) == .appInstalled("Synth"), "Unknown presence keeps it")
}

@Test func aLicenseOrAppleItemIsRefusedEvenIfItReachesTheCheck() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Application Support/PACE Anti-Piracy/x")
    try write(home, "Library/Preferences/com.apple.gone.plist")
    let catalog = Catalog(rules: fixtureRules), rule = try #require(catalog.rule(RemovedAppLeftovers.ruleID))
    let forged = try ["Library/Application Support/PACE Anti-Piracy", "Library/Preferences/com.apple.gone.plist"].map { relative -> Candidate in
        let url = home.appendingPathComponent(relative)
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        var item = catalog.candidate(rule, url, info, logical: 100, allocated: nil, complete: true, lastUsed: nil)
        item.leftover = LeftoverTie(app: "Gone", bundleID: "com.gone.app", vendor: "com.gone", evidence: .bundleID)
        return try #require(item.found(under: home) as Candidate?)
    }

    #expect(forged.map(check(home).check).allSatisfy { if case .protected = $0 { true } else { false } })
}

private struct FixtureHomeTrash: TrashMoving {
    let home: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        let destination = home.appendingPathComponent(".Trash/" + url.lastPathComponent)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

@Test func leftoversGoToTrashAndPutBackRestoresThem() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Caches/com.gone.synth/Cache.db", bytes: 2_000)
    let found = scan(home)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let executor = CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: FixtureHomeTrash(home: home))

    let result = await executor.execute(CatalogApproval(candidates: found, previewOnly: false))
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded && record.trashURL != nil)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.gone.synth").path))

    #expect(TrashPutBack(journal: journal).putBack(record) == .restored(record.originalURL))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.gone.synth/Cache.db").path))
}

@Test func aLeftoverAnotherRuleOffersHoldsOrSitsInsideIsLeftToThatRule() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Caches/com.gone.synth/org.sparkle-project.Sparkle/update.zip")
    try write(home, "Library/Logs/com.gone.synth/main.log")
    try write(home, "Library/Preferences/com.gone.synth.plist")
    let offered = Catalog(rules: fixtureRules).discover(fixture: home)
    #expect(!offered.isEmpty)

    #expect(names(RemovedAppLeftovers.notOffered(by: offered, scan(home))) == ["com.gone.synth.plist"])
}
