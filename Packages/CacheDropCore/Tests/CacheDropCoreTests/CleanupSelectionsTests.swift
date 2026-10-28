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

/// #310: an item the page listed that the click-time check refuses stays in, so its review says why it will be skipped,
/// as the plan's does. One the page never listed (refused at the scan too), or unticked, stays out.
@Test func aListedItemTheCheckRefusesAtClickTimeStaysInForItsReviewToExplain() {
    var selections = CleanupSelections()
    let refused: (Candidate) -> CheckRefusal? = { $0.ruleID == "npm-cache" || $0.ruleID == "app-logs" ? .ownerRunning("Chrome") : nil }
    #expect(selections.smartClean(catalog: catalog, found: scan, listed: [npm, derived], check: refused).map(\.ruleID) == ["npm-cache", "xcode-derived-data"])
    selections.setSmartClean([npm], included: false)
    #expect(selections.smartClean(catalog: catalog, found: scan, listed: [npm, derived], check: refused).map(\.ruleID) == ["xcode-derived-data"])
}

@Test func buildingOrUntickingASmartCleanNeverChangesTheCleanupPlan() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, npm.id]
    _ = selections.smartClean(catalog: catalog, found: scan) { _ in nil }
    selections.setSmartClean([npm, logs], included: false)
    #expect(selections.ticked == [installer.id, npm.id])
}

@Test func choosingInTheCleanupPlanNeverChangesTheSmartClean() {
    var selections = CleanupSelections()
    selections.setSmartClean([logs], included: false)
    selections.ticked = [logs.id]
    selections.ticked.remove(logs.id)
    #expect(!selections.isInSmartClean(logs))
    #expect(selections.isInSmartClean(npm))
}

@Test func aFinishedRunClearsOnlyTheSelectionItCameFrom() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id]
    selections.setSmartClean([logs], included: false)

    selections.finishRun(from: .smartClean)
    #expect(selections.ticked == [installer.id])
    #expect(selections.isInSmartClean(logs), "A Smart clean starts again with everything ticked")

    selections.setSmartClean([logs], included: false)
    selections.finishRun(from: .plan)
    #expect(selections.ticked.isEmpty)
    #expect(!selections.isInSmartClean(logs))
}

/// Decision 51: leftovers of removed apps are chosen and cleaned on the Applications page, the rest in the Cleanup plan.
private let leftover = item(RemovedAppLeftovers.ruleID, name: "Synth"), related = item(RemovedAppLeftovers.possiblyRelatedRuleID, name: "Gone")

@Test func eachPageReviewsOnlyTheItemsItShows() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id, related.id]
    let found = scan + [leftover, related]
    #expect(selections.chosen(on: .plan, from: found).map(\.ruleID) == ["downloads-installers"])
    #expect(selections.chosen(on: .applications, from: found).map(\.ruleID) == [RemovedAppLeftovers.ruleID, RemovedAppLeftovers.possiblyRelatedRuleID])
}

@Test func aFinishedRunFromOnePageKeepsTheOtherPagesChoices() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id]
    selections.finishRun(from: .applications)
    #expect(selections.ticked == [installer.id])

    selections.ticked = [installer.id, leftover.id]
    selections.finishRun(from: .plan)
    #expect(selections.ticked == [leftover.id])
}

/// #270: quitting with only leftovers ticked still has choices to lose.
@Test func leftoversTickedOnApplicationsCountAsChoices() {
    var selections = CleanupSelections()
    let found = scan + [leftover]
    #expect(!selections.hasChoices(among: found))
    selections.ticked = [leftover.id]
    #expect(selections.hasChoices(among: found))
}

/// #270: starting a new Cleanup plan clears only the plan's choices, never the Applications page's, even right after a
/// run, when nothing is found until the next scan.
@Test func clearingOnePageKeepsTheOtherPagesChoices() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id, related.id]
    selections.clear(.plan)
    #expect(selections.ticked == [leftover.id, related.id])
    selections.clear(.applications)
    #expect(selections.ticked.isEmpty)
}

