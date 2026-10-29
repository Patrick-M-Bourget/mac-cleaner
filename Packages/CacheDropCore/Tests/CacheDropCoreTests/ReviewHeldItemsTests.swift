import Foundation
import Testing
@testable import CacheDropCore

// #377: the review sheet offers "Quit X" on a row a known app holds. Owners, open apps and checks are fixtures; nothing on
// this Mac is read, asked to quit or changed.

private let synth = RuleOwner(name: "Synth", bundleIDs: ["com.maker.synth"], executables: ["Synth"])
private let browser = RuleOwner(name: "Browser", bundleIDs: ["com.maker.browser"])
private let npm = RuleOwner(name: "npm", executables: ["npm"])
private func rule(_ id: String, owner: RuleOwner?, copies: RuleOwner? = nil) -> CleanupRule {
    CleanupRule(id: id, category: .developer, title: id, detail: "", consequence: "", regen: .cache, action: .delete, locations: [id], owner: owner,
                copies: copies.map { LeakedCopies(owner: $0) })
}
private let catalog = Catalog(rules: [rule("synth-cache", owner: synth), rule("browser-copies", owner: nil, copies: browser), rule("npm-cache", owner: npm),
                                      rule("synth-presets", owner: synth)])
private func item(_ ruleID: String) -> Candidate {
    Candidate(ruleID: ruleID, action: .delete, url: fixtureNoHome.appendingPathComponent(ruleID), resourceID: "1:\(ruleID)", isDirectory: true, toolURL: nil,
              volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1_000, allocatedBytes: 1_000, sizeComplete: true, lastUsed: nil,
              observedAt: Date(), profile: nil)
}
private func open(_ ids: [String]) -> Bool { !Set(ids).isDisjoint(with: ["com.maker.synth", "com.maker.browser"]) }

@Test func aRowHeldByAnOpenKnownAppOffersToQuitItAndNoOtherRowDoes() {
    let items = ["synth-cache", "browser-copies", "npm-cache", "synth-presets"].map(item)
    let refusals: [String: CheckRefusal] = [
        items[0].id: .ownerRunning("Synth"),
        items[1].id: .inUse("Browser"),
        items[2].id: .ownerRunning("npm"),
        items[3].id: .ownerUnknown("Synth"),
    ]
    let held = ReviewHeldItems(candidates: items, refusals: refusals, catalog: catalog, isOpen: open)
    #expect(held.quitTitle(for: items[0]) == "Quit Synth", "Its owner is an open app")
    #expect(held.quitTitle(for: items[1]) == "Quit Browser", "In use by a known app")
    #expect(held.quitTitle(for: items[2]) == nil, "A command-line tool isn't an app")
    #expect(held.quitTitle(for: items[3]) == nil, "Couldn't check: no holder to quit")
    #expect(held.refusals == refusals)

    // An app that is only running as its tools or helpers, not open as an app, has nothing to quit here.
    let closed = ReviewHeldItems(candidates: items, refusals: refusals, catalog: catalog, isOpen: { _ in false })
    #expect(closed.quitTitle(for: items[0]) == nil)
    #expect(closed.quitTitle(for: items[1]) == nil)
    // Someone else holding it ("An Android virtual device", any app) is never a known app.
    let other = ReviewHeldItems(candidates: [items[1]], refusals: [items[1].id: .inUse("Something else")], catalog: catalog, isOpen: { _ in true })
    #expect(other.quitTitle(for: items[1]) == nil)
}

@Test func onceTheAppQuitsItsRowsAreCheckedAgainAndOnesThatPassLeave() {
    let items = ["synth-cache", "synth-presets", "browser-copies"].map(item)
    let refusals: [String: CheckRefusal] = [items[0].id: .ownerRunning("Synth"), items[1].id: .ownerRunning("Synth"), items[2].id: .inUse("Browser")]
    var held = ReviewHeldItems(candidates: items, refusals: refusals, catalog: catalog, isOpen: open)
    #expect(held.candidates(heldBy: synth).map(\.ruleID) == ["synth-cache", "synth-presets"])

    var checked: [String] = []
    held.quitEnded(synth, outcome: .quit, isOpen: { _ in false }) { candidate in
        checked.append(candidate.ruleID)
        // The preset folder changed meanwhile: it keeps a reason, the new one, and no Quit.
        return candidate.ruleID == "synth-presets" ? .changed : nil
    }
    #expect(checked == ["synth-cache", "synth-presets"], "Only the quit app's rows are checked again")
    #expect(held.refusals == [items[1].id: .changed, items[2].id: .inUse("Browser")])
    #expect(held.quitTitle(for: items[0]) == nil)
    #expect(held.quitTitle(for: items[1]) == nil)
    #expect(held.quitTitle(for: items[2]) == "Quit Browser", "Another app's row is untouched")
}

