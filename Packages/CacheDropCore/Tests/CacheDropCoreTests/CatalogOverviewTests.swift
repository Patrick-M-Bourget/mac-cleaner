import Foundation
import Testing
@testable import CacheDropCore

/// A temp home folder; tests never read or write the real home.
private func overviewHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropOverview-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ bytes: Int, at relative: String, in home: URL) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
private func rule(_ id: String, _ category: CatalogCategory, _ action: CleanupAction = .delete) -> CleanupRule {
    CleanupRule(id: id, category: category, title: id, detail: "", consequence: "", regen: action == .delete ? .cache : .installer,
                action: action, locations: [id], owner: nil)
}

@Test func overviewHasOneRowPerCategoryInCatalogOrderWithItsSummedEstimate() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "a/f", in: home)
    try write(8192, at: "b/f", in: home)
    try write(16384, at: "c/f", in: home)
    let catalog = Catalog(rules: [rule("b", .browser), rule("a", .developer), rule("c", .browser), rule("missing", .models)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))

    #expect(overview.rows.map(\.category) == [.browser, .developer])
    #expect(overview.rows.map { $0.rules.map(\.id) } == [["b", "c"], ["a"]])
    #expect(overview.rows.first?.estimate == .measured(24576))
    #expect(overview.rows.last?.estimate == .measured(4096))
}

@Test func aLocationThatCouldNotBeMeasuredIsUnknownNeverZero() throws {
    let home = try overviewHome()
    let locked = home.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: home)
    }
    let catalog = Catalog(rules: [rule("locked", .developer)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.rows.map(\.estimate) == [.unknown])
}

@Test func aPartlyMeasuredCategoryIsALowerBound() throws {
    let home = try overviewHome()
    try write(8192, at: "open/f", in: home)
    // Deeper than the git search goes, so only sizing meets the unreadable folder.
    let locked = home.appendingPathComponent("open/a/b/c/d/locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: home)
    }
    let catalog = Catalog(rules: [rule("open", .developer)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.rows.map(\.estimate) == [.atLeast(8192)])
}

@Test func recommendedTotalSumsCandidatesThatReleaseSpaceAndKeepsTrashApart() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(8192, at: "cache/f", in: home)
    try write(12288, at: "build/f", in: home)
    try write(4096, at: "installers/f", in: home)
    let catalog = Catalog(rules: [rule("cache", .browser), rule("build", .developer), rule("installers", .downloads, .trash)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.recommended == .measured(20480))
    #expect(overview.proposedForTrash == .measured(4096))
}

@Test func anUnmeasuredCategoryMakesTheRecommendedTotalALowerBound() throws {
    let home = try overviewHome()
    try write(8192, at: "cache/f", in: home)
    let locked = home.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: home)
    }
    let catalog = Catalog(rules: [rule("cache", .browser), rule("locked", .developer)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.recommended == .atLeast(8192))
    #expect(overview.proposedForTrash == .measured(0))
}

@Test func visibleRowsAreLargestFirstKeepUnknownAfterTheSizedOnesAndListEmptyCategoriesLast() throws {
    let home = try overviewHome()
    try write(4096, at: "small/f", in: home)
    try write(16384, at: "large/f", in: home)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("empty/sub"), withIntermediateDirectories: true)
    let locked = home.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: home)
    }
    let catalog = Catalog(rules: [rule("missing", .updaters), rule("locked", .logs), rule("small", .browser), rule("empty", .models), rule("large", .developer)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.rows.first { $0.category == .models }?.estimate == .measured(0), "An empty location is a 0-byte row")
    // #372: a category that found nothing, or only 0 bytes, stays listed as Empty, below every other, in catalog order.
    #expect(overview.visibleRows.map(\.category) == [.developer, .browser, .logs, .updaters, .models])
    #expect(overview.visibleRows.map(\.isEmpty) == [false, false, false, true, true])
}

