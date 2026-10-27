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
private struct HomeTrash: TrashMoving {
    let home: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        let destination = home.appendingPathComponent(".Trash/" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
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
private func scan(_ home: URL, _ app: InstalledApp, _ apps: Apps, own: String? = "com.cachedrop.app") -> [Candidate] {
    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    return AppUninstall.scan(app, excluding: own, home: home, apps: apps, receipts: NoReceipts(), leftovers: leftovers)
}
private func check(_ home: URL, running: Running = Running()) -> CandidateCheck {
    CandidateCheck(catalog: Catalog(rules: AppUninstall.rules), running: running, inUse: FixtureNothingInUse(), home: home)
}
private func names(_ items: [Candidate], _ rule: String) -> Set<String> { Set(items.filter { $0.ruleID == rule }.map(\.url.lastPathComponent)) }

@Test func anAppIsOfferedWithTheFilesItsRemovalWouldLeaveNameOnlyMatchesAsPossiblyRelated() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let found = scan(home, synth, apps)

    #expect(names(found, AppUninstall.appRuleID) == ["Synth.app"])
    #expect(names(found, AppUninstall.filesRuleID) == ["com.maker.synth", "com.maker.synth.plist"], "Tied by bundle ID; license data never offered")
    #expect(names(found, AppUninstall.possiblyRelatedRuleID) == ["Synth"])
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
    let result = await CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: HomeTrash(home: home))
        .execute(CatalogApproval(candidates: [bundle], previewOnly: false))

    #expect(result.records.first?.state == .skipped)
    #expect(result.records.first?.message == CheckRefusal.notPermitted.reason)
    #expect(FileManager.default.fileExists(atPath: app.path))
}

@Test func aRunningAppBlocksItsUninstall() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)

    #expect(found.allSatisfy { check(home, running: Running(names: ["Synth"])).check($0) == .ownerRunning("Synth") })
    #expect(Catalog(rules: AppUninstall.rules).owner(for: found[0]) == RuleOwner(name: "Synth", bundleIDs: ["com.maker.synth"]))
}

@Test func uninstallingMovesTheAppAndItsFilesToTrashAndPutBackRestoresThem() async throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let chosen = scan(home, synth, apps).filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))

    let result = await CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: HomeTrash(home: home))
        .execute(CatalogApproval(candidates: chosen, previewOnly: false))

    #expect(result.records.count == 3 && result.records.allSatisfy { $0.state == .succeeded })
    #expect(!FileManager.default.fileExists(atPath: synth.path))
    let run = try #require(try journal.completedHistory().completedRuns.first)
    #expect(run.title == "Uninstalled Synth · 3 items")
    for record in result.records { #expect(TrashPutBack(journal: journal).putBack(record) == .restored(record.originalURL)) }
    #expect(chosen.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
}

@Test func theReviewSaysWhatStaysAndGroupsFilesByPlace() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)
    let chosen = found.filter { $0.ruleID != AppUninstall.possiblyRelatedRuleID }

    #expect(AppUninstall.staying(chosen: chosen, offered: found) == ["1 item of Synth stay because you didn’t tick them (1 possibly related)."])
    #expect(AppUninstall.staying(chosen: found, offered: found).isEmpty)
    #expect(AppUninstall.byPlace(chosen).map(\.place.lastPathComponent) == ["Applications", "Containers", "Preferences"])
}

@Test func anUninstalledAppsItemsAreChosenOnTheApplicationsPage() throws {
    let (home, synth, apps) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let found = scan(home, synth, apps)
    var selections = CleanupSelections()
    selections.ticked = Set(found.map(\.id))

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
}
