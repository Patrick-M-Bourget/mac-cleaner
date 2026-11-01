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
    #expect(CandidateHold.grouped(items.filter { $0.hold != nil }).map(\.hold) == [using, running])
}

// #560, Decision 125: the review sheet shows one line per holder, not one per item. Chrome's real rule, two profiles with
// two cache folders each: one "Google Chrome" line with one Quit link, the skipped size shown once, on that line.
private struct ChromeRunning: RunningAppChecking {
    func isRunning(_ owner: RuleOwner) -> Bool? { owner.name == "Google Chrome" }
}
private func chromeProfiles() throws -> (URL, Catalog, [Candidate]) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropHeldChrome-\(UUID())").resolvingSymlinksInPath()
    for profile in ["Default", "Profile 1"] {
        for folder in ["Cache/Cache_Data/index", "Code Cache/js/index"] {
            let file = home.appendingPathComponent("Library/Caches/Google/Chrome/\(profile)/\(folder)")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4_096).write(to: file)
        }
    }
    let catalog = Catalog(rules: fixtureRules)
    return (home, catalog, catalog.discover(fixture: home))
}

@Test func aBrowsersCachesInEveryProfileShowAsOneLineWithOneQuitLink() throws {
    let (home, catalog, caches) = try chromeProfiles()
    defer { try? FileManager.default.removeItem(at: home) }
    try #require(caches.count == 4)
    let refusals = CandidateCheck(catalog: catalog, running: ChromeRunning(), inUse: FixtureNothingInUse(), home: home).refusals(of: caches)
    let held = ReviewHeldItems(candidates: caches, refusals: refusals, catalog: catalog, isOpen: { $0 == ["com.google.Chrome"] })
    let lines = held.lines(in: caches)
    #expect(lines.count == 1)
    let line = try #require(lines.first)
    #expect(line.text == "Google Chrome is open, so its caches will be skipped")
    #expect(line.items.count == 4)
    #expect(line.quitTitle == "Quit Google Chrome", "The browser holding its caches offers Quit (#560, point 3)")
    #expect(line.size == SizeEstimate(sum: caches.map(SizeEstimate.init)))
    #expect(line.text?.contains("scan again") == false)
}

// Two holders, two lines; a holder that isn't a known app still gets one line for its rows, without Quit; a row refused for
// a reason of its own keeps a line of its own, which the sheet names by its row.
@Test func eachHolderGetsOneLineAndARowSkippedForItsOwnReasonKeepsItsOwn() {
    let items = ["synth-cache", "synth-presets", "npm-cache", "browser-copies"].map(item)
    let other = Candidate(ruleID: "npm-cache", action: .delete, url: fixtureNoHome.appendingPathComponent("npm-2"), resourceID: "2:npm", isDirectory: true,
                          toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 500, allocatedBytes: 500,
                          sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
    let all = [items[0], items[2], items[1], items[3], other]
    let refusals: [String: CheckRefusal] = [items[0].id: .ownerRunning("Synth"), items[1].id: .ownerRunning("Synth"), items[2].id: .ownerRunning("npm"),
                                            items[3].id: .inUse("Browser"), other.id: .changed]
    let held = ReviewHeldItems(candidates: all, refusals: refusals, catalog: catalog, isOpen: open)
    let lines = held.lines(in: all)
    #expect(lines.map(\.text) == ["Synth is open, so its caches will be skipped", "npm is open, so its caches will be skipped",
                                  "Browser is using 1 item, so it will be skipped", nil])
    #expect(lines.map { $0.items.map(\.ruleID) } == [["synth-cache", "synth-presets"], ["npm-cache"], ["browser-copies"], ["npm-cache"]])
    #expect(lines.map(\.quitTitle) == ["Quit Synth", nil, "Quit Browser", nil], "A command-line tool isn't an app")
    #expect(lines.map(\.size) == [.measured(2_000), .measured(1_000), .measured(1_000), .measured(500)])
    #expect(lines.map(\.isUpperBound) == [false, false, true, false], "Copies share disk blocks")
    #expect(lines.last?.refusal == .changed)
    #expect(held.lines(in: [items[0]]).map(\.items.count) == [1], "Only the rows asked about")
}

// #560, Decision 125: an app that quits by any means while the sheet is open (from its own menu, the Dock) has its rows checked
// again, as after the sheet's own Quit. Rows still refused, say by a helper still closing, keep a line with that reason and no
// Quit, and are looked at again; once they pass, the line goes.
@Test func anAppThatQuitsByAnyMeansHasItsRowsCheckedAgain() {
    let items = ["synth-cache", "synth-presets", "browser-copies"].map(item)
    let refusals: [String: CheckRefusal] = [items[0].id: .ownerRunning("Synth"), items[1].id: .ownerRunning("Synth"), items[2].id: .inUse("Browser")]
    var held = ReviewHeldItems(candidates: items, refusals: refusals, catalog: catalog, isOpen: open)
    #expect(held.ownersToCheckAgain(isOpen: open).isEmpty, "Every holder is still open")

    let synthQuit: ([String]) -> Bool = { $0 == ["com.maker.browser"] }
    #expect(held.ownersToCheckAgain(isOpen: synthQuit) == [synth])
    held.quitEnded(synth, outcome: .quit, isOpen: synthQuit) { $0.ruleID == "synth-presets" ? .ownerRunning("Synth") : nil }
    #expect(held.lines(in: items).map(\.text) == ["Synth is open, so its caches will be skipped", "Browser is using 1 item, so it will be skipped"])
    #expect(held.lines(in: items).map { $0.items.map(\.ruleID) } == [["synth-presets"], ["browser-copies"]])
    #expect(held.lines(in: items).map(\.quitTitle) == [nil, "Quit Browser"], "Nothing open to quit")
    #expect(held.ownersToCheckAgain(isOpen: synthQuit) == [synth], "Still held, so looked at again")

    held.quitEnded(synth, outcome: .quit, isOpen: synthQuit) { _ in nil }
    #expect(held.ownersToCheckAgain(isOpen: synthQuit).isEmpty)
    #expect(held.lines(in: items).map(\.text) == ["Browser is using 1 item, so it will be skipped"])
}
