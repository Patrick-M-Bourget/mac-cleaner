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
