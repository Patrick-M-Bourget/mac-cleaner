import Foundation
import Testing
@testable import CacheDropCore

// #780, Decision 178: Smart clean's Worth a look holds the files from deleted apps that `RecommendedPlan` doesn't take,
// never ticked for you; the ones it takes stay ticked in their own category row. Nothing here touches disk.

private let catalog = Catalog(rules: fixtureRules)
private func item(_ ruleID: String, _ name: String, tie: LeftoverTie? = nil) -> Candidate {
    var found = Candidate(ruleID: ruleID, action: catalog.rule(ruleID)?.action ?? .delete, url: fixtureNoHome.appendingPathComponent(name), resourceID: "1:" + name,
                          isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1_000, allocatedBytes: 1_000,
                          sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
    found.leftover = tie
    return found
}
private let npm = item("npm-cache", "npm")
/// Tied to its removed app by an installer receipt: recommended (Decision 64).
private let tied = item(RemovedAppLeftovers.ruleID, "FooData", tie: LeftoverTie(app: "Foo", bundleID: nil, vendor: "com.foocorp", evidence: .receipt("com.foocorp.foo.pkg")))
/// Named like a removed app only: possibly related, never recommended (Decision 49).
private let related = item(RemovedAppLeftovers.possiblyRelatedRuleID, "Gone", tie: LeftoverTie(app: "Gone", bundleID: "com.gone.app", vendor: "com.gone", evidence: .nameOnly("Named like Gone")))
private let found = [npm, tied, related]
private let plan = RecommendedPlan(catalog: catalog, candidates: found) { _ in nil }

@Test func recommendedLeftoversStayInTheirRowAndTheRestGoToWorthALookNeverBoth() {
    #expect(plan.candidates.map(\.id).contains(tied.id), "Receipt-tied: ticked in Files from deleted apps")
    #expect(WorthALook.candidates(in: found, plan: plan) == [related])
    let suggested = Set(WorthALook.candidates(in: found, plan: plan).map(\.id))
    #expect(suggested.isDisjoint(with: (plan.candidates + plan.held).map(\.id)), "Nothing is shown twice")
}

@Test func worthALookShowsOnlyWhenItFoundSomething() {
    #expect(WorthALook.title == "Worth a look")
    let rows = WorthALook.rows(WorthALook.candidates(in: found, plan: plan), catalog: catalog)
    #expect(rows.map(\.category) == [.leftovers])
    #expect(rows.first?.itemCount == 1)
    let none = [npm, tied]
    #expect(WorthALook.rows(WorthALook.candidates(in: none, plan: RecommendedPlan(catalog: catalog, candidates: none) { _ in nil }), catalog: catalog).isEmpty)
}

@Test func worthALookStartsUntickedAndCountsInSmartCleanOnlyOnceTicked() {
    var selections = CleanupSelections()
    selections.noteChoices(among: found, recommended: plan.candidates)
    #expect(selections.isTicked(tied) && !selections.isTicked(related))
    #expect(selections.smartClean(catalog: catalog, found: found) { _ in nil }.map(\.id) == [npm.id, tied.id])
    let revision = selections.revision(of: .smartClean)

    selections.set([related], ticked: true)
    selections.noteChoices(among: found, recommended: plan.candidates)
    #expect(selections.smartClean(catalog: catalog, found: found) { _ in nil }.map(\.id) == [npm.id, tied.id, related.id])
    #expect(selections.chosen(on: .applications, from: found) == [tied, related], "One selection with Applications")
    #expect(selections.revision(of: .smartClean) != revision, "An open review sheet knows")
}
