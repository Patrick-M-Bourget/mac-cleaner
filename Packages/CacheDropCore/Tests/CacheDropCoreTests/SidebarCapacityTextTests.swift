import Testing
import CacheDropCore

/// The sidebar's storage line fits one line; "available" moves to its label and tooltip (#353).
@Test func sidebarCapacityReadsAvailableOfTotalOnOneLine() {
    let text = SidebarCapacityText(available: 312_000_000_000, total: 1_000_000_000_000)
    #expect(text.line == "312 GB of 1 TB")
    #expect(text.description == "312 GB available of 1 TB")
}

@Test func sidebarCapacityWithoutFreeSpaceSaysSo() {
    for available: Int64? in [nil, -1] {
        let text = SidebarCapacityText(available: available, total: 1_000_000_000_000)
        #expect(text.line == "Free space unavailable")
        #expect(text.description == "Free space unavailable")
    }
}

@Test func sidebarCapacityWithoutAConsistentTotalShowsAvailableAlone() {
    for total: Int64? in [nil, 0, 100_000_000_000] {
        let text = SidebarCapacityText(available: 312_000_000_000, total: total)
        #expect(text.line == "312 GB available")
        #expect(text.description == "312 GB available · Total capacity unavailable")
    }
}