/// #271: a category row is on the page its rules are on, so the app asks the core instead of checking the category.
@Test func aCategoryRowIsOnThePageOfItsRules() {
    let rows = CatalogOverview(catalog: Catalog(rules: fixtureRules + RemovedAppLeftovers.rules), candidates: scan + [leftover, related]).rows
    #expect(rows.filter { CleanupSelections.Source.page(of: $0) == .applications }.map(\.category) == [.leftovers])
    #expect(rows.filter { CleanupSelections.Source.page(of: $0) == .plan }.count == rows.count - 1)
}

/// Each page's revision (#307, #333).
private func revisions(_ selections: CleanupSelections) -> [UInt64] { CleanupSelections.Source.allCases.map(selections.revision(of:)) }

/// #307: an open review sheet closes only when what it was built from changed, never because a scan ended.
@Test func aScanThatKeepsEveryChoiceLeavesTheRevisionsAlone() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id]
    selections.noteChoices(among: scan + [leftover], smartClean: [npm, logs])
    let before = revisions(selections)
    let dropped = selections.keepOnly(scan + [leftover, related], smartClean: [npm, logs])
    #expect(!dropped, "Nothing chosen was dropped")
    #expect(revisions(selections) == before)
    #expect(selections.ticked == [installer.id, leftover.id])
}

/// #333: a scan that drops one of the plan's choices moves only the plan's revision.
@Test func aScanThatDropsAPlanChoiceMovesOnlyThePlansRevision() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id]
    selections.noteChoices(among: scan + [leftover], smartClean: [npm, logs])
    let smart = selections.revision(of: .smartClean), apps = selections.revision(of: .applications), plan = selections.revision(of: .plan)
    let dropped = selections.keepOnly([npm, logs, derived, leftover], smartClean: [npm, logs])
    #expect(dropped)
    #expect(selections.ticked == [leftover.id])
    #expect(selections.revision(of: .plan) != plan)
    #expect(selections.revision(of: .smartClean) == smart)
    #expect(selections.revision(of: .applications) == apps)
}

/// #333: Applications' choices changing moves only its revision.
@Test func aScanThatDropsAnApplicationsChoiceMovesOnlyItsRevision() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id]
    selections.noteChoices(among: scan + [leftover], smartClean: [npm, logs])
    let smart = selections.revision(of: .smartClean), apps = selections.revision(of: .applications), plan = selections.revision(of: .plan)
    selections.keepOnly(scan, smartClean: [npm, logs])
    #expect(selections.revision(of: .applications) != apps)
    #expect(selections.revision(of: .plan) == plan)
    #expect(selections.revision(of: .smartClean) == smart)
}

/// #333: Smart clean's picks changing (a recheck drops one, or an owner starts running) moves only Smart clean's revision.
@Test func aChangeToSmartCleansPicksMovesOnlyItsRevision() {
    var selections = CleanupSelections()
    selections.ticked = [installer.id, leftover.id]
    selections.noteChoices(among: scan + [leftover], smartClean: [npm, logs])
    let smart = selections.revision(of: .smartClean), apps = selections.revision(of: .applications), plan = selections.revision(of: .plan)
    let dropped = selections.keepOnly(scan + [leftover], smartClean: [npm])
    #expect(!dropped)
    #expect(selections.revision(of: .smartClean) != smart)
    #expect(selections.revision(of: .plan) == plan)
    #expect(selections.revision(of: .applications) == apps)
}

@Test func choosingAnItemMovesItsPagesRevisionAndChoosingNothingNewDoesNot() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, smartClean: [])
    let plan = selections.revision(of: .plan), smart = selections.revision(of: .smartClean)
    selections.ticked.insert(npm.id)
    selections.noteChoices(among: scan, smartClean: [])
    #expect(selections.revision(of: .plan) != plan)
    #expect(selections.revision(of: .smartClean) == smart)
    let chosen = revisions(selections)
    selections.noteChoices(among: scan, smartClean: [])
    #expect(revisions(selections) == chosen)
    selections.revise()
    #expect(zip(revisions(selections), chosen).allSatisfy { $0 != $1 }, "A change to what every review would do, a dry run or a run, moves all three")
}
