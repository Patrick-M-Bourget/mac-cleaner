import Foundation
import Testing
@testable import CacheDropCore

/// Decision 134 (#647): after a run that changed Applications, the rescan reads again only the app, plug-in product and
/// leftover groups the run touched, and merges them into what the page shows. Every test uses a temp home with fake apps;
/// installed apps, receipts and the Trash are fixtures.

private struct Apps: AppPresence {
    var installed: [InstalledApp]
    func installedApps() -> [InstalledApp]? { installed }
    func isRegistered(bundleID: String) -> Bool { installed.contains { $0.bundleID.lowercased() == bundleID.lowercased() } }
}
private struct NoReceipts: InstallerReceiptReading { func receipts() -> [InstallerReceipt] { [] } }

/// Synth and Pad, by two makers, each with a container and preferences.
private func twoApps() throws -> (home: URL, synth: InstalledApp, pad: InstalledApp) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropTouched-\(UUID())").resolvingSymlinksInPath()
    for relative in ["Applications/Synth.app/Contents/MacOS/Synth", "Applications/Pad.app/Contents/MacOS/Pad",
                     "Library/Preferences/com.synthco.synth.plist", "Library/Containers/com.synthco.synth/Data/x",
                     "Library/Preferences/com.padco.pad.plist", "Library/Containers/com.padco.pad/Data/x"] {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: file)
    }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    let synth = InstalledApp(name: "Synth", bundleID: "com.synthco.synth", path: home.appendingPathComponent("Applications/Synth.app").path)
    let pad = InstalledApp(name: "Pad", bundleID: "com.padco.pad", path: home.appendingPathComponent("Applications/Pad.app").path)
    return (home, synth, pad)
}
/// Every installed app's items, as the full scan offers them.
private func uninstallable(_ home: URL, _ apps: Apps) -> [Candidate] {
    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    return apps.installed.flatMap { AppUninstall.scan($0, excluding: nil, home: home, apps: apps, receipts: NoReceipts(), leftovers: leftovers) }
}
private func run(_ items: [Candidate], home: URL, apps: Apps, dryRun: Bool = false) async throws -> CatalogExecutionResult {
    try await runAny(items, rules: [rule], home: home, apps: apps, dryRun: dryRun)
}
private func runAny(_ items: [Candidate], rules: [CleanupRule], home: URL, apps: Apps, dryRun: Bool = false) async throws -> CatalogExecutionResult {
    let check = CandidateCheck(catalog: Catalog(rules: AppRuleFamily.rules + rules), running: FixtureNothingRunning(), inUse: FixtureNothingInUse(), home: home,
                               apps: apps)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal-\(UUID()).sqlite"))
    return await CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: FixtureHomeTrash(home: home))
        .execute(CatalogApproval(candidates: items, dryRun: dryRun))
}
/// A catalog rule over Pad's container, standing in for any plan rule whose item may hold an app's file.
private let rule = CleanupRule(id: "containers", category: .system, title: "Containers", detail: "", consequence: "", regen: .cache, action: .trash,
                               locations: ["Library/Containers/com.padco.pad"], owner: nil)

@Test func aRunTouchesTheRowsOfTheAppsItUninstalledAndNoOthers() async throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let shown = uninstallable(home, apps)
    let synths = shown.filter { $0.uninstall?.path == synth.path }
    try #require(synths.count == 3 && shown.count == 6)

    let uninstalled = try await run(synths, home: home, apps: apps)
    try #require(uninstalled.records.allSatisfy { $0.state == .succeeded })
    let touched = try #require(uninstalled.touchedApplications(shown: shown, plugIns: nil))
    #expect(touched.rows == [synth.path], "Only Synth's row is read again")
    #expect(shown.filter(touched.touches).map(\.id) == synths.map(\.id))

    #expect(try await run(synths, home: home, apps: apps, dryRun: true).touchedApplications(shown: shown, plugIns: nil)?.rows == [], "A dry run touches nothing")
}

