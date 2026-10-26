import Testing
import Foundation
import StorageAlerts

private let en = Locale(identifier: "en_US")

/// #131: the menu bar item reads free space in a short, calm form.
@Test func menuBarShowsFreeSpaceInWholeDecimalUnits() {
    #expect(MenuBarStatus.freeSpaceTitle(available: 38_400_000_000, locale: en) == "38 GB free")
    #expect(MenuBarStatus.freeSpaceTitle(available: 38_600_000_000, locale: en) == "39 GB free")
    #expect(MenuBarStatus.freeSpaceTitle(available: 4_260_000_000, locale: en) == "4.3 GB free")
    #expect(MenuBarStatus.freeSpaceTitle(available: 1_240_000_000_000, locale: en) == "1.2 TB free")
    #expect(MenuBarStatus.freeSpaceTitle(available: 400_000_000, locale: en) == "0.4 GB free")
}

@Test func menuBarShowsNoNumberWhenCapacityIsUnknown() {
    #expect(MenuBarStatus.freeSpaceTitle(available: nil, locale: en) == nil)
    #expect(MenuBarStatus.freeSpaceTitle(available: -1, locale: en) == nil)
}

@Test func menuOffersTheRecommendedPlanOnlyWhenThereIsOne() {
    #expect(MenuBarStatus.items(hasRecommendedPlan: false) == [.openStill, .scanAgain, .settings, .quit])
    #expect(MenuBarStatus.items(hasRecommendedPlan: true) == [.openStill, .scanAgain, .reviewRecommendedPlan, .settings, .quit])
    #expect(MenuBarStatus.Item.reviewRecommendedPlan.title == "Review recommended plan…")
}
