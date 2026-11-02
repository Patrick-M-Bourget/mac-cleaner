import Foundation
import Testing
@testable import CacheDropCore

// #177: uninstalling an installed app with its files. Every test uses a temp home with a fake app in `<home>/Applications`;
// installed apps, receipts, running apps and the Trash are fixtures, so nothing on this Mac is read or changed.

private struct Apps: AppPresence {
    var installed: [InstalledApp]
    func installedApps() -> [InstalledApp]? { installed }
    func isRegistered(bundleID: String) -> Bool { installed.contains { $0.bundleID.lowercased() == bundleID.lowercased() } }
}
private struct NoReceipts: InstallerReceiptReading { func receipts() -> [InstallerReceipt] { [] } }
private struct Running: RunningAppChecking {
    var names: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { names.contains(owner.name) }
}

/// A home with Synth installed (its bundle, container, preferences and a folder only named like it) and the leftovers of an
/// app removed earlier.
private func fixture() throws -> (home: URL, synth: InstalledApp, apps: Apps) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropUninstall-\(UUID())").resolvingSymlinksInPath()
    for relative in ["Applications/Synth.app/Contents/MacOS/Synth", "Library/Containers/com.maker.synth/Data/x", "Library/Preferences/com.maker.synth.plist",
                     "Library/Application Support/Synth/presets", "Library/Containers/com.gone.old/Data/x", "Library/Preferences/com.maker.synth.license.plist"] {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: file)
    }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    let synth = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: home.appendingPathComponent("Applications/Synth.app").path)
    return (home, synth, Apps(installed: [synth]))
}
private func scan(_ home: URL, _ app: InstalledApp, _ apps: Apps, own: String? = "com.cachedrop.app", exclusions: ProtectedItemsPolicy = ProtectedItemsPolicy()) -> [Candidate] {
    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    return AppUninstall.scan(app, excluding: own, home: home, apps: apps, receipts: NoReceipts(), leftovers: leftovers, exclusions: exclusions)
}
private func check(_ home: URL, running: Running = Running(), apps: Apps? = nil) -> CandidateCheck {
    let installed = apps ?? Apps(installed: [InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: home.appendingPathComponent("Applications/Synth.app").path)])
    return CandidateCheck(catalog: Catalog(rules: AppUninstall.rules), running: running, inUse: FixtureNothingInUse(), home: home, apps: installed)
}
private func names(_ items: [Candidate], _ rule: String) -> Set<String> { Set(items.filter { $0.ruleID == rule }.map(\.url.lastPathComponent)) }

@Test func anAppIsOfferedWithTheFilesItsRemovalWouldLeaveNameOnlyMatchesAsPossiblyRelated() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let found = scan(home, synth, apps)

    #expect(names(found, AppUninstall.appRuleID) == ["Synth.app"])
    #expect(names(found, AppUninstall.filesRuleID) == ["com.maker.synth", "com.maker.synth.plist"], "Tied by bundle ID; license data never offered")
    #expect(names(found, AppUninstall.possiblyRelatedRuleID) == ["Synth"])
    // The app is installed: a possibly related item says only what ties it, not that the app is gone (#285).
    #expect(found.first { $0.ruleID == AppUninstall.possiblyRelatedRuleID }?.leftover?.reason == "Named like Synth")
    #expect(!found.contains { $0.url.lastPathComponent == "com.gone.old" }, "A removed app's leftovers stay in Leftovers")
    #expect(found.allSatisfy { $0.uninstall?.path == synth.path && $0.action == .trash })
    #expect(found.allSatisfy { check(home).check($0) == nil })
    // Ticking the app ticks the bundle and its confirmed files, never the possibly related one (Decision 49).
    let selection = CategorySelection(rules: AppUninstall.rules, candidates: found, selected: [])
    #expect(selection.toggle == .choose(Set(found.filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }.map(\.id))))
}

@Test func appleAppsCacheDropItselfAndSystemAppsAreNeverOffered() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let apple = InstalledApp(name: "Synth", bundleID: "com.apple.synth", path: synth.path)
    let system = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: "/System/Applications/Synth.app")

    #expect(scan(home, apple, Apps(installed: [apple])).isEmpty)
    #expect(scan(home, synth, apps, own: "com.maker.synth").isEmpty)
    #expect(scan(home, system, Apps(installed: [system])).isEmpty)
}

@Test func anExcludedAppIsNeverOffered() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let excluded = ProtectedItemsPolicy(rules: [try ProtectedItemsRule.capture(URL(fileURLWithPath: synth.path))])

    #expect(scan(home, synth, apps, exclusions: excluded).isEmpty, "SPEC section 2: an item inside a user exclusion is never a candidate")
}

