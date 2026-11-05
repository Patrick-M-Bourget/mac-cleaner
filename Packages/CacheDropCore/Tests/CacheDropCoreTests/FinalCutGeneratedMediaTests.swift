import Foundation
import Testing
@testable import CacheDropCore

// #399, Decision 171: Final Cut Pro's render files, optimized and proxy media in each library, from the layout documentation
// and secondary sources give (`<Event>/Render Files`, `<Event>/Transcoded Media/High Quality Media` and `Proxy Media`), not
// observed. Every library here is a temp fixture; the temp home stands in for the system root, so `<home>/Volumes/Shuttle`
// is a connected drive.

private func libraryHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropFinalCut-\(UUID())")
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
private let ruleIDs = [FinalCutGeneratedMedia.renderFilesID, FinalCutGeneratedMedia.optimizedMediaID, FinalCutGeneratedMedia.proxyMediaID]
private let untitled = "Movies/Untitled.fcpbundle/"

/// A library as the sources describe it: generated media in each event folder, beside its original media and the
/// library's and event's own data, and decoys with the same names at other depths or in other cases.
private func makeLibraries(_ home: URL) throws {
    for event in ["Event 1", "5-11-20"] {
        try write(home, untitled + event + "/Render Files/Peaks Data/a/peak", bytes: 1_000)
        try write(home, untitled + event + "/Render Files/High Quality Media/render.mov", bytes: 2_000)
        try write(home, untitled + event + "/Transcoded Media/High Quality Media/optimized.mov", bytes: 3_000)
        try write(home, untitled + event + "/Transcoded Media/Proxy Media/proxy.mov", bytes: 4_000)
        try write(home, untitled + event + "/Original Media/clip.mov", bytes: 5_000)
        try write(home, untitled + event + "/CurrentVersion.fcpevent")
    }
    // A renamed library on a connected drive.
    try write(home, "Volumes/Shuttle/Client/Edit.fcpbundle/Interview/Render Files/render.mov", bytes: 6_000)
    // Never offered: the library's and events' own data, folders with a documented name at another depth or in another case,
    // hidden folders, a folder linked elsewhere, and anything outside a library.
    for kept in ["CurrentVersion.flexolibrary", "Settings.plist", "__Temp/x", "Motion Templates.localized/x",
                 "Event 1/Analysis Files/a", "Event 1/Shared Items/a", "Event 1/Untitled Project/CurrentVersion.fcpproject",
                 "Event 1/Transcoded Media/Other Media/a", "Event 1/Original Media/Render Files/a", "Event 1/Untitled Project/Render Files/a",
                 "Render Files/High Quality Media/a", "Transcoded Media/Proxy Media/a", "High Quality Media/a",
                 ".fcpcache/Event 1/Render Files/a", ".Event/Render Files/a",
                 "Lowercase/render files/a", "Lowercase/transcoded media/proxy media/a", "Lowercase/Transcoded Media/proxy media/a"] {
        try write(home, untitled + kept)
    }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(untitled + "Linked/Transcoded Media"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(untitled + "Linked/Render Files"),
                                               withDestinationURL: home.appendingPathComponent(untitled + "Event 1/Original Media"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(untitled + "Linked/Transcoded Media/Proxy Media"),
                                               withDestinationURL: home.appendingPathComponent(untitled + "Event 1/Original Media"))
    try write(home, "Movies/Not a library/Event 1/Render Files/a")
    try write(home, "Library/Application Support/Hidden.fcpbundle/Event 1/Render Files/a")
}
private func found(_ home: URL, access: FullDiskAccessStatus = .granted) -> CatalogDiscovery {
    Catalog(rules: fixtureRules).discovery(fixture: home, access: access)
}
private func relative(_ candidates: [Candidate], _ ruleID: String, _ home: URL) -> Set<String> {
    Set(candidates.filter { $0.ruleID == ruleID }.map { String($0.url.path.dropFirst(home.path.count + 1)) })
}

@Test func finalCutGeneratedMediaIsOfferedOnlyAtItsDocumentedPlaceInEachLibrary() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeLibraries(home)
    let candidates = found(home).candidates

    #expect(relative(candidates, FinalCutGeneratedMedia.renderFilesID, home)
        == [untitled + "Event 1/Render Files", untitled + "5-11-20/Render Files", "Volumes/Shuttle/Client/Edit.fcpbundle/Interview/Render Files"])
    #expect(relative(candidates, FinalCutGeneratedMedia.optimizedMediaID, home)
        == [untitled + "Event 1/Transcoded Media/High Quality Media", untitled + "5-11-20/Transcoded Media/High Quality Media"])
    #expect(relative(candidates, FinalCutGeneratedMedia.proxyMediaID, home)
        == [untitled + "Event 1/Transcoded Media/Proxy Media", untitled + "5-11-20/Transcoded Media/Proxy Media"])
    // Nothing else inside a library is offered by any rule.
    #expect(candidates.filter { $0.url.path.contains(".fcpbundle") }.allSatisfy { ruleIDs.contains($0.ruleID) })

    // Each item names its library and event, and is grouped and scoped by its library, so sizes add up per library and kind.
    let render = candidates.filter { $0.ruleID == FinalCutGeneratedMedia.renderFilesID }
    #expect(Set(render.compactMap(\.itemName)) == ["Untitled · Event 1", "Untitled · 5-11-20", "Edit · Interview"])
    #expect(Set(render.compactMap(\.profile)) == ["Untitled", "Edit"])
    let edit = try #require(render.first { $0.profile == "Edit" })
    #expect(edit.scopeRoot?.lastPathComponent == "Edit.fcpbundle")
    #expect(edit.logicalBytes == 6_000)
    let proxy = try #require(candidates.first { $0.ruleID == FinalCutGeneratedMedia.proxyMediaID })
    #expect(proxy.logicalBytes == 4_000 && proxy.sizeComplete)
    for id in ruleIDs { #expect(Catalog(rules: fixtureRules).rule(id)?.category == .photoVideo) }
}

