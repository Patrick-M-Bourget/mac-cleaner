import Foundation
import Testing
@testable import CacheDropCore

// Rule families (#289): the app-tied rules say which family they are in, and every other rule is in none.
@Test func onlyTheAppTiedRulesHaveAFamilyAndOnlyTheirPossiblyRelatedOnesAreTickedOneByOne() {
    #expect(RemovedAppLeftovers.rules.map(\.family) == [.removedAppLeftovers, .removedAppLeftovers])
    #expect(AppUninstall.rules.map(\.family) == [.appUninstall, .appUninstall, .appUninstall])
    #expect(PlugInUninstall.rules.map(\.family) == [.plugInUninstall, .plugInUninstall, .plugInUninstall])
    #expect(fixtureRules.filter { $0.family != nil }.count == 8)
    // A JetBrains folder is chosen item by item too, but in the plan, never one by one away from its category.
    #expect(Set(fixtureRules.filter(\.selectedOneByOne).map(\.id)) == ["removed-app-possibly-related", "uninstall-app-possibly-related", "uninstall-plugin-shared"])
    #expect(fixtureRules.contains { $0.itemByItem && $0.family == nil })
}

// #356: an item ticked one by one is chosen in the app: clicking its row ticks it, Reveal in Finder sits beside it, and its
// rule's own row reveals nothing. Every other rule keeps its rows as Finder links, its items chosen by their checkboxes.
@Test func itemsTickedOneByOneAreChosenByClickingTheirRowsAndTheirRuleRowRevealsNothing() {
    let oneByOne: Set = ["removed-app-possibly-related", "uninstall-app-possibly-related", "uninstall-plugin-shared"]
    for rule in fixtureRules {
        let ticks = oneByOne.contains(rule.id)
        #expect(rule.itemRowClick == (ticks ? .tick : .reveal), "\(rule.id)")
        #expect(rule.ruleRowReveals == !ticks, "\(rule.id)")
    }
}
