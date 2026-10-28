import Foundation
import Testing
import CacheDropCore

private let GB: Int64 = 1_000_000_000

@Test func theThreeLargestCategoriesGetTheirOwnSegmentAndTheRestFoldIntoOther() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [
        (.logs, .measured(1 * GB)), (.developer, .measured(12 * GB)), (.browser, .measured(3 * GB)),
        (.downloads, .measured(5 * GB)), (.models, .measured(2 * GB)),
    ], trash: .empty)

    #expect(breakdown.segments.map(\.part) == [.category(.developer), .category(.downloads), .category(.browser), .other([.models, .logs])])
    #expect(breakdown.segments.map(\.bytes) == [12 * GB, 5 * GB, 3 * GB, 3 * GB])
    #expect(breakdown.segments.last?.estimate == .measured(3 * GB))
    #expect(!breakdown.isScaled)
}

@Test func unknownAndZeroByteSizesAreNeverDrawnButALowerBoundIs() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [
        (.developer, .unknown), (.browser, .measured(0)), (.downloads, .atLeast(4 * GB)), (.models, .about(2 * GB)),
    ], trash: .unknown)

    #expect(breakdown.segments.map(\.part) == [.category(.downloads), .category(.models)])
    #expect(breakdown.segments.map(\.estimate) == [.atLeast(4 * GB), .about(2 * GB)])
}

@Test func theTrashGetsItsOwnSegmentAfterTheCategories() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [(.developer, .measured(12 * GB))], trash: .holds(7 * GB))

    #expect(breakdown.segments.map(\.part) == [.category(.developer), .trash])
    #expect(breakdown.segments.last?.estimate == .measured(7 * GB))
    #expect(breakdown.segments.last?.bytes == 7 * GB)
}

@Test func estimatesLargerThanTheUsedSpaceAreScaledToFitAndKeepTheirEstimate() {
    // APFS clones: 300 GB and 150 GB of copies plus 50 GB in the Trash on a disk with 250 GB used.
    let breakdown = StorageBreakdown(used: 250 * GB, total: 1000 * GB, categories: [
        (.developer, .measured(300 * GB)), (.browser, .measured(150 * GB)),
    ], trash: .holds(50 * GB))

    #expect(breakdown.isScaled)
    #expect(breakdown.segments.map(\.bytes) == [150 * GB, 75 * GB, 25 * GB])
    #expect(breakdown.segments.map(\.estimate) == [.measured(300 * GB), .measured(150 * GB), .measured(50 * GB)])
}

@Test func anInconsistentCapacityReadingDrawsNothing() {
    for (used, total) in [(Int64(0), Int64(0)), (1200 * GB, 1000 * GB), (-1, 1000 * GB)] {
        let breakdown = StorageBreakdown(used: used, total: total, categories: [(.developer, .measured(1 * GB))], trash: .holds(GB))
        #expect(breakdown.segments.isEmpty, "used \(used) of \(total)")
    }
}

@Test func aSelectionHighlightsWhatItWouldFreeInsideEachSegment() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [
        (.developer, .measured(12 * GB)), (.downloads, .measured(5 * GB)), (.browser, .measured(3 * GB)),
        (.logs, .measured(2 * GB)), (.system, .measured(1 * GB)),
    ], trash: .holds(GB), highlighted: [.developer: 10 * GB, .logs: 2 * GB, .system: GB])

    #expect(breakdown.segments.map(\.highlightedBytes) == [10 * GB, 0, 0, 3 * GB, 0])
}

@Test func withoutASelectionNothingIsHighlightedOrDimmed() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [(.developer, .measured(12 * GB))], trash: .empty)
    #expect(breakdown.segments.map(\.highlightedBytes) == [nil])
}

@Test func aHighlightIsScaledWithItsSegmentAndNeverExceedsIt() {
    let breakdown = StorageBreakdown(used: 100 * GB, total: 1000 * GB, categories: [(.developer, .measured(200 * GB))], trash: .empty,
                                     highlighted: [.developer: 300 * GB])
    #expect(breakdown.segments.map(\.bytes) == [100 * GB])
    #expect(breakdown.segments.map(\.highlightedBytes) == [100 * GB])
}

@Test func theSidebarShowsOneReclaimableTotalWithoutTheTrash() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [
        (.developer, .measured(12 * GB)), (.downloads, .measured(5 * GB)), (.browser, .measured(3 * GB)), (.logs, .measured(2 * GB)),
    ], trash: .holds(7 * GB))
    #expect(breakdown.reclaimableBytes == 22 * GB)
}

