import Testing
import CacheDropCore

// #749: a plan item's identifier is unique within its rule too, not only across rules (#744).

@Test func aNameOnlyOneItemOfTheRuleHasKeepsTheRuleAndName() {
    let repeated = PlanItemIdentifier.repeatedNames(["Setup.dmg", "Other.pkg"])
    #expect(repeated.isEmpty)
    #expect(PlanItemIdentifier.make(ruleID: "downloads", name: "Setup.dmg", path: "/Users/a/Downloads/Setup.dmg", repeated: repeated)
            == "downloads-Setup.dmg")
}

@Test func twoSameNamedItemsOfOneRuleEachGetTheirOwnIdentifier() {
    let paths = ["/Users/a/Downloads/Setup.dmg", "/Users/a/Downloads/Old/Setup.dmg"]
    let repeated = PlanItemIdentifier.repeatedNames(["Setup.dmg", "Other.pkg", "Setup.dmg"])
    #expect(repeated == ["Setup.dmg"])
    let ids = paths.map { PlanItemIdentifier.make(ruleID: "downloads", name: "Setup.dmg", path: $0, repeated: repeated) }
    #expect(ids[0] != ids[1])
    #expect(ids[0] == "downloads-Setup.dmg-" + PlanItemIdentifier.pathTag(paths[0]))
    #expect(ids.allSatisfy { $0.hasPrefix("downloads-Setup.dmg-") && $0.count == "downloads-Setup.dmg-".count + 8 })
    // The other names of the rule are unchanged.
    #expect(PlanItemIdentifier.make(ruleID: "downloads", name: "Other.pkg", path: "/Users/a/Downloads/Other.pkg", repeated: repeated)
            == "downloads-Other.pkg")
}

@Test func thePathTagIsShortAndTheSameEveryLaunch() {
    // 32-bit FNV-1a, not Swift's per-launch seeded `Hasher`, so a journey can work it out from the fixture's path.
    #expect(PlanItemIdentifier.pathTag("") == "811c9dc5")
    #expect(PlanItemIdentifier.pathTag("a") == "e40c292c")
    #expect(PlanItemIdentifier.pathTag("/Users/a/Downloads/Setup.dmg") != PlanItemIdentifier.pathTag("/Users/a/Downloads/Old/Setup.dmg"))
}
