import Foundation
import Testing
@testable import CacheDropCore

private let GB: Int64 = 1_000_000_000
private let license = License(id: UUID(), edition: .standard, macs: 3, issued: Date(timeIntervalSince1970: 0))

/// #595, Decision 137: with gating on, Clean up is free until it has freed 2 GB (SizeFormatter's decimal GB); an active
/// license is never gated, and a key that isn't valid or is revoked counts as no license.
@Test func theTrialAppliesWhileNoKeyIsActiveAndAnActiveLicenseIsNeverGated() {
    #expect(Trial.freeBytes == 2_000_000_000)
    #expect(CleanupAllowance(gating: true, license: .none, used: 0) == .trial(left: 2 * GB))
    #expect(CleanupAllowance(gating: true, license: .invalid, used: GB / 2) == .trial(left: 3 * GB / 2))
    #expect(CleanupAllowance(gating: true, license: .revoked(license), used: 3 * GB) == .trial(left: 0), "Never below zero")
    #expect(CleanupAllowance(gating: true, license: .active(license), used: 3 * GB) == .unlimited)
}

/// With the build setting off nothing is gated, whatever the license and count say.
@Test func withGatingOffEveryCleanupIsAllowed() {
    let allowance = CleanupAllowance(gating: false, license: .none, used: 5 * GB)
    #expect(allowance == .unlimited)
    #expect(allowance.permits(50 * GB, dryRun: false))
}

/// A plan bigger than what's left never runs; one that fits does, and a dry run is never blocked.
@Test func aPlanBiggerThanWhatsLeftIsRefusedButADryRunNeverIs() {
    let allowance = CleanupAllowance.trial(left: GB)
    #expect(allowance.permits(GB, dryRun: false), "Exactly what's left fits")
    #expect(!allowance.permits(GB + 1, dryRun: false))
    #expect(allowance.permits(5 * GB, dryRun: true))
    #expect(CleanupAllowance.trial(left: 0).permits(0, dryRun: false), "Nothing to free uses nothing")
    #expect(CleanupAllowance.unlimited.permits(500 * GB, dryRun: false))
}

private let catalog = Catalog(rules: fixtureRules)
private func item(_ ruleID: String, _ name: String, bytes: Int64, resource: String? = nil) -> Candidate {
    let rule = catalog.rule(ruleID)
    return Candidate(ruleID: ruleID, action: rule?.action ?? .delete, url: fixtureNoHome.appendingPathComponent(name), resourceID: "1:" + (resource ?? name),
                     isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: bytes, allocatedBytes: bytes,
                     sizeComplete: true, lastUsed: nil, observedAt: Date(), profile: nil)
}
private let npm = item("npm-cache", "npm", bytes: 3 * GB), logs = item("app-logs", "logs", bytes: GB)
private let installer = item("downloads", "Setup.dmg", bytes: 4 * GB)

/// The plan's size against the trial is what Clean up will act on: items the review says will be skipped don't count,
/// Trash moves do, and space offered twice counts once.
@Test func aPlanCountsWhatItWillCleanOnceAndLeavesOutSkippedItems() {
    let again = item("npm-cache", "npm again", bytes: 3 * GB, resource: "npm")
    let approval = CatalogApproval(candidates: [npm, logs, installer, again], dryRun: false)
    #expect(approval.trialBytes(skipping: [], catalog: catalog) == 8 * GB)
    #expect(approval.trialBytes(skipping: [logs.id], catalog: catalog) == 7 * GB)
}

/// The trial counts the reported sizes of items actually removed or moved to the Trash; failed, skipped and stopped items
/// don't count, and a dry run counts nothing.
@Test func aRunCountsOnlyWhatItRemovedOrMovedToTheTrash() {
    let approval = CatalogApproval(candidates: [npm, logs, installer], dryRun: false)
    func record(_ candidate: Candidate, _ state: CleanupTargetState, dryRun: Bool = false) -> CleanupRecord {
        var record = CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: candidate, dryRun: dryRun)
        record.state = state
        return record
    }
    let run = CatalogExecutionResult(batchID: approval.id, records: [record(npm, .failed), record(logs, .succeeded), record(installer, .succeeded)],
                                     dryRun: false, rejectedReplay: false, journalFailure: nil, estimatedBytes: 8 * GB)
    #expect(run.trialBytes(of: approval, catalog: catalog) == 5 * GB)
    let stopped = CatalogExecutionResult(batchID: approval.id, records: [record(npm, .skipped), record(logs, .cancelled), record(installer, .unknown)],
                                         dryRun: false, rejectedReplay: false, journalFailure: nil, estimatedBytes: 8 * GB)
    #expect(stopped.trialBytes(of: approval, catalog: catalog) == 0)
    let dry = CatalogExecutionResult(batchID: approval.id, records: [record(npm, .succeeded, dryRun: true)],
                                     dryRun: true, rejectedReplay: false, journalFailure: nil, estimatedBytes: 3 * GB)
    #expect(dry.trialBytes(of: approval, catalog: catalog) == 0)
}