@Test func overviewsCategoriesAndASelectionOfFoundItemsFeedTheBreakdown() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropBreakdown-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    for (folder, bytes) in [("a", 40_960), ("b", 8192), ("c", 16384)] {
        let file = home.appendingPathComponent(folder + "/f")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: file)
    }
    let rule = { (id: String, category: CatalogCategory) in
        CleanupRule(id: id, category: category, title: id, detail: "", consequence: "", regen: .cache, action: .delete, locations: [id], owner: nil)
    }
    let catalog = Catalog(rules: [rule("a", .developer), rule("b", .browser), rule("c", .browser)])
    let found = catalog.discover(fixture: home)
    let overview = CatalogOverview(catalog: catalog, candidates: found)

    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, overview: overview, trash: .empty,
                                     highlighting: found.filter { $0.ruleID == "b" })

    #expect(breakdown.segments.map(\.part) == [.category(.developer), .category(.browser)])
    #expect(breakdown.segments.map(\.estimate) == overview.rows.map(\.estimate))
    let browser = try #require(breakdown.segments.last)
    #expect(browser.highlightedBytes == found.first { $0.ruleID == "b" }?.estimatedBytes)
    #expect(breakdown.segments.first?.highlightedBytes == 0)
}

@Test func aSegmentsSizeReadsAsTheSameUpToEstimateAsOverview() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [
        (.developer, .measured(12_200_000_000)), (.downloads, .atLeast(5 * GB)), (.models, .about(3 * GB)),
    ], trash: .holds(2 * GB))
    #expect(breakdown.segments.map(\.sizeText) == ["up to 12.2 GB", "at least 5 GB", "about 3 GB", "2 GB"])
}

/// #343: a selection's Trash-bound items free nothing until the Trash is emptied (SPEC section 6), so they leave their
/// category's segment for their own, drawn whole, just before the Trash at the tip.
@Test func aSelectionsTrashBoundItemsGetTheirOwnSegmentBesideTheTrash() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [(.developer, .measured(12 * GB)), (.downloads, .measured(5 * GB))],
                                     trash: .holds(GB), highlighted: [.developer: 10 * GB], toTrash: [.downloads: 4 * GB])
    #expect(breakdown.segments.map(\.part) == [.category(.developer), .category(.downloads), .goingToTrash, .trash])
    #expect(breakdown.segments.map(\.bytes) == [12 * GB, 1 * GB, 4 * GB, 1 * GB])
    #expect(breakdown.segments.map(\.highlightedBytes) == [10 * GB, 0, 4 * GB, 0])
    #expect(breakdown.segments.map(\.sizeText) == ["up to 12 GB", "up to 1 GB", "up to 4 GB", "1 GB"], "Downloads names what stays, never the 4 GB twice")
    #expect(breakdown.reclaimableBytes == 13 * GB, "Neither Trash part is reclaimable yet")
}

@Test func withoutTrashBoundItemsThereIsNoSuchSegment() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [(.developer, .measured(12 * GB))], trash: .empty,
                                     highlighted: [.developer: 2 * GB], toTrash: [:])
    #expect(breakdown.segments.map(\.part) == [.category(.developer)])
}

@Test func aSelectionOfFoundItemsSplitsWhatGoesToTheTrash() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropBreakdown-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    for (folder, bytes) in [("cache", 40_960), ("installers", 16_384)] {
        let file = home.appendingPathComponent(folder + "/f")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: file)
    }
    let catalog = Catalog(rules: [
        CleanupRule(id: "cache", category: .developer, title: "cache", detail: "", consequence: "", regen: .cache, action: .delete, locations: ["cache"], owner: nil),
        CleanupRule(id: "installers", category: .downloads, title: "installers", detail: "", consequence: "", regen: .userFile, action: .trash, locations: ["installers"], owner: nil),
    ])
    let found = catalog.discover(fixture: home)
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, overview: CatalogOverview(catalog: catalog, candidates: found), trash: .empty,
                                     highlighting: found)
    let installer = try #require(found.first { $0.ruleID == "installers" })
    #expect(breakdown.segments.map(\.part) == [.category(.developer), .goingToTrash])
    #expect(breakdown.segments.last?.bytes == installer.estimatedBytes)
}

/// #343: a category ranks by what stays once its Trash-bound items leave, so a bigger one takes its place among the 3.
@Test func whatStaysDecidesWhichCategoriesGetTheirOwnSegment() {
    let breakdown = StorageBreakdown(used: 400 * GB, total: 1000 * GB, categories: [
        (.developer, .measured(12 * GB)), (.downloads, .measured(10 * GB)), (.browser, .measured(3 * GB)), (.logs, .measured(2 * GB)),
    ], trash: .empty, highlighted: [:], toTrash: [.downloads: 9 * GB])
    #expect(breakdown.segments.map(\.part) == [.category(.developer), .category(.browser), .category(.logs), .other([.downloads]), .goingToTrash])
}