@Test func anAppThatNeedsAPasswordIsNeverOffered() throws {
    let (home, synth, apps) = try fixture()
    let folder = home.appendingPathComponent("Applications")
    defer { chmod(folder.path, 0o755); try? FileManager.default.removeItem(at: home) }
    chmod(folder.path, 0o555)

    #expect(scan(home, synth, apps).isEmpty)
}

@Test func anItemWhosePermissionsChangeAfterTheScanIsRefusedNotMoved() async throws {
    let (home, synth, apps) = try fixture()
    let app = URL(fileURLWithPath: synth.path)
    defer { chmod(app.path, 0o755); try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)
    let bundle = try #require(found.first { $0.ruleID == AppUninstall.appRuleID })
    #expect(check(home).check(bundle) == nil)
    // After the scan, the app bundle stops being writable: macOS would now ask for a password.
    chmod(app.path, 0o555)

    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
        .execute(CatalogApproval(candidates: [bundle], dryRun: false))

    #expect(result.records.first?.state == .skipped)
    #expect(result.records.first?.message == CheckRefusal.notPermitted.reason)
    #expect(FileManager.default.fileExists(atPath: app.path))
}

@Test func aFileIsKeptWhenAnotherAppItCouldBelongToAppearsAfterTheScan() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let files = scan(home, synth, apps).filter { $0.ruleID != AppUninstall.appRuleID }
    #expect(!files.isEmpty && files.allSatisfy { check(home).check($0) == nil })
    let editor = InstalledApp(name: "Editor", bundleID: "com.maker.editor", path: "/Applications/Editor.app")
    let copy = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: "/Volumes/Studio/Applications/Synth.app")
    let namesake = InstalledApp(name: "Synth", bundleID: "com.other.synth", path: "/Applications/Other Synth.app")

    // A second copy of Synth appeared since the scan: the files may be its.
    #expect(files.allSatisfy { check(home, apps: Apps(installed: [synth, copy])).check($0) == .appInstalled("Synth") })
    // Another app of the same maker: files named for Synth's own bundle ID are still Synth's (#305).
    #expect(files.allSatisfy { check(home, apps: Apps(installed: [synth, editor])).check($0) == nil })
    // Another maker's app named Synth: the folder only named like Synth may be its.
    let folder = try #require(files.first { $0.url.lastPathComponent == "Synth" })
    #expect(check(home, apps: Apps(installed: [synth, namesake])).check(folder) == .changed)
}

private struct Processes: ProcessListing {
    let list: [RunningProcess]
    func processes() -> [RunningProcess]? { list }
}

@Test func aHelperOrLoginItemOfTheAppCountsAsTheAppRunning() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = URL(fileURLWithPath: synth.path).appendingPathComponent("Contents/Library/LoginItems/Synth Helper.app")
    try FileManager.default.createDirectory(at: helper.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.maker.synthhelper"], format: .xml, options: 0)
        .write(to: helper.appendingPathComponent("Contents/Info.plist"))
    let owner = try #require(Catalog(rules: AppUninstall.rules).owner(for: scan(home, synth, apps)[0]))
    func running(_ process: RunningProcess) -> Bool? { SystemRunningAppChecker(processes: Processes(list: [process])).isRunning(owner) }

    #expect(running(RunningProcess(path: helper.path + "/Contents/MacOS/Synth Helper")) == true, "A process inside the bundle")
    #expect(running(RunningProcess(path: "/private/var/run/agent", bundleID: "com.maker.synthhelper")) == true, "Its login item, by bundle ID")
    #expect(running(RunningProcess(path: "/Applications/Other.app/Contents/MacOS/Other", bundleID: "com.other.app")) == false)
}

@Test func aRunningAppBlocksItsUninstall() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)

    #expect(found.allSatisfy { check(home, running: Running(names: ["Synth"])).check($0) == .ownerRunning("Synth") })
    #expect(Catalog(rules: AppUninstall.rules).owner(for: found[0])?.bundleIDs == ["com.maker.synth"])
}