/// Stands in for the Keychain: Core tests never touch the real one.
@MainActor final class MemoryTrialStore: TrialStore {
    var used: Int64?
    var reads = 0, writes = 0
    var failReads = false, failWrites = false
    init(_ used: Int64? = nil) { self.used = used }
    func read() throws -> Int64? { reads += 1; if failReads { throw CocoaError(.fileReadNoPermission) }; return used }
    func write(_ value: Int64) throws { writes += 1; if failWrites { throw CocoaError(.fileWriteNoPermission) }; used = value }
}

private func run(_ candidates: [Candidate], succeeded: Bool = true) -> (CatalogExecutionResult, CatalogApproval) {
    let approval = CatalogApproval(candidates: candidates, dryRun: false)
    let records = candidates.map { candidate in
        var record = CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: candidate, dryRun: false)
        record.state = succeeded ? .succeeded : .failed
        return record
    }
    return (CatalogExecutionResult(batchID: approval.id, records: records, dryRun: false, rejectedReplay: false, journalFailure: nil, estimatedBytes: 0), approval)
}

/// The count starts at zero, grows with each cleanup, and a new launch or a reinstall (a new controller on the same
/// Keychain item) reads it back, so the trial doesn't start over.
@Test @MainActor func theTrialCountStartsAtZeroAndSurvivesARelaunch() {
    let store = MemoryTrialStore()
    let trial = TrialController(store: store, gating: true)
    #expect(trial.allowance(for: .none) == .trial(left: 2 * GB))
    let (result, approval) = run([logs])
    trial.record(result, of: approval, catalog: catalog)
    #expect(trial.allowance(for: .none) == .trial(left: GB))
    #expect(store.used == GB)
    #expect(TrialController(store: store, gating: true).allowance(for: .none) == .trial(left: GB))
    let (failed, failedApproval) = run([npm], succeeded: false)
    trial.record(failed, of: failedApproval, catalog: catalog)
    #expect(store.used == GB, "A failed item counts nothing")
}

/// With the build setting off nothing changes: the Keychain item is never read or written, and nothing is gated.
@Test @MainActor func withGatingOffTheTrialIsNeverReadOrCounted() {
    let store = MemoryTrialStore(5 * GB)
    let trial = TrialController(store: store, gating: false)
    let (result, approval) = run([npm])
    trial.record(result, of: approval, catalog: catalog)
    #expect(trial.allowance(for: .none) == .unlimited)
    #expect(store.reads == 0 && store.writes == 0)
}

/// A Keychain that can't be read or written says so (Decision 62) rather than reading as a fresh trial in silence; the
/// count goes on in memory for this launch.
@Test @MainActor func aKeychainFailureSaysSoAndTheCountGoesOnInMemory() {
    let store = MemoryTrialStore(GB)
    store.failReads = true
    let trial = TrialController(store: store, gating: true)
    #expect(trial.notice == .unreadable)
    let (result, approval) = run([logs])
    trial.record(result, of: approval, catalog: catalog)
    #expect(trial.notice == .unreadable, "Still unreadable, so nothing was saved")
    #expect(trial.allowance(for: .none) == .trial(left: GB))
    store.failReads = false; store.failWrites = true
    trial.record(result, of: approval, catalog: catalog)
    #expect(trial.notice == .saveFailed)
}