@Test func anEmptyCategoryWhoseRulesNeedFullDiskAccessSaysSoInsteadOfEmpty() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let safari = rule("safari", .browser), logs = rule("logs", .logs)
    let catalog = Catalog(rules: [safari, logs])
    // Decision 62: a category CacheDrop couldn't read is never shown as nothing; it needs access, not "Empty".
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home), notAccessible: [safari])
    #expect(overview.visibleRows.map(\.category) == [.browser, .logs])
    #expect(overview.visibleRows.map(\.needsAccess) == [true, false])
    #expect(CatalogOverview(catalog: catalog, candidates: []).visibleRows.allSatisfy { !$0.needsAccess })
}

@Test func overviewNeverListsAsEmptyACategoryItsScanCannotFill() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    func other(_ id: String, _ category: CatalogCategory, action: CleanupAction = .trash, fromPickedFolders: Bool = false, family: AppRuleFamily? = nil) -> CleanupRule {
        CleanupRule(id: id, category: category, title: id, detail: "", consequence: "", regen: .userFile, action: action, locations: [], owner: nil,
                    fromPickedFolders: fromPickedFolders, family: family)
    }
    // App-managed storage has its own row, large and old files come from picked folders, and apps are only what you chose
    // to uninstall; files from deleted apps are found by the scan, so they are listed.
    let catalog = Catalog(rules: [rule("cache", .browser), other("guide", .managed, action: .guidance), other("picked", .files, fromPickedFolders: true),
                                  other("app", .apps, family: .appUninstall), other("plugin", .apps, family: .plugInUninstall),
                                  other("left", .leftovers, family: .removedAppLeftovers)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.visibleRows.map(\.category) == [.browser, .leftovers])
}

@Test func thePlanShowsRuleRowsOnlyWhenACategoryFoundSomethingForTwoOrMoreRules() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "single/f", in: home)
    try write(4096, at: "a/f", in: home)
    try write(4096, at: "b/f", in: home)
    let catalog = Catalog(rules: [rule("single", .developer), rule("a", .browser), rule("b", .browser), rule("missing", .browser)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.rows.map(\.planLayout) == [.categoryOnly, .ruleRows])
}

@Test func aSingleRuleWithSeveralItemsListsItsItemsWithoutARuleRow() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "parent/one/f", in: home)
    try write(4096, at: "parent/two/f", in: home)
    let catalog = Catalog(rules: [CleanupRule(id: "each", category: .models, title: "each", detail: "", consequence: "", regen: .cache,
                                              action: .delete, locations: ["parent/*"], owner: nil)])
    let candidates = catalog.discover(fixture: home)
    #expect(candidates.count == 2)
    let overview = CatalogOverview(catalog: catalog, candidates: candidates)
    #expect(overview.rows.map(\.planLayout) == [.items])
    #expect(overview.rows.first?.itemCount == 2)
}

/// #374: a held item shows on the plan, listed so it can be ticked on its own, but Overview's main size counts only cleanable space.
@Test func aHeldItemIsListedOnThePlanButNotCountedInTheMainSize() throws {
    let home = try overviewHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "single/f", in: home)
    try write(8192, at: "held/f", in: home)
    let catalog = Catalog(rules: [rule("single", .developer), rule("held", .browser)])
    let candidates = catalog.discover(fixture: home).map { found in
        var found = found
        if found.ruleID == "held" { found.hold = CandidateHold(.inUse("Browser")) }
        return found
    }
    let overview = CatalogOverview(catalog: catalog, candidates: candidates)
    #expect(overview.rows.map(\.category) == [.developer, .browser])
    #expect(overview.recommended == SizeEstimate(sum: candidates.filter { $0.ruleID == "single" }.map(SizeEstimate.init)))
    #expect(overview.rows.map(\.planLayout) == [.categoryOnly, .items], "A lone held item is listed, to be ticked on its own")
}
