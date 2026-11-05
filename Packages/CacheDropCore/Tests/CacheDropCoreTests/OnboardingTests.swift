import Foundation
import Testing
@testable import CacheDropCore

// #783, #784: onboarding's badges, captioned with the categories' short names.

@Test func onboardingBadgesAreCaptionedWithTheOwnersShortNames() {
    #expect(Onboarding.categories.map(\.shortTitle) == ["Developer", "Browsers", "App caches", "Downloads", "Audio", "Photo and video",
                                                        "Models", "App updates", "Logs", "Deleted apps"])
    #expect(CatalogCategory.icloud.shortTitle == "Downloaded iCloud files", "A category onboarding doesn't show keeps its full title")
}

private func rule(_ id: String, _ category: CatalogCategory, _ action: CleanupAction = .delete) -> CleanupRule {
    CleanupRule(id: id, category: category, title: id, detail: "", consequence: "", regen: .cache, action: action, locations: [id], owner: nil)
}

// Discovery checks rules in catalog order, so a category has finished once the last of its rules has.
@Test func aCategoryLightsUpOnceItsLastRuleIsReadAndEveryOneOnceTheScanMovesOn() {
    let catalog = Catalog(rules: [rule("d1", .developer), rule("b1", .browser), rule("d2", .developer), rule("m", .models, .guidance),
                                  rule("x", .files)])
    let checking = CatalogScanPhase.location(title: "", number: 3, total: 4)
    #expect(Onboarding.finished(in: catalog, phase: .starting, lastFinishedRuleID: nil) == [])
    #expect(Onboarding.finished(in: catalog, phase: checking, lastFinishedRuleID: "d1") == [])
    #expect(Onboarding.finished(in: catalog, phase: checking, lastFinishedRuleID: "b1") == [.browser])
    #expect(Onboarding.finished(in: catalog, phase: checking, lastFinishedRuleID: "x") == [.browser, .developer],
            "Models has only guidance and lights with the rest; Large and old files has no badge")
    let afterDiscovery = Onboarding.finished(in: catalog, phase: .removedAppLeftovers, lastFinishedRuleID: "x")
    #expect(afterDiscovery == Set(Onboarding.categories).subtracting([.leftovers]), "Files from deleted apps are read next")
    #expect(Onboarding.finished(in: catalog, phase: .appsAndPlugIns, lastFinishedRuleID: "x") == Set(Onboarding.categories))
}

private func onboardingHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropOnboarding-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ bytes: Int, at relative: String, in home: URL) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

// Ready follows Smart clean: its Free up figure over what it would clean, the three largest of those categories.
@Test func readyShowsSmartCleansFreeUpFigureAndItsThreeLargestCategories() throws {
    let home = try onboardingHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(8192, at: "d/f", in: home)
    try write(4096, at: "b/f", in: home)
    try write(16384, at: "l/f", in: home)
    try write(4096 * 3, at: "m/f", in: home)
    try write(4096 * 10, at: "t/f", in: home)
    let catalog = Catalog(rules: [rule("d", .developer), rule("b", .browser), rule("l", .logs), rule("m", .models), rule("t", .downloads, .trash)])
    let ready = try #require(Onboarding.ready(smartClean: catalog.discover(fixture: home), catalog: catalog))
    #expect(ready.found == 40960, "What goes to the Trash isn't freed space")
    #expect(ready.top.map(\.category) == [.logs, .models, .developer])
    #expect(ready.top.map(\.estimate) == [.measured(16384), .measured(12288), .measured(8192)])
}

// Decision 132's precedent: a run that only moves items to the Trash reports what it moved.
@Test func readyWithOnlyTrashBoundItemsShowsTheirTotal() throws {
    let home = try onboardingHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096 * 10, at: "t/f", in: home)
    let catalog = Catalog(rules: [rule("t", .downloads, .trash)])
    let ready = try #require(Onboarding.ready(smartClean: catalog.discover(fixture: home), catalog: catalog))
    #expect(ready.found == 40960)
    #expect(ready.top.map(\.category) == [.downloads])
}

@Test func readyIsNothingFoundOnlyWhenSmartCleanHasNothingToClean() {
    #expect(Onboarding.ready(smartClean: [], catalog: Catalog(rules: [rule("d", .developer)])) == nil)
}

@Test func foundSoFarIsOverviewsRecommendedFigure() throws {
    let home = try onboardingHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(8192, at: "d/f", in: home)
    try write(4096, at: "t/f", in: home)
    let catalog = Catalog(rules: [rule("d", .developer), rule("t", .downloads, .trash)])
    #expect(Onboarding.found(CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home))) == 8192)
    #expect(Onboarding.found(nil) == 0, "Nothing so far before the first location finishes")
}