@Test func uninstallingMovesTheAppAndItsFilesToTrashAndPutBackRestoresThem() async throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let chosen = scan(home, synth, apps).filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))

    let result = await CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
        .execute(CatalogApproval(candidates: chosen, dryRun: false))

    #expect(result.records.count == 3 && result.records.allSatisfy { $0.state == .succeeded })
    #expect(!FileManager.default.fileExists(atPath: synth.path))
    let run = try #require(try journal.completedHistory().completedRuns.first)
    #expect(run.title == "Uninstalled Synth · 3 items")
    // #312: the result row names the app, not the rule ("App · ~/Applications").
    #expect(result.records.first { $0.ruleID == AppUninstall.appRuleID }?.uninstalledName == "Synth")
    #expect(result.records.filter { $0.ruleID == AppUninstall.filesRuleID }.allSatisfy { $0.uninstalledName == nil })
    for record in result.records { #expect(TrashPutBack(journal: journal).putBack(record) == .restored(record.originalURL)) }
    #expect(chosen.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
}

@Test func theReviewSaysWhatStaysAndGroupsFilesByPlace() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)
    let chosen = found.filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }

    // #354: what stays, why and what to do, in plain words.
    let unticked = AppUninstall.staying(chosen: chosen, offered: found)
    #expect(unticked.map(\.text) == ["Synth: 1 item you didn’t tick stays. Go back and tick it to remove it too."])
    #expect(unticked.map(\.link) == [nil], "Going back is the sheet's own Cancel")
    let two = AppUninstall.staying(chosen: chosen.filter { $0.url.pathExtension != "plist" }, offered: found).map(\.text)
    #expect(two == ["Synth: 2 items you didn’t tick stay. Go back and tick them to remove them too."])
    #expect(AppUninstall.staying(chosen: found, offered: found).isEmpty)
    #expect(AppUninstall.byPlace(chosen).map(\.place.lastPathComponent) == ["Applications", "Containers", "Preferences"])
}

@Test func theReviewCountsWhatNeedsAPasswordAndWhatThePlanAlreadyOffers() throws {
    let (home, synth, apps) = try fixture()
    let prefs = home.appendingPathComponent("Library/Preferences")
    defer { chmod(prefs.path, 0o755); try? FileManager.default.removeItem(at: home) }
    let container = home.appendingPathComponent("Library/Containers/com.maker.synth")
    // The Cleanup plan already offers the container through another rule.
    let planItem = try #require(scan(home, synth, apps).first { $0.url == container })
    chmod(prefs.path, 0o555)

    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    let found = AppUninstall.scan(synth, excluding: nil, home: home, apps: apps, receipts: NoReceipts(), leftovers: leftovers, offered: [planItem])

    #expect(!found.contains { $0.url == container || $0.url.deletingLastPathComponent() == prefs })
    let lines = AppUninstall.staying(chosen: found, offered: found)
    // #354: each says what stays, why and what to do, with a link to where it can be cleaned.
    #expect(lines.map(\.text) == ["Synth: 1 file needs your password to remove, so it stays. Remove it in Finder if you want it gone.",
                                  "1 of Synth’s files isn’t removed here; clean it in the Cleanup plan."])
    #expect(lines.map(\.link) == [.finder(paths: [prefs.appendingPathComponent("com.maker.synth.plist").path]),
                                  .cleanupPlan(ruleIDs: [planItem.ruleID])])
    #expect(lines.compactMap(\.link?.title) == ["Reveal in Finder", "Clean in the Cleanup plan"])
    #expect(Set(lines.map(\.id)).count == 2, "Each line has its own identifier")
}

@Test func anUninstalledAppsItemsAreChosenOnTheApplicationsPage() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)
    var selections = CleanupSelections()
    selections.set(found, ticked: true)

    #expect(selections.chosen(on: .applications, from: found).count == found.count)
    #expect(selections.chosen(on: .plan, from: found).isEmpty)
}

@Test func anAppsOwnUninstallerIsFoundInItsFolderOrByItsName() {
    func app(_ path: String, _ id: String = "com.x.y") -> InventoryEntry {
        InventoryEntry(id: path, name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, maker: nil, volume: nil, parts: [], bundleID: id)
    }
    let synth = app("/Applications/Maker/Synth.app"), inFolder = app("/Applications/Maker/Uninstaller.app")
    let named = app("/Applications/Uninstall Synth.app"), other = app("/Applications/Uninstall Editor.app")
    let loose = app("/Applications/Synth.app")

    #expect(ApplicationsInventory.uninstaller(for: synth, among: [synth, other, inFolder]) == inFolder)
    #expect(ApplicationsInventory.uninstaller(for: loose, among: [loose, other, named]) == named)
    #expect(ApplicationsInventory.uninstaller(for: loose, among: [loose, other]) == nil, "Another app's uninstaller in the Applications folder isn't its")
    // Only named exactly for the app: "Uninstall Synth Pro" is another app's, and so is a loose "Synth Uninstall Helper".
    let pro = app("/Applications/Uninstall Synth Pro.app"), helper = app("/Applications/Synth Uninstall Helper.app")
    #expect(ApplicationsInventory.uninstaller(for: loose, among: [loose, pro, helper]) == nil)
    #expect(ApplicationsInventory.uninstaller(for: synth, among: [synth, app("/Applications/Maker/Read Me.app")]) == nil, "Its folder's other apps aren't uninstallers")
}