@Test func aRunWhoseUninstalledItemsCantBeTiedToARowNeedsAFullScan() async throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let shown = uninstallable(home, apps)
    let uninstalled = try await run(shown.filter { $0.uninstall?.path == synth.path }, home: home, apps: apps)
    #expect(uninstalled.touchedApplications(shown: shown.filter { $0.uninstall?.path != synth.path }, plugIns: nil) == nil, "Not among the rows shown: no guessing")
    // A plug-in product's row is read again only against the inventory it was found in.
    let asProduct = shown.map { item -> Candidate in
        guard item.uninstall?.path == synth.path else { return item }
        var product = item
        product.uninstall?.plugIn = AppUninstall.Target.PlugIn()
        return product
    }
    #expect(uninstalled.touchedApplications(shown: asProduct, plugIns: nil) == nil)
    #expect(uninstalled.touchedApplications(shown: asProduct, plugIns: PlugInInventory(products: [])) == nil)
}

@Test func anotherRulesItemAtOrHoldingAnAppsFileTouchesThatAppsRow() async throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let shown = uninstallable(home, apps)
    let container = Catalog(rules: [rule]).discover(fixture: home)
    try #require(container.count == 1)
    let cleaned = try await run(container, home: home, apps: apps)
    try #require(cleaned.records.allSatisfy { $0.state == .succeeded })
    #expect(cleaned.touchedApplications(shown: shown + container, plugIns: nil)?.rows == [pad.path], "Pad's row listed the container the plan cleaned")
}

private func rescanning(_ touched: TouchedApplications, _ shown: [Candidate], home: URL, apps: Apps) -> [Candidate] {
    touched.rescanning(shown, home: home, systemRoot: home, apps: apps, receipts: ReceiptListings([:]), plugIns: nil, excluding: nil, leftovers: [], offered: [])
}

@Test func theRescanReplacesTouchedRowsAndKeepsEveryOtherRowAsShown() async throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let shown = uninstallable(home, apps)
    let plist = try #require(shown.first { $0.url.lastPathComponent == "com.synthco.synth.plist" })
    let cleaned = try await run([plist], home: home, apps: apps)
    // Pad gained a file meanwhile; its row isn't read again, so it keeps what the last full scan found.
    try Data(count: 10).write(to: home.appendingPathComponent("Library/Preferences/com.padco.pad.extra.plist"))
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Saved Application State/com.padco.pad.savedState"), withIntermediateDirectories: true)
    let touched = try #require(cleaned.touchedApplications(shown: shown, plugIns: nil))

    let merged = rescanning(touched, cleaned.keptDuringRescan(shown), home: home, apps: apps)

    #expect(Set(merged.filter { $0.uninstall?.path == synth.path }.map(\.url.lastPathComponent)) == ["Synth.app", "com.synthco.synth"], "Synth's row, refreshed")
    #expect(merged.filter { $0.uninstall?.path == pad.path } == shown.filter { $0.uninstall?.path == pad.path }, "Pad's row as it was")
}

@Test func anUninstalledAppsRowLeavesThoughTheListOfAppsStillHasIt() async throws {
    let (home, synth, pad) = try twoApps()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let shown = uninstallable(home, apps)
    let uninstalled = try await run(shown.filter { $0.uninstall?.path == synth.path }, home: home, apps: apps)
    let touched = try #require(uninstalled.touchedApplications(shown: shown, plugIns: nil))

    for presence in [apps, Apps(installed: [pad])] {
        let merged = rescanning(touched, uninstalled.keptDuringRescan(shown), home: home, apps: presence)
        #expect(!merged.contains { $0.isUninstalled(with: synth.path) }, "Spotlight may still list it; its bundle is gone")
        #expect(merged.filter { $0.isUninstalled(with: pad.path) }.count == 3)
    }
}

