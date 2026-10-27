import Foundation
import Testing
@testable import CacheDropCore

/// An item a rule found, as the scan would offer it. Nothing here touches disk.
private func item(_ ruleID: String, name: String? = nil) -> Candidate {
    let rule = Catalog(rules: fixtureRules).rule(ruleID)
    return Candidate(ruleID: ruleID, action: rule?.action ?? .delete, url: fixtureNoHome.appendingPathComponent(name ?? ruleID), resourceID: "1:\((name ?? ruleID).hashValue)",
                     isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1_000, allocatedBytes: 1_000,
                     sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
}
private let catalog = Catalog(rules: fixtureRules)
private let npm = item("npm-cache"), logs = item("app-logs"), installer = item("downloads-installers"), derived = item("xcode-derived-data")
private let scan = [npm, logs, installer, derived]

@Test func smartCleanStartsWithEveryRecommendedItemTicked() {
    let selections = CleanupSelections()
    #expect(selections.smartClean(catalog: catalog, found: scan) { _ in nil }.map(\.ruleID) == ["npm-cache", "app-logs", "xcode-derived-data"])
    #expect([npm, logs, derived].allSatisfy(selections.isInSmartClean))
}

@Test func anUntickedItemIsLeftOutOfTheSmartCleanAndCanBeTickedAgain() {
    var selections = CleanupSelections()
    selections.setSmartClean([logs], included: false)
    #expect(!selections.isInSmartClean(logs))
    #expect(selections.smartClean(catalog: catalog, found: scan) { _ in nil }.map(\.ruleID) == ["npm-cache", "xcode-derived-data"])
    selections.setSmartClean([logs], included: true)
    #expect(selections.smartClean(catalog: catalog, found: scan) { _ in nil }.map(\.ruleID) == ["npm-cache", "app-logs", "xcode-derived-data"])
}

@Test func theSmartCleanRunsTheChecksAtClickTime() {
    let selections = CleanupSelections()
    #expect(selections.smartClean(catalog: catalog, found: scan) { $0.ruleID == "npm-cache" ? .ownerRunning("npm") : nil }.map(\.ruleID) == ["app-logs", "xcode-derived-data"])
}

@Test func buildingOrUntickingASmartCleanNeverChangesTheCleanupPlan() {
    var selections = CleanupSelections()
    selections.plan = [installer.id, npm.id]
    _ = selections.smartClean(catalog: catalog, found: scan) { _ in nil }
    selections.setSmartClean([npm, logs], included: false)
    #expect(selections.plan == [installer.id, npm.id])
}

@Test func choosingInTheCleanupPlanNeverChangesTheSmartClean() {
    var selections = CleanupSelections()
    selections.setSmartClean([logs], included: false)
    selections.plan = [logs.id]
    selections.plan.remove(logs.id)
    #expect(!selections.isInSmartClean(logs))
    #expect(selections.isInSmartClean(npm))
}

@Test func aFinishedRunClearsOnlyTheSelectionItCameFrom() {
    var selections = CleanupSelections()
    selections.plan = [installer.id]
    selections.setSmartClean([logs], included: false)

    selections.finishRun(from: .smartClean)
    #expect(selections.plan == [installer.id])
    #expect(selections.isInSmartClean(logs), "A Smart clean starts again with everything ticked")

    selections.setSmartClean([logs], included: false)
    selections.finishRun(from: .plan)
    #expect(selections.plan.isEmpty)
    #expect(!selections.isInSmartClean(logs))
}

/// Decision 51: leftovers of removed apps are chosen and cleaned on the Applications page, the rest in the Cleanup plan.
private let leftover = item(RemovedAppLeftovers.ruleID, name: "Synth"), related = item(RemovedAppLeftovers.possiblyRelatedRuleID, name: "Gone")

@Test func eachPageReviewsOnlyTheItemsItShows() {
    var selections = CleanupSelections()
    selections.plan = [installer.id, leftover.id, related.id]
    let found = scan + [leftover, related]
    #expect(selections.chosen(on: .plan, from: found).map(\.ruleID) == ["downloads-installers"])
    #expect(selections.chosen(on: .applications, from: found).map(\.ruleID) == [RemovedAppLeftovers.ruleID, RemovedAppLeftovers.possiblyRelatedRuleID])
}

@Test func aFinishedRunFromOnePageKeepsTheOtherPagesChoices() {
    var selections = CleanupSelections()
    selections.plan = [installer.id, leftover.id]
    selections.finishRun(from: .applications)
    #expect(selections.plan == [installer.id])

    selections.plan = [installer.id, leftover.id]
    selections.finishRun(from: .plan)
    #expect(selections.plan == [leftover.id])
}

/// #270: quitting with only leftovers ticked still has choices to lose.
@Test func leftoversTickedOnApplicationsCountAsChoices() {
    var selections = CleanupSelections()
    let found = scan + [leftover]
    #expect(!selections.hasChoices(among: found))
    selections.plan = [leftover.id]
    #expect(selections.hasChoices(among: found))
}

/// #270: starting a new Cleanup plan clears only the plan's choices, never the Applications page's, even right after a
/// run, when nothing is found until the next scan.
@Test func clearingOnePageKeepsTheOtherPagesChoices() {
    var selections = CleanupSelections()
    selections.plan = [installer.id, leftover.id, related.id]
    selections.clear(.plan)
    #expect(selections.plan == [leftover.id, related.id])
    selections.clear(.applications)
    #expect(selections.plan.isEmpty)
}
