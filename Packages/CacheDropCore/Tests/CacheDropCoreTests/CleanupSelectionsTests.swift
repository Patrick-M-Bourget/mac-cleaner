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
/// What `RecommendedPlan` takes from `scan`: everything but the new installer.
private let recommended = [npm, logs, derived]

/// #349: one selection; recommended items start ticked on every page, and the rest unticked.
@Test func recommendedItemsArriveTickedOnEveryPage() {
    var selections = CleanupSelections()
    selections.keepOnly(scan, recommended: recommended)
    #expect(selections.chosen(on: .plan, from: scan).map(\.ruleID) == ["npm-cache", "app-logs", "xcode-derived-data"])
    #expect(!selections.isTicked(installer))
}

@Test func smartCleanStartsWithEveryRecommendedItemTicked() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    #expect(selections.smartClean(catalog: catalog, found: scan) { _ in nil }.map(\.ruleID) == ["npm-cache", "app-logs", "xcode-derived-data"])
    #expect(recommended.allSatisfy(selections.isTicked))
}

/// #349: one selection, so an untick on Smart clean shows in the plan, and a tick in the plan on Smart clean.
@Test func anUntickOnOnePageShowsOnEveryPage() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    selections.set([logs], ticked: false)
    #expect(selections.smartClean(catalog: catalog, found: scan) { _ in nil }.map(\.ruleID) == ["npm-cache", "xcode-derived-data"])
    #expect(selections.chosen(on: .plan, from: scan).map(\.ruleID) == ["npm-cache", "xcode-derived-data"])
    selections.set([logs, installer], ticked: true)
    #expect(selections.smartClean(catalog: catalog, found: scan) { _ in nil }.map(\.ruleID) == ["npm-cache", "app-logs", "xcode-derived-data"])
    #expect(selections.chosen(on: .plan, from: scan).count == 4, "The plan adds to Smart clean's ticks")
}

/// #349: a rescan keeps every untick, and a recommended item found for the first time arrives ticked.
@Test func untickingSurvivesARescanAndNewRecommendedItemsArriveTicked() {
    var selections = CleanupSelections()
    selections.keepOnly([npm, logs, installer], recommended: [npm, logs])
    selections.set([logs], ticked: false)
    selections.keepOnly(scan, recommended: recommended)
    #expect(!selections.isTicked(logs))
    #expect(selections.isTicked(derived), "Found for the first time")
    #expect(!selections.isTicked(installer), "Never recommended, never ticked for you")
}

@Test func theSmartCleanRunsTheChecksAtClickTime() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    #expect(selections.smartClean(catalog: catalog, found: scan) { $0.ruleID == "npm-cache" ? .ownerRunning("npm") : nil }.map(\.ruleID) == ["app-logs", "xcode-derived-data"])
}

/// #310: an item the page listed that the click-time check refuses stays in, so its review says why it will be skipped,
/// as the plan's does. One the page never listed (refused at the scan too), or unticked, stays out.
@Test func aListedItemTheCheckRefusesAtClickTimeStaysInForItsReviewToExplain() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    let refused: (Candidate) -> CheckRefusal? = { $0.ruleID == "npm-cache" || $0.ruleID == "app-logs" ? .ownerRunning("Chrome") : nil }
    #expect(selections.smartClean(catalog: catalog, found: scan, listed: [npm, derived], check: refused).map(\.ruleID) == ["npm-cache", "xcode-derived-data"])
    selections.set([npm], ticked: false)
    #expect(selections.smartClean(catalog: catalog, found: scan, listed: [npm, derived], check: refused).map(\.ruleID) == ["xcode-derived-data"])
}

/// #349: Smart clean's run takes only its ticked recommended items; the plan's own ticks stay for the plan.
@Test func smartCleansRunKeepsThePlansOtherTicks() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    selections.set([installer], ticked: true)
    selections.set([logs], ticked: false)
    let run = selections.smartClean(catalog: catalog, found: scan) { _ in nil }
    #expect(run.map(\.ruleID) == ["npm-cache", "xcode-derived-data"])
    selections.finishRun(cleaned: run.map(\.id))
    #expect(selections.ticked == [installer.id])
    selections.keepOnly([logs, installer], recommended: [logs])
    #expect(!selections.isTicked(logs), "Its untick outlives another page's run")
}

