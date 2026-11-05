import Foundation
import Testing
@testable import CacheDropCore

// #779: Smart clean's one-screen summary, "Free up X" over its rows and "Clean up X" in the bottom bar. Nothing here touches disk.

private let catalog = Catalog(rules: fixtureRules)
private func item(_ ruleID: String, bytes: Int64 = 1_000_000_000) -> Candidate {
    let action = catalog.rule(ruleID)?.action ?? .delete
    return Candidate(ruleID: ruleID, action: action, url: fixtureNoHome.appendingPathComponent(ruleID + "-\(bytes)"), resourceID: "1:\(ruleID)\(bytes)",
                     isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: bytes,
                     allocatedBytes: bytes, sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
}

@Test func freeUpIsWhatTheTickedItemsReleaseNeverWhatGoesToTheTrash() {
    let npm = item("npm-cache", bytes: 2_000_000_000), download = item("downloads", bytes: 5_000_000_000)
    let summary = SmartCleanSummary(ticked: [npm, download], catalog: catalog)
    #expect(summary.freeUp == SizeEstimate(npm).text(upperBound: false))
    #expect(summary.itemCount == 2)
    #expect(summary.cleanUpTitle == "Clean up " + SizeEstimate(npm).text(upperBound: false))
}

@Test func copiesThatShareDiskBlocksMakeFreeUpAnUpperBound() {
    let summary = SmartCleanSummary(ticked: [item("npm-cache"), item("chrome-code-sign-clones")], catalog: catalog)
    #expect(summary.freeUp?.hasPrefix("Up to ") == true)
    #expect(summary.cleanUpTitle == "Clean up " + (summary.freeUp ?? ""))
}

@Test func whenNothingTickedReleasesSpaceThereIsNoFigureAndTheButtonIsPlain() {
    let onlyTrash = SmartCleanSummary(ticked: [item("downloads")], catalog: catalog)
    #expect(onlyTrash.freeUp == nil)
    #expect(onlyTrash.itemCount == 1)
    #expect(onlyTrash.cleanUpTitle == "Clean up")

    let nothing = SmartCleanSummary(ticked: [], catalog: catalog)
    #expect(nothing.freeUp == nil)
    #expect(nothing.itemCount == 0)
    #expect(nothing.cleanUpTitle == "Clean up")
}

@Test func theCaptionNamesWhatIsLeftOutAndWhereToAdjust() {
    #expect(SmartCleanSummary.title == "Free up")
    #expect(SmartCleanSummary.notIncluded == "Not included: newer downloads, models, iCloud copies")
    #expect(SmartCleanSummary.adjust == "Adjust in Cleanup plan")
}
