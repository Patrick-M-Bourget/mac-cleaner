import Foundation
import Testing
@testable import StillCore

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