@Test func anAppThatDoesntQuitLeavesItsRowsAsTheyWere() {
    let items = [item("synth-cache")]
    let refusals: [String: CheckRefusal] = [items[0].id: .ownerRunning("Synth")]
    for outcome in [AppQuitOutcome.stillOpen, .notAnApp] {
        var held = ReviewHeldItems(candidates: items, refusals: refusals, catalog: catalog, isOpen: open)
        var checked = 0
        held.quitEnded(synth, outcome: outcome, isOpen: open) { _ in checked += 1; return nil }
        #expect(checked == 0)
        #expect(held.refusals == refusals)
        #expect(held.quitTitle(for: items[0]) == "Quit Synth", "It can be asked again, after saving")
    }
}

// #384, Decision 79: one rule says whether a refusal is a hold and which known app holds it, for Smart clean's held lines
// (`RecommendedPlan`) and the review's Quit links alike.
@Test func oneRuleSaysWhichKnownAppARefusalNamesAsTheHolder() {
    let synthCache = item("synth-cache"), copies = item("browser-copies")
    #expect(CandidateHold(.ownerRunning("Synth"), of: synthCache, catalog: catalog) == CandidateHold(.ownerRunning("Synth"), app: synth))
    #expect(CandidateHold(.inUse("Browser"), of: copies, catalog: catalog) == CandidateHold(.inUse("Browser"), app: browser))
    // A holder the item's owners don't name is still a hold, but no known app's.
    #expect(CandidateHold(.inUse("An Android virtual device"), of: copies, catalog: catalog) == CandidateHold(.inUse("An Android virtual device")))
    #expect(CandidateHold(.ownerRunning("This simulator"), of: synthCache, catalog: catalog) == CandidateHold(.ownerRunning("This simulator")))
    // Any other refusal isn't a hold.
    #expect(CandidateHold(.ownerUnknown("Synth"), of: synthCache, catalog: catalog) == nil)
    #expect(CandidateHold(.excluded, of: synthCache, catalog: catalog) == nil)

    // Smart clean reads the same rule.
    let plan = RecommendedPlan(catalog: catalog, candidates: [synthCache, copies], now: Date()) {
        $0.ruleID == "synth-cache" ? .ownerRunning("Synth") : .inUse("An Android virtual device")
    }
    #expect(plan.held.map(\.hold) == [CandidateHold(.ownerRunning("Synth"), app: synth), CandidateHold(.inUse("An Android virtual device"))])
}

// #384: two apps can share a display name (Synth and another maker's Synth). Each holds only its own rows, and quitting
// one checks only its rows again.
@Test func ownersSharingANameHoldOnlyTheirOwnRows() {
    let other = RuleOwner(name: "Synth", bundleIDs: ["com.other.synth"])
    let catalog = Catalog(rules: [rule("synth-cache", owner: synth), rule("other-cache", owner: other)])
    let items = [item("synth-cache"), item("other-cache")]
    let refusals: [String: CheckRefusal] = [items[0].id: .ownerRunning("Synth"), items[1].id: .ownerRunning("Synth")]
    var held = ReviewHeldItems(candidates: items, refusals: refusals, catalog: catalog, isOpen: { _ in true })
    #expect(held.candidates(heldBy: synth).map(\.ruleID) == ["synth-cache"])
    #expect(held.candidates(heldBy: other).map(\.ruleID) == ["other-cache"])

    var checked: [String] = []
    held.quitEnded(other, outcome: .quit, isOpen: { _ in true }) { checked.append($0.ruleID); return nil }
    #expect(checked == ["other-cache"])
    #expect(held.refusals == [items[0].id: .ownerRunning("Synth")])
}

// #384: Smart clean gives held items a line per hold. Holds are told apart by what they are, not by their line's text: an
// owner running and the same app using a copy both read "In use by Synth · Quit Synth to clean it". Free items come first,
// then each hold in the order the scan found it.
@Test func heldItemsAreGroupedByTheirHoldNotItsWording() {
    func held(_ ruleID: String, _ hold: CandidateHold?) -> Candidate { var found = item(ruleID); found.hold = hold; return found }
    let running = CandidateHold(.ownerRunning("Synth"), app: synth), using = CandidateHold(.inUse("Synth"), app: synth)
    #expect(running.line == using.line)
    let items = [held("synth-cache", using), held("browser-copies", nil), held("npm-cache", running), held("synth-presets", using)]
    let groups = CandidateHold.grouped(items)
    #expect(groups.map(\.hold) == [nil, using, running])
    #expect(groups.map { $0.items.map(\.ruleID) } == [["browser-copies"], ["synth-cache", "synth-presets"], ["npm-cache"]])
}
