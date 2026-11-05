import Testing
import CacheDropCore

/// The sidebar's storage line fits one line; its label and tooltip say the same in full, with "free" (#353, #764: Decision 92 rule 1).
@Test func sidebarCapacityReadsFreeOfTotalOnOneLine() {
    let text = SidebarCapacityText(available: 312_000_000_000, total: 1_000_000_000_000)
    #expect(text.line == "312 GB free of 1 TB")
    #expect(text.description == "312 GB free of 1 TB")
}

@Test func sidebarCapacityWithoutFreeSpaceSaysSo() {
    for available: Int64? in [nil, -1] {
        let text = SidebarCapacityText(available: available, total: 1_000_000_000_000)
        #expect(text.line == "Free space unknown")
        #expect(text.description == "Free space unknown")
    }
}

@Test func sidebarCapacityWithoutAConsistentTotalShowsAvailableAlone() {
    for total: Int64? in [nil, 0, 100_000_000_000] {
        let text = SidebarCapacityText(available: 312_000_000_000, total: total)
        #expect(text.line == "312 GB free", "As the line with a total, and the menu bar")
        #expect(text.description == "312 GB free · Disk size unknown")
    }
}

/// Overview's Can be cleaned figure (#764): "At least" already hedges an unknown part, so nothing is added (Decision 92 rule 4).
@Test func canBeCleanedSaysAtLeastWithNoSecondHedge() {
    #expect(CatalogOverview.recommendedText(.atLeast(2_000_000_000)) == "At least 2 GB")
    #expect(CatalogOverview.recommendedText(.measured(0)) == "Empty")
}
