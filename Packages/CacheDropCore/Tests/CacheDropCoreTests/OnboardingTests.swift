import Foundation
import Testing
@testable import CacheDropCore

// #783, #784: onboarding's badges, captioned with the categories' short names.

@Test func onboardingBadgesAreCaptionedWithTheOwnersShortNames() {
    #expect(Onboarding.categories.map(\.shortTitle) == ["Developer", "Browsers", "App caches", "Downloads", "Audio", "Photo and video",
                                                        "Models", "App updates", "Logs", "Deleted apps"])
    #expect(CatalogCategory.icloud.shortTitle == "Downloaded iCloud files", "A category onboarding doesn't show keeps its full title")
}
