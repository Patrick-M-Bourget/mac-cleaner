import Foundation
import Testing
@testable import CacheDropCore

/// Decision 123 (#556): when the Applications page waits for the running scan, and what it can tick and review meanwhile.
private func item(_ ruleID: String) -> Candidate {
    Candidate(ruleID: ruleID, action: .trash, url: fixtureNoHome.appendingPathComponent(ruleID), resourceID: "1:" + ruleID, isDirectory: true, toolURL: nil,
              volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: 1_000, allocatedBytes: 1_000, sizeComplete: true, lastUsed: nil,
              observedAt: Date(), profile: nil)
}
private let app = item(AppUninstall.appRuleID), leftover = item(RemovedAppLeftovers.possiblyRelatedRuleID), cache = item("npm-cache")

/// A run that changed nothing Applications lists ended, then the rescan after it started.
private func keptRescan() -> ApplicationsRescan {
    var rescan = ApplicationsRescan()
    rescan.scanStarted(); rescan.scanPrepared(UUID())
    rescan.runStarted(); rescan.runEnded(keptApplications: true)
    rescan.rescanRequested(afterRun: true, scanning: false); rescan.scanStarted()
    return rescan
}

@Test func theRescanAfterARunThatKeptApplicationsLetsAppsBeChosenButNothingElse() {
    let rescan = keptRescan()
    #expect(!rescan.appsWait(scanning: true))
    #expect(rescan.canChoose([app], scanning: true), "An app is ticked and reviewed during it")
    #expect(!rescan.canChoose([leftover], scanning: true), "Files from deleted apps wait for the scan")
    #expect(!rescan.canChoose([app, leftover], scanning: true), "So does a review that holds one")
    #expect(!rescan.canChoose([cache], scanning: true), "Every other page waits too")
    #expect(rescan.canChoose([cache, leftover], scanning: false), "Once the scan ends, anything")
}

@Test func anyOtherScanMakesApplicationsWait() {
    var fresh = ApplicationsRescan()
    fresh.rescanRequested(afterRun: false, scanning: false); fresh.scanStarted()
    #expect(fresh.appsWait(scanning: true), "Launch, Scan again, Put back")
    #expect(!fresh.canChoose([app], scanning: true))

    var changed = ApplicationsRescan()
    changed.runStarted(); changed.runEnded(keptApplications: false)
    changed.rescanRequested(afterRun: true, scanning: false)
    #expect(changed.appsWait(scanning: true), "The rescan after an uninstall")

    var failed = ApplicationsRescan()
    failed.runStarted()
    failed.rescanRequested(afterRun: true, scanning: false)
    #expect(failed.appsWait(scanning: true), "A run that never said what it changed")

    var queued = keptRescan()
    queued.rescanRequested(afterRun: false, scanning: true)
    #expect(queued.appsWait(scanning: true), "Scan again asked for during the kept rescan")
}

@Test func aRunsKeepingIsUsedOnceByTheRescanAfterIt() {
    var rescan = keptRescan()
    rescan.scanPrepared(UUID())
    // A run with no catalog items ends without saying; its rescan must not reuse the last run's answer.
    rescan.rescanRequested(afterRun: true, scanning: false)
    #expect(rescan.appsWait(scanning: true))
}

@Test func theListsAreReadAgainOnlyAfterAScanThatCouldChangeThem() {
    var rescan = ApplicationsRescan()
    rescan.scanStarted()
    #expect(rescan.listsScan == nil, "Nothing to read yet")
    let full = UUID()
    rescan.scanPrepared(full)
    #expect(rescan.listsScan == full)
    rescan.runStarted(); rescan.runEnded(keptApplications: true)
    rescan.rescanRequested(afterRun: true, scanning: false); rescan.scanStarted()
    #expect(rescan.listsScan == full, "The kept rescan's lists are the last full scan's, readable during it")
    rescan.scanPrepared(UUID())
    #expect(rescan.listsScan == full, "and after it: nothing to read again")
    rescan.rescanRequested(afterRun: false, scanning: false); rescan.scanStarted()
    #expect(rescan.listsScan == nil)
    let next = UUID()
    rescan.scanPrepared(next)
    #expect(rescan.listsScan == next)
    rescan.scanFoundNothing()
    #expect(rescan.listsScan == nil, "A scan that couldn't read the settings: read them again")
}
