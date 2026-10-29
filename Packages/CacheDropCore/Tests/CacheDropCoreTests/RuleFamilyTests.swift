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

// #356, #367: clicking an item's row ticks it, as its checkbox does; Finder is always its own Reveal link, never a row click.
// A rule's own row ticks the rule, except a rule of items ticked one by one (Decision 49), whose row is inert. What can't be
// chosen (a guidance rule's libraries) has inert rows.
@Test func clickingAChoosableRowTicksItAndEverythingElseIsInert() throws {
    let rules = Dictionary(uniqueKeysWithValues: fixtureRules.map { ($0.id, $0) })
    let expected: [(id: String, item: CleanupRule.RowClick, rule: CleanupRule.RowClick)] = [
        ("removed-app-leftovers", .tick, .tick), ("removed-app-possibly-related", .tick, .inert),
        ("uninstall-app-possibly-related", .tick, .inert), ("uninstall-plugin-shared", .tick, .inert),
        (CleanupRule.downloadsID, .tick, .tick), ("photos-library", .inert, .inert),
    ]
    for (id, item, rule) in expected {
        let found = try #require(rules[id], "\(id)")
        #expect(found.itemRowClick == item, "\(id)")
        #expect(found.ruleRowClick == rule, "\(id)")
    }
}