/// A launch that couldn't read the count never overwrites it with that launch's smaller total: it reads again before
/// saving, and adds to what's stored; while it still can't read, it saves nothing.
@Test @MainActor func aLaunchThatCouldntReadTheCountNeverOverwritesIt() {
    let store = MemoryTrialStore(1_500_000_000)
    store.failReads = true
    let trial = TrialController(store: store, gating: true)
    let (first, firstApproval) = run([logs])
    trial.record(first, of: firstApproval, catalog: catalog)
    #expect(store.used == 1_500_000_000, "Still unreadable: nothing saved over the stored count")
    store.failReads = false
    let (second, secondApproval) = run([npm])
    trial.record(second, of: secondApproval, catalog: catalog)
    #expect(store.used == 1_500_000_000 + GB + 3 * GB, "Readable again: both runs added to what was stored")
    #expect(trial.notice == nil)
    #expect(trial.allowance(for: .none) == .trial(left: 0))
}

/// Settings › License's first line while no key is active: what the trial has left, or that it's used; nothing while
/// gating is off or a license is active, so the license's own line shows.
@Test func settingsSaysWhatTheTrialHasLeftOrThatItsUsed() {
    #expect(CleanupAllowance.trial(left: 2 * GB).settingsLine == "2 GB of free cleanup left")
    #expect(CleanupAllowance.trial(left: 1_200_000_000).settingsLine == "1.2 GB of free cleanup left")
    #expect(CleanupAllowance.trial(left: 0).settingsLine == "Free trial used")
    #expect(CleanupAllowance.unlimited.settingsLine == nil)
}

/// The review sheet's one line: what the trial has left against the plan's size; nothing when unlimited or a dry run.
@Test func theReviewSheetSaysWhatTheTrialHasLeftAgainstThePlan() {
    #expect(CleanupAllowance.trial(left: 1_200_000_000).reviewLine(plan: 300_000_000, dryRun: false) == "1.2 GB of free cleanup left · this cleanup uses 300 MB")
    #expect(CleanupAllowance.trial(left: 1_200_000_000).reviewLine(plan: 3_400_000_000, dryRun: false) == "This cleanup is 3.4 GB, more than the 1.2 GB of free cleanup left")
    #expect(CleanupAllowance.trial(left: 0).reviewLine(plan: 3_400_000_000, dryRun: false) == "Free trial used · this cleanup is 3.4 GB")
    #expect(CleanupAllowance.trial(left: GB).reviewLine(plan: 3 * GB, dryRun: true) == nil)
    #expect(CleanupAllowance.unlimited.reviewLine(plan: 3 * GB, dryRun: false) == nil)
}

/// The price shows its saving, 29.99 then 19.99, with the Mac's region currency symbol: the same numbers in every currency.
@Test func thePriceIsTheSameNumbersInTheRegionsCurrency() {
    let us = LicensePrice.text(locale: Locale(identifier: "en_US"))
    #expect(us.was == "$29.99" && us.now == "$19.99")
    let france = LicensePrice.text(locale: Locale(identifier: "fr_FR"))
    #expect(france.was.contains("29,99") && france.was.contains("€") && france.now.contains("19,99"))
    let uk = LicensePrice.text(locale: Locale(identifier: "en_GB"))
    #expect(uk.now == "£19.99")
    let canada = LicensePrice.text(locale: Locale(identifier: "en_CA"))
    #expect(canada.now == "$19.99")
    let japan = LicensePrice.text(locale: Locale(identifier: "ja_JP"))
    #expect(japan.now.contains("$") && japan.now.contains("19.99") && !japan.now.contains("¥"),
            "A region whose currency isn't sold shows US dollars, which its checkout charges")
}

/// The trial's Keychain item is its own, apart from the license key's, and its names are stored keys: renaming either
/// would start every Mac's trial over (#448). It holds the count as decimal text; anything else reads as unreadable.
@Test @MainActor func theTrialsKeychainItemKeepsItsNamesAndReadsOnlyACount() throws {
    #expect(KeychainTrialStore.service == "com.patrickbourget.CacheDrop.trial")
    #expect(KeychainTrialStore.account == "freed-bytes")
    #expect(KeychainTrialStore.service != KeychainLicenseKeyStore.service)
    #expect(try KeychainTrialStore.count(from: Data("1234567".utf8)) == 1_234_567)
    #expect(throws: (any Error).self) { try KeychainTrialStore.count(from: Data("lots".utf8)) }
}