/// Leftovers of Old, removed earlier, and of Gone, removed earlier by another maker; Synth and Pad installed.
private func withLeftovers() throws -> (home: URL, synth: InstalledApp, pad: InstalledApp) {
    let (home, synth, pad) = try twoApps()
    for relative in ["Library/Containers/com.oldco.old/Data/x", "Library/Preferences/com.oldco.old.plist", "Library/Containers/com.goneco.gone/Data/x"] {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: file)
    }
    return (home, synth, pad)
}
private func names(_ items: [Candidate]) -> Set<String> { Set(items.map(\.url.lastPathComponent)) }

@Test func cleaningFilesFromADeletedAppReadsAgainOnlyThatMakersLeftovers() async throws {
    let (home, synth, pad) = try withLeftovers()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    try #require(names(leftovers) == ["com.oldco.old", "com.oldco.old.plist", "com.goneco.gone"])
    let container = try #require(leftovers.first { $0.url.lastPathComponent == "com.oldco.old" })
    let cleaned = try await run([container], home: home, apps: apps)
    try #require(cleaned.records.allSatisfy { $0.state == .succeeded })
    // Gone's maker left another file meanwhile; its leftovers aren't read again.
    try Data(count: 10).write(to: home.appendingPathComponent("Library/Preferences/com.goneco.gone.plist"))
    let touched = try #require(cleaned.touchedApplications(shown: leftovers, plugIns: nil))
    #expect(touched.rows.isEmpty)

    let merged = touched.rescanningLeftovers(cleaned.keptDuringRescan(leftovers), home: home, apps: apps, receipts: NoReceipts())

    #expect(names(merged) == ["com.oldco.old.plist", "com.goneco.gone"])
    #expect(merged.first { $0.url.lastPathComponent == "com.goneco.gone" } == leftovers.first { $0.url.lastPathComponent == "com.goneco.gone" }, "As shown")
}

@Test func filesAnAppLeftAppearAsFilesFromADeletedAppOnceItIsUninstalled() async throws {
    let (home, synth, pad) = try withLeftovers()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let shownLeftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    let shown = uninstallable(home, apps)
    // Only Synth's bundle was ticked: its container and preferences stay on disk, now an uninstalled app's.
    let bundle = try #require(shown.first { $0.url.path == synth.path })
    let uninstalled = try await run([bundle], home: home, apps: apps)
    let touched = try #require(uninstalled.touchedApplications(shown: shown + shownLeftovers, plugIns: nil))

    let merged = touched.rescanningLeftovers(shownLeftovers, home: home, apps: Apps(installed: [pad]), receipts: NoReceipts())

    #expect(names(merged) == ["com.oldco.old", "com.oldco.old.plist", "com.goneco.gone", "com.synthco.synth", "com.synthco.synth.plist"])
    #expect(Array(merged.prefix(3)) == shownLeftovers, "The others as shown")
}

@Test func anotherRulesItemAtAFileFromADeletedAppReadsItsMakersLeftoversAgain() async throws {
    let (home, synth, pad) = try withLeftovers()
    defer { try? FileManager.default.removeItem(at: home) }
    let apps = Apps(installed: [synth, pad])
    let leftovers = RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts())
    let oldsContainer = CleanupRule(id: "old", category: .system, title: "Old", detail: "", consequence: "", regen: .cache, action: .trash,
                                    locations: ["Library/Containers/com.oldco.old"], owner: nil)
    let data = Catalog(rules: [oldsContainer]).discover(fixture: home)
    try #require(data.count == 1)
    let cleaned = try await runAny(data, rules: [oldsContainer], home: home, apps: apps)
    try #require(cleaned.records.allSatisfy { $0.state == .succeeded })
    let touched = try #require(cleaned.touchedApplications(shown: leftovers + data, plugIns: nil))

    #expect(names(touched.rescanningLeftovers(leftovers, home: home, apps: apps, receipts: NoReceipts())) == ["com.oldco.old.plist", "com.goneco.gone"],
            "Its container, cleaned by the plan, never shows as still there")
}
