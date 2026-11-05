import Foundation
import Testing
@testable import CacheDropCore

// #782, Decision 177: Results' bottom bar leads with Empty from Trash… while a run moved CacheDrop's own items to the Trash
// and they're still there. Nothing here touches disk.

private let catalog = Catalog(rules: fixtureRules)
private func item(_ ruleID: String, _ name: String) -> Candidate {
    Candidate(ruleID: ruleID, action: catalog.rule(ruleID)?.action ?? .delete, url: fixtureNoHome.appendingPathComponent(name), resourceID: "1:" + name,
              isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1_000, allocatedBytes: 1_000,
              sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
}
private func run(_ candidates: [Candidate], _ state: CleanupTargetState = .succeeded, dryRun: Bool = false) -> CatalogExecutionResult {
    let approval = CatalogApproval(candidates: candidates, dryRun: dryRun)
    let records = candidates.map { candidate in
        var record = CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: candidate, dryRun: dryRun)
        record.state = state
        return record
    }
    return CatalogExecutionResult(batchID: approval.id, records: records, dryRun: dryRun, rejectedReplay: false, journalFailure: nil, estimatedBytes: 0)
}
private let download = item("downloads", "Setup.dmg"), npm = item("npm-cache", "npm")

@Test func aRunThatMovedItemsToTheTrashLeadsWithEmptyFromTrashWhileTheyAreStillThere() {
    #expect(run([download, npm]).leadsWithEmptyFromTrash(cacheDropBytesInTrash: 1_000))
}

@Test func onceEmptiedOrNeverReadTheBarIsAsBefore() {
    #expect(!run([download]).leadsWithEmptyFromTrash(cacheDropBytesInTrash: 0), "Emptied, or put back")
    #expect(!run([download]).leadsWithEmptyFromTrash(cacheDropBytesInTrash: nil), "The Trash isn't read yet")
}

@Test func aRunThatMovedNothingToTheTrashNeverLeadsWithEmptyFromTrash() {
    #expect(!run([npm]).leadsWithEmptyFromTrash(cacheDropBytesInTrash: 1_000), "Earlier runs' items are Overview's to offer")
    #expect(!run([download], .failed).leadsWithEmptyFromTrash(cacheDropBytesInTrash: 1_000))
    #expect(!run([download], dryRun: true).leadsWithEmptyFromTrash(cacheDropBytesInTrash: 1_000), "A dry run moved nothing")
}
