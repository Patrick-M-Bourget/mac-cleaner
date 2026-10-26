import Foundation
import Testing
import StillCore

/// A temp home folder; tests never read or write the real home.
private func overviewHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillOverview-\(UUID())")
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

@Test func visibleRowsAreLargestFirstHideZeroBytesAndKeepUnknownLast() throws {
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
    let catalog = Catalog(rules: [rule("locked", .logs), rule("small", .browser), rule("empty", .models), rule("large", .developer)])
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))
    #expect(overview.visibleRows.map(\.category) == [.developer, .browser, .logs])
    #expect(overview.rows.first { $0.category == .models }?.estimate == .measured(0), "An empty location is a 0-byte row")
    #expect(!overview.visibleRows.contains { $0.estimate == .measured(0) })
}
