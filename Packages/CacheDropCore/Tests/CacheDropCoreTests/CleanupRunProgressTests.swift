import Foundation
import Testing
@testable import CacheDropCore

/// An item a rule found, as the scan would offer it. Nothing here touches disk.
private func item(_ ruleID: String, _ name: String, bytes: Int64) -> Candidate {
    let rule = Catalog(rules: fixtureRules).rule(ruleID)
    return Candidate(ruleID: ruleID, action: rule?.action ?? .delete, url: fixtureNoHome.appendingPathComponent(name), resourceID: "1:" + name,
                     isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: bytes, allocatedBytes: bytes,
                     sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
}
private let catalog = Catalog(rules: fixtureRules)
private let GB: Int64 = 1_000_000_000
private let npm = item("npm-cache", "npm", bytes: 3 * GB), logs = item("app-logs", "logs", bytes: 1 * GB)
private let derived = item("xcode-derived-data", "derived", bytes: 12 * GB), installer = item("downloads-installers", "Setup.dmg", bytes: 4 * GB)
private let approval = CatalogApproval(candidates: [npm, derived, logs, installer], previewOnly: false)

/// The run's record for `candidate`, ended in `state`.
private func record(_ candidate: Candidate, _ state: CleanupTargetState) -> CleanupRecord {
    var record = CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: candidate, previewOnly: false)
    record.state = state
    return record
}

/// #355: before anything finishes, every category waits but the first, which is being cleaned, and nothing is freed.
@Test func aRunStartsWithItsFirstCategoryCleaningAndNothingFreed() {
    let progress = CleanupRunProgress(approval: approval, catalog: catalog, records: [])
    #expect(progress.categories.map(\.category) == [.developer, .logs, .downloads])
    #expect(progress.categories.map(\.state) == [.cleaning, .waiting, .waiting])
    #expect(progress.categories.map(\.total) == [2, 1, 1])
    #expect(progress.releasedBytes == 0)
    #expect(progress.finished == 0 && progress.total == 4)
}

/// #355: each finished item ticks its category off and adds what it released; a Trash-bound one adds to the Trash instead.
@Test func finishedItemsTickTheirCategoryOffAndCountWhatTheyReleased() {
    let progress = CleanupRunProgress(approval: approval, catalog: catalog, records: [
        record(npm, .succeeded), record(derived, .skipped), record(logs, .succeeded), record(installer, .succeeded),
    ])
    #expect(progress.categories.map(\.state) == [.done, .done, .done])
    #expect(progress.categories.map(\.finished) == [2, 1, 1])
    #expect(progress.categories.map(\.skipped) == [1, 0, 0])
    #expect(progress.releasedBytes == 4 * GB, "npm and logs; DerivedData was skipped")
    #expect(progress.movedToTrashBytes == 4 * GB)
}

/// #355: the bar shaves at its tip. What is still to go stays in its category; what went to the Trash turns grey there,
/// and the used space shrinks by what was released.
@Test func theBarKeepsWhatIsLeftAtTheTipAndWhatWentToTheTrashInGrey() throws {
    let progress = CleanupRunProgress(approval: approval, catalog: catalog, records: [record(npm, .succeeded), record(installer, .succeeded)])
    #expect(progress.categories.map(\.state) == [.cleaning, .waiting, .done])
    let bar = try #require(progress.breakdown(usedAtStart: 400 * GB, total: 1000 * GB, trash: .empty))
    #expect(bar.used == 397 * GB)
    #expect(bar.segments.map(\.part) == [.category(.developer), .category(.logs), .goingToTrash])
    #expect(bar.segments.map(\.bytes) == [12 * GB, 1 * GB, 4 * GB])
}

/// #355: in a dry run nothing is released, but what would be is counted, so the screen reads the same.
@Test func aDryRunCountsWhatItWouldRelease() {
    let dry = CatalogApproval(candidates: [npm], previewOnly: true)
    var would = CleanupRecord(batchID: dry.id, approvedAt: dry.approvedAt, candidate: npm, previewOnly: true)
    would.state = .skipped; would.message = "Dry run: would delete (3 GB). Checks passed; nothing changed."
    let progress = CleanupRunProgress(approval: dry, catalog: catalog, records: [would])
    #expect(progress.releasedBytes == 3 * GB)
    #expect(progress.categories.first?.skipped == 0)
}

/// #355 review: a dry run releases nothing, so its bar stays where it was; only the count says what would be freed.
@Test func aDryRunsBarStaysStill() throws {
    let dry = CatalogApproval(candidates: [npm], previewOnly: true)
    var would = CleanupRecord(batchID: dry.id, approvedAt: dry.approvedAt, candidate: npm, previewOnly: true)
    would.state = .skipped; would.message = "Dry run: would delete (3 GB). Checks passed; nothing changed."
    let progress = CleanupRunProgress(approval: dry, catalog: catalog, records: [would])
    let bar = try #require(progress.breakdown(usedAtStart: 400 * GB, total: 1000 * GB, trash: .empty, releasing: false))
    #expect(bar.used == 400 * GB)
}

/// #355 review: items a stop left untouched read as not started, not as skipped.
@Test func aStoppedRunsUntouchedItemsAreNotStartedNotSkipped() {
    let progress = CleanupRunProgress(approval: approval, catalog: catalog, records: [
        record(npm, .succeeded), record(derived, .cancelled), record(logs, .cancelled), record(installer, .failed),
    ])
    #expect(progress.categories.map(\.notStarted) == [1, 1, 0])
    #expect(progress.categories.map(\.skipped) == [0, 0, 1])
}