/// Final Cut Pro, and only it, is installed.
private struct FinalCutInstalled: AppLookup {
    func app(bundleID: String) -> InstalledApp? {
        bundleID == "com.apple.FinalCut" ? InstalledApp(name: "Final Cut Pro", bundleID: bundleID, path: "/Applications/Final Cut Pro.app") : nil
    }
    func app(updaterCacheDirName name: String) -> InstalledApp? { nil }
    func jetBrainsIDEs() -> [JetBrainsInstall] { [] }
}

@Test func withoutFullDiskAccessNoLibraryIsReadAndOnlyAnInstalledFinalCutNeedsAccess() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeLibraries(home)
    let notInstalled = found(home, access: .notGranted)
    #expect(!notInstalled.candidates.contains { ruleIDs.contains($0.ruleID) })
    #expect(!notInstalled.notAccessible.contains { ruleIDs.contains($0.id) })
    let installed = Catalog(rules: BuiltInCatalog.rules(apps: FinalCutInstalled())).discovery(fixture: home, access: .notGranted)
    #expect(!installed.candidates.contains { ruleIDs.contains($0.ruleID) })
    #expect(Set(installed.notAccessible.map(\.id)).isSuperset(of: ruleIDs))
}

@Test func finalCutGeneratedMediaIsRefusedWhileFinalCutRunsAndRemovedPermanently() async throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeLibraries(home)
    let catalog = Catalog(rules: fixtureRules)
    let items = catalog.discovery(fixture: home, access: .granted).candidates.filter { $0.itemName == "Untitled · Event 1" }
    #expect(items.count == 3)
    for running in ["com.apple.FinalCut", "com.apple.FinalCutTrial"] {
        let check = CandidateCheck(catalog: catalog, running: Running(bundleIDs: [running]), home: home)
        #expect(items.allSatisfy { check.check($0) == .ownerRunning("Final Cut Pro") })
    }

    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: Running(), home: home), measure: { _ in nil }, trash: TrashNeverUsed())
    let records = await run.execute(CatalogApproval(candidates: items, dryRun: false)).records
    #expect(records.count == 3 && records.allSatisfy { $0.state == .succeeded })
    let event = home.appendingPathComponent(untitled + "Event 1")
    for gone in ["Render Files", "Transcoded Media/High Quality Media", "Transcoded Media/Proxy Media"] {
        #expect(!FileManager.default.fileExists(atPath: event.appendingPathComponent(gone).path))
    }
    for kept in ["Original Media/clip.mov", "CurrentVersion.fcpevent", "Transcoded Media/Other Media/a", "Analysis Files/a", "Untitled Project/Render Files/a"] {
        #expect(FileManager.default.fileExists(atPath: event.appendingPathComponent(kept).path))
    }
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(untitled + "5-11-20/Render Files").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(untitled + "CurrentVersion.flexolibrary").path))
}