/// #349: what a run cleaned leaves every page, what it skipped keeps its tick, and a cleaned item found again that is
/// still recommended comes back ticked.
@Test func aFinishedRunClearsWhatItTookFromEveryPage() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    selections.set([installer], ticked: true)
    selections.finishRun(cleaned: [npm, logs, derived].map(\.id))
    #expect(selections.ticked == [installer.id], "The installer was skipped, so it keeps its tick")
    selections.finishRun(cleaned: [installer.id])
    #expect(selections.ticked.isEmpty)
    selections.keepOnly([npm], recommended: [npm])
    #expect(selections.isTicked(npm), "Found again and still recommended")
}

/// #349: an item ticked as recommended stays the default when its owner starts running and it leaves the recommended
/// plan: Overview never says "Selected" and quitting never warns for it, and a scan that no longer finds it says nothing.
@Test func anItemTickedForYouStaysTheDefaultWhenItLeavesTheRecommendedPlan() {
    var selections = CleanupSelections()
    selections.keepOnly(scan, recommended: recommended)
    selections.keepOnly(scan, recommended: [npm, derived])
    #expect(selections.isTicked(logs))
    #expect(!selections.differsFromRecommended(scan))
    let droppedForYou = selections.keepOnly([npm, installer, derived], recommended: [npm, derived])
    #expect(!droppedForYou, "Only an item the user ticked is worth a message")
    selections.set([installer], ticked: true)
    let droppedYours = selections.keepOnly([npm, derived], recommended: [npm, derived])
    #expect(droppedYours)
}

/// #349: Overview's "Selected" and the quit warning (#270) show only once the ticks differ from the recommended default.
@Test func ticksDifferFromTheRecommendedDefaultOnlyOnceTheUserChangesThem() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    #expect(!selections.differsFromRecommended(scan))
    selections.set([installer], ticked: true)
    #expect(selections.differsFromRecommended(scan))
    #expect(!selections.differsFromRecommended([npm, logs]), "Only the category that changed")
    selections.set([installer], ticked: false)
    selections.set([logs], ticked: false)
    #expect(selections.differsFromRecommended([logs]))
}

/// Decision 51: files from deleted apps are chosen and cleaned on the Applications page, the rest in the Cleanup plan.
private let leftover = item(RemovedAppLeftovers.ruleID, name: "Synth"), related = item(RemovedAppLeftovers.possiblyRelatedRuleID, name: "Gone")

@Test func eachPageReviewsOnlyTheItemsItShows() {
    var selections = CleanupSelections()
    selections.set([installer, leftover, related], ticked: true)
    let found = scan + [leftover, related]
    #expect(selections.chosen(on: .plan, from: found).map(\.ruleID) == ["downloads-installers"])
    #expect(selections.chosen(on: .applications, from: found).map(\.ruleID) == [RemovedAppLeftovers.ruleID, RemovedAppLeftovers.possiblyRelatedRuleID])
}

/// #349: a leftover tied to its removed app is in Smart clean, ticked, and its tick is the Applications page's too.
@Test func aLeftoverInSmartCleanSharesItsTickWithApplications() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan + [leftover], recommended: recommended + [leftover])
    #expect(selections.chosen(on: .applications, from: scan + [leftover]) == [leftover])
    selections.set([leftover], ticked: false)
    #expect(selections.chosen(on: .applications, from: scan + [leftover]).isEmpty)
}

/// #270: quitting with only leftovers ticked still has choices to lose.
@Test func leftoversTickedOnApplicationsCountAsChoices() {
    var selections = CleanupSelections()
    let found = scan + [leftover]
    #expect(!selections.differsFromRecommended(found))
    selections.set([leftover], ticked: true)
    #expect(selections.differsFromRecommended(found))
}

/// #270: starting a new Cleanup plan starts only the plan over, never the Applications page, even right after a run,
/// when nothing is found until the next scan. The plan comes back to the recommended default.
@Test func clearingOnePageKeepsTheOtherPagesChoices() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: recommended)
    selections.set([logs], ticked: false)
    selections.set([installer, leftover, related], ticked: true)
    selections.clear(.plan)
    #expect(selections.ticked == [leftover.id, related.id])
    selections.noteChoices(among: scan, recommended: recommended)
    #expect(selections.isTicked(logs), "The plan's unticks went with it")
    selections.clear(.applications)
    #expect(selections.ticked == Set(recommended.map(\.id)))
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
    selections.set([installer, leftover], ticked: true)
    selections.noteChoices(among: scan + [leftover], recommended: [npm, logs])
    let before = revisions(selections)
    let dropped = selections.keepOnly(scan + [leftover, related], recommended: [npm, logs])
    #expect(!dropped, "Nothing chosen was dropped")
    #expect(revisions(selections) == before)
    #expect(selections.ticked == [installer.id, leftover.id, npm.id, logs.id])
}