@Test func anAppsOwnUninstallerIsNotListedOnItsOwnAndGoesWithTheApp() async throws {
    let (home, synth, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    // Synth in its maker's folder, with "Uninstall Synth" beside it.
    let folder = home.appendingPathComponent("Applications/Maker")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.moveItem(atPath: synth.path, toPath: folder.appendingPathComponent("Synth.app").path)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Uninstall Synth.app/Contents"), withIntermediateDirectories: true)
    let app = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: folder.appendingPathComponent("Synth.app").path)
    let tool = InstalledApp(name: "Uninstall Synth", bundleID: "com.maker.synth.uninstall", path: folder.appendingPathComponent("Uninstall Synth.app").path)
    let apps = Apps(installed: [tool, app])

    let pairs = ApplicationsInventory.withUninstallers(apps.installed, excluding: nil, home: home)
    #expect(pairs.map(\.app) == [app] && pairs.first?.uninstaller == tool, "The uninstaller is the app's, not a row of its own")
    let entries = ApplicationsInventory.apps(apps.installed, excluding: nil, home: home)
    #expect(entries.map(\.name) == ["Synth"])
    #expect(ApplicationsInventory.uninstaller(for: entries[0], among: entries)?.name == "Uninstall Synth", "Open <uninstaller> still comes first")

    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    let found = AppUninstall.scan(app, uninstaller: tool, excluding: nil, home: home, apps: apps, receipts: NoReceipts(), leftovers: leftovers)
    #expect(names(found, AppUninstall.appRuleID) == ["Synth.app", "Uninstall Synth.app"], "It goes with the app, in its App group")
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let installed = Apps(installed: [app])
    _ = await CleanupExecutor(journal: journal, check: check(home, apps: installed), measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
        .execute(CatalogApproval(candidates: found.filter { $0.ruleID == AppUninstall.appRuleID }, dryRun: false))
    #expect(try journal.completedHistory().completedRuns.first?.title == "Uninstalled Synth · 2 items")
}

/// #301: an app with no container or saved window state is uninstalled with its own preferences and caches, and its helper's:
/// the installed app being uninstalled proves its bundle IDs were an app's. Another ID still needs that evidence (#251).
@Test func anAppWithoutAContainerIsUninstalledWithItsOwnPreferencesAndCaches() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropUninstall-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = home.appendingPathComponent("Applications/Synth.app/Contents/Library/LoginItems/Synth Helper.app")
    for relative in ["Applications/Synth.app/Contents/MacOS/Synth", "Library/Preferences/com.maker.synth.plist", "Library/Caches/com.maker.synth/Cache.db",
                     "Library/Preferences/com.maker.synthhelper.plist", "Library/Preferences/com.maker.other.plist"] {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: file)
    }
    try FileManager.default.createDirectory(at: helper.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.maker.synthhelper"], format: .xml, options: 0)
        .write(to: helper.appendingPathComponent("Contents/Info.plist"))
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    let synth = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: home.appendingPathComponent("Applications/Synth.app").path)
    let found = scan(home, synth, Apps(installed: [synth]))

    #expect(names(found, AppUninstall.filesRuleID) == ["com.maker.synth.plist", "com.maker.synth", "com.maker.synthhelper.plist"], "Its files, ticked with the app")
    #expect(names(found, AppUninstall.possiblyRelatedRuleID).isEmpty, "Another ID's file is never offered with it (#305)")
    let chosen = found.filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }
    #expect(chosen.allSatisfy { check(home).check($0) == nil }, "The check before acting agrees")
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
        .execute(CatalogApproval(candidates: chosen, dryRun: false))
    #expect(result.records.count == 4 && result.records.allSatisfy { $0.state == .succeeded })
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Preferences/com.maker.synth.plist").path))
}