@Test func theCheckKeepsAFolderNoLongerAtItsDocumentedPlace() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeLibraries(home)
    let catalog = Catalog(rules: fixtureRules)
    let item = try #require(catalog.discovery(fixture: home, access: .granted).candidates.first {
        $0.ruleID == FinalCutGeneratedMedia.proxyMediaID && $0.itemName == "Untitled · Event 1"
    })
    let check = CandidateCheck(catalog: catalog, running: Running(), home: home)
    #expect(check.check(item) == nil)
    // The event's Transcoded Media replaced by a link to its original media: the same folder is no longer reached there.
    let transcoded = home.appendingPathComponent(untitled + "Event 1/Transcoded Media")
    let moved = home.appendingPathComponent("Moved Transcoded Media")
    try FileManager.default.moveItem(at: transcoded, to: moved)
    try FileManager.default.createSymbolicLink(at: transcoded, withDestinationURL: moved)
    #expect(check.check(item) != nil)
    #expect(FinalCutGeneratedMedia.refusal(for: item, root: try #require(item.scopeRoot)) == .changed)
    // An item whose scope isn't a library is never acted on.
    #expect(FinalCutGeneratedMedia.refusal(for: item, root: home.appendingPathComponent("Movies")) == .changed)
}

@Test func smartCleanTakesOnlyRenderFilesAndOptimizedAndProxyMediaSayTheyMayBeTheOnlyCopy() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeLibraries(home)
    let catalog = Catalog(rules: fixtureRules)
    let candidates = catalog.discovery(fixture: home, access: .granted).candidates.filter { ruleIDs.contains($0.ruleID) }
    let plan = RecommendedPlan(catalog: catalog, candidates: candidates, check: { _ in nil })
    #expect(!plan.candidates.isEmpty && plan.candidates.allSatisfy { $0.ruleID == FinalCutGeneratedMedia.renderFilesID })
    #expect(plan.candidates.count == candidates.filter { $0.ruleID == FinalCutGeneratedMedia.renderFilesID }.count)
    for id in [FinalCutGeneratedMedia.optimizedMediaID, FinalCutGeneratedMedia.proxyMediaID] {
        let rule = try #require(catalog.rule(id))
        #expect(rule.consequence == "If the original media is offline or was deleted, this can be the only copy.")
        #expect(rule.choosesItems && rule.action == .delete)
    }
    let render = try #require(catalog.rule(FinalCutGeneratedMedia.renderFilesID))
    #expect(render.action == .delete && !render.choosesItems)
}

@Test func anInterruptedDeleteInALibraryIsOfferedAgainUnderItsRule() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeLibraries(home)
    let remnant = untitled + "Event 1/Transcoded Media/" + Catalog.deletionRemnantName(for: FinalCutGeneratedMedia.proxyMediaID)
    try write(home, remnant + "/proxy.mov", bytes: 700)
    // Another rule's remnant name in a library is never offered.
    try write(home, untitled + "Event 1/" + Catalog.deletionRemnantName(for: "app-caches") + "/a")
    let catalog = Catalog(rules: fixtureRules)
    let candidates = catalog.discovery(fixture: home, access: .granted).candidates
    let item = try #require(candidates.first { $0.url.path.hasSuffix(remnant) })
    #expect(item.ruleID == FinalCutGeneratedMedia.proxyMediaID && item.action == .delete && item.profile == "Untitled")
    #expect(CandidateCheck(catalog: catalog, running: Running(), home: home).check(item) == nil)
    #expect(!candidates.contains { $0.url.lastPathComponent.contains("app-caches") })
}
