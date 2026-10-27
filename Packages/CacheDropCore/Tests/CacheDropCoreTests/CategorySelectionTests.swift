import Foundation
import Testing
@testable import CacheDropCore

// #240: a plan category's checkbox when some or all of its items are chosen one by one (possibly related leftovers, #173).
// Nothing here touches disk.

private let confirmed = RemovedAppLeftovers.rules[0], possible = RemovedAppLeftovers.rules[1]
private func item(_ rule: CleanupRule, _ name: String) -> Candidate {
    Candidate(ruleID: rule.id, action: rule.action, url: fixtureNoHome.appendingPathComponent(name), resourceID: "1:\(name)", isDirectory: true, toolURL: nil,
              volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1_000, allocatedBytes: 1_000, sizeComplete: true, lastUsed: nil,
              observedAt: Date(), profile: nil)
}
private func selection(_ items: [Candidate], chosen: [Candidate] = []) -> CategorySelection {
    CategorySelection(rules: RemovedAppLeftovers.rules, candidates: items, selected: Set(chosen.map(\.id)))
}

@Test func aCategoryOfOnlyPossiblyRelatedItemsOpensItsListInsteadOfDoingNothing() {
    let gone = item(possible, "Gone"), synth = item(possible, "Synth")
    let none = selection([gone, synth])
    #expect(none.state == .unchecked)
    #expect(none.toggle == .showItems)

    // Ticked one by one, they show on the category's checkbox, and it clears them.
    let one = selection([gone, synth], chosen: [gone])
    #expect(one.state == .mixed)
    #expect(one.toggle == .clear([gone.id, synth.id]))
    #expect(selection([gone, synth], chosen: [gone, synth]).state == .checked)
}

@Test func theCategoryChoosesOnlyWhatMayBeChosenTogetherAndClearsEverything() {
    let synth = item(confirmed, "com.gone.synth.plist"), gone = item(possible, "Gone")
    let none = selection([synth, gone])
    #expect(none.state == .unchecked)
    // A possibly related item is never ticked with its category (#173).
    #expect(none.toggle == .choose([synth.id]))

    let together = selection([synth, gone], chosen: [synth])
    #expect(together.state == .checked)
    #expect(together.toggle == .clear([synth.id, gone.id]))

    let byHand = selection([synth, gone], chosen: [gone])
    #expect(byHand.state == .mixed)
    #expect(byHand.toggle == .choose([synth.id]))
    #expect(selection([synth, gone], chosen: [synth, gone]).toggle == .clear([synth.id, gone.id]))
}

@Test func aCategoryOfOnePossiblyRelatedItemStillListsIt() {
    let catalog = Catalog(rules: RemovedAppLeftovers.rules)
    let overview = CatalogOverview(catalog: catalog, candidates: [item(possible, "Gone")])
    // One rule and one item would show the category's checkbox alone, which can't choose it.
    #expect(overview.rows.map(\.planLayout) == [.items])
    #expect(CatalogOverview(catalog: catalog, candidates: [item(confirmed, "com.gone.synth.plist")]).rows.map(\.planLayout) == [.categoryOnly])
}