/// #305: two apps of one maker, each with its own preferences, container and support folder.
private func twoApps() throws -> (home: URL, synth: InstalledApp, pad: InstalledApp) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropUninstall-\(UUID())").resolvingSymlinksInPath()
    for relative in ["Applications/Synth.app/Contents/MacOS/Synth", "Applications/Pad.app/Contents/MacOS/Pad",
                     "Library/Preferences/com.maker.synth.plist", "Library/Containers/com.maker.synth/Data/x", "Library/Application Support/Synth/presets",
                     "Library/Preferences/com.maker.pad.plist", "Library/Containers/com.maker.pad/Data/x", "Library/Application Support/Pad/presets",
                     "Library/Group Containers/group.com.maker.synth/x"] {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: file)
    }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    let synth = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: home.appendingPathComponent("Applications/Synth.app").path)
    let pad = InstalledApp(name: "Pad", bundleID: "com.maker.pad", path: home.appendingPathComponent("Applications/Pad.app").path)
    return (home, synth, pad)
}

@Test func anAppOfAMakerWithAnotherAppInstalledIsUninstalledWithOnlyItsOwnFiles() throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])

    let synths = scan(home, synth, apps), pads = scan(home, pad, apps)

    #expect(names(synths, AppUninstall.filesRuleID) == ["com.maker.synth.plist", "com.maker.synth"], "Its own bundle ID's files, though Pad is installed")
    #expect(names(synths, AppUninstall.possiblyRelatedRuleID) == ["Synth"])
    #expect(names(pads, AppUninstall.filesRuleID) == ["com.maker.pad.plist", "com.maker.pad"])
    #expect(names(pads, AppUninstall.possiblyRelatedRuleID) == ["Pad"])
    #expect(!(synths + pads).contains { $0.url.lastPathComponent == "group.com.maker.synth" }, "The maker's apps may share a group container")
    #expect((synths + pads).allSatisfy { check(home, apps: apps).check($0) == nil }, "The check before acting agrees")
}

@Test func onceOneAppOfAMakerIsGoneTheOthersItemsDoNotChange() async throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let before = Set(scan(home, pad, Apps(installed: [synth, pad])).map(\.url))
    let synths = scan(home, synth, Apps(installed: [synth, pad]))
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: check(home, apps: Apps(installed: [synth, pad])), measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
        .execute(CatalogApproval(candidates: synths.filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }, dryRun: false))
    #expect(result.records.count == 3 && result.records.allSatisfy { $0.state == .succeeded })
    // Synth's support folder stays, as it wasn't ticked. Pad is installed, so its maker's files are no removed app's leftovers either.
    let apps = Apps(installed: [pad])
    #expect(RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts()).isEmpty)

    let after = scan(home, pad, apps)

    #expect(Set(after.map(\.url)) == before, "Synth's files are never Pad's")
    #expect(!after.contains { $0.url.lastPathComponent.lowercased().contains("synth") })
}

@Test func aStaleScanCantUninstallAnotherAppsFileWithAnApp() throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let padTarget = try #require(scan(home, pad, apps).first?.uninstall)
    // Synth's files, as a stale or wrong scan might have offered them with Pad.
    let stale = scan(home, synth, apps).filter { $0.ruleID != AppUninstall.appRuleID }.map { $0.uninstalled(with: padTarget, ruleID: AppUninstall.filesRuleID) }
    #expect(stale.count == 3)

    #expect(stale.allSatisfy { check(home, apps: apps).check($0) == .changed })
    #expect(stale.allSatisfy { check(home, apps: Apps(installed: [pad])).check($0) == .changed }, "Also once Synth is gone")
}

/// Decisions 123 and 134 (#556, #647): a run that uninstalled an app touched its row, which the rescan reads again; one the
/// checks refused, or a dry run, touched nothing there.
@Test func onlyARunThatUninstalledSomethingTouchesItsApplicationsRow() async throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let chosen = scan(home, synth, apps).filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }
    func run(_ check: CandidateCheck, dryRun: Bool) async throws -> CatalogExecutionResult {
        let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal-\(UUID()).sqlite"))
        return await CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
            .execute(CatalogApproval(candidates: chosen, dryRun: dryRun))
    }

    let refused = try await run(check(home, running: Running(names: ["Synth"])), dryRun: false)
    #expect(refused.records.allSatisfy { $0.state == .skipped })
    #expect(refused.touchedApplications(shown: chosen, plugIns: nil)?.rows == [], "Refused: nothing left")
    #expect((try await run(check(home), dryRun: true)).touchedApplications(shown: chosen, plugIns: nil)?.rows == [], "A dry run changes nothing")
    let uninstalled = try await run(check(home), dryRun: false)
    #expect(uninstalled.records.allSatisfy { $0.state == .succeeded })
    #expect(uninstalled.touchedApplications(shown: chosen, plugIns: nil)?.rows == [synth.path])
}