/// #333: a scan that drops one of the plan's choices moves only the plan's revision.
@Test func aScanThatDropsAPlanChoiceMovesOnlyThePlansRevision() {
    var selections = CleanupSelections()
    selections.set([installer, leftover], ticked: true)
    selections.noteChoices(among: scan + [leftover], recommended: [npm, logs])
    let smart = selections.revision(of: .smartClean), apps = selections.revision(of: .applications), plan = selections.revision(of: .plan)
    let dropped = selections.keepOnly([npm, logs, derived, leftover], recommended: [npm, logs])
    #expect(dropped)
    #expect(selections.ticked == [leftover.id, npm.id, logs.id])
    #expect(selections.revision(of: .plan) != plan)
    #expect(selections.revision(of: .smartClean) == smart)
    #expect(selections.revision(of: .applications) == apps)
}

/// #333: Applications' choices changing moves only its revision.
@Test func aScanThatDropsAnApplicationsChoiceMovesOnlyItsRevision() {
    var selections = CleanupSelections()
    selections.set([installer, leftover], ticked: true)
    selections.noteChoices(among: scan + [leftover], recommended: [npm, logs])
    let smart = selections.revision(of: .smartClean), apps = selections.revision(of: .applications), plan = selections.revision(of: .plan)
    selections.keepOnly(scan, recommended: [npm, logs])
    #expect(selections.revision(of: .applications) != apps)
    #expect(selections.revision(of: .plan) == plan)
    #expect(selections.revision(of: .smartClean) == smart)
}

/// #333: Smart clean's picks changing (a recheck drops one, or an owner starts running) moves only Smart clean's revision.
@Test func aChangeToSmartCleansPicksMovesOnlyItsRevision() {
    var selections = CleanupSelections()
    selections.set([installer, leftover], ticked: true)
    selections.noteChoices(among: scan + [leftover], recommended: [npm, logs])
    let smart = selections.revision(of: .smartClean), apps = selections.revision(of: .applications), plan = selections.revision(of: .plan)
    let dropped = selections.keepOnly(scan + [leftover], recommended: [npm])
    #expect(!dropped)
    #expect(selections.revision(of: .smartClean) != smart)
    #expect(selections.revision(of: .plan) == plan)
    #expect(selections.revision(of: .applications) == apps)
}

@Test func choosingAnItemMovesItsPagesRevisionAndChoosingNothingNewDoesNot() {
    var selections = CleanupSelections()
    selections.noteChoices(among: scan, recommended: [])
    let plan = selections.revision(of: .plan), smart = selections.revision(of: .smartClean)
    selections.set([npm], ticked: true)
    selections.noteChoices(among: scan, recommended: [])
    #expect(selections.revision(of: .plan) != plan)
    #expect(selections.revision(of: .smartClean) == smart)
    let chosen = revisions(selections)
    selections.noteChoices(among: scan, recommended: [])
    #expect(revisions(selections) == chosen)
    selections.revise()
    #expect(zip(revisions(selections), chosen).allSatisfy { $0 != $1 }, "A change to what every review would do, a dry run or a run, moves all three")
}

/// #374: an item held at the scan is never ticked for you, an item ticked for you that becomes held is unticked, and it
/// arrives ticked again once free. Ticked by hand, a held item stays ticked, and Smart clean takes it for the checks to decide.
@Test func aHeldItemIsNeverTickedByDefaultButATickTakesIt() {
    var copy = item("chrome-code-sign-clones", name: "copy")
    copy.hold = CandidateHold(.inUse("Google Chrome"))
    let found = scan + [copy]
    var selections = CleanupSelections()
    selections.keepOnly(found, recommended: recommended, held: [copy])
    #expect(!selections.isTicked(copy))
    #expect(!selections.differsFromRecommended(found))

    // npm starts running: held now, so its tick for you goes; once it quits, it is ticked again.
    selections.noteChoices(among: found, recommended: [logs, derived], held: [copy, npm])
    #expect(!selections.isTicked(npm))
    #expect(!selections.differsFromRecommended(found))
    selections.noteChoices(among: found, recommended: recommended, held: [copy])
    #expect(selections.isTicked(npm))

    // Ticked by hand: kept ticked while held, and Smart clean takes it; the check at Clean up skips it if still in use.
    selections.set([copy], ticked: true)
    selections.noteChoices(among: found, recommended: recommended, held: [copy])
    #expect(selections.isTicked(copy))
    #expect(selections.smartClean(catalog: catalog, found: found, listed: [copy]) { $0.id == copy.id ? .inUse("Google Chrome") : nil }.map(\.ruleID)
            == ["npm-cache", "app-logs", "xcode-derived-data", "chrome-code-sign-clones"])
}
