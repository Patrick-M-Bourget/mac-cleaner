import Foundation
import Testing
@testable import CacheDropCore

/// A scan of `scope` as the folder scanner would record it; nothing here touches disk.
private func scan(_ scope: String = "/tmp/Projects", bytes: Int64 = 12_000_000, issues: [(String, ScanIssue.Reason)] = [], excluded: Int = 0,
                  kinds: [ObservationKind] = []) -> ScanResult {
    let observations = kinds.enumerated().map { index, kind in
        FileObservation(id: "\(index)", resourceID: "1:\(index)", url: URL(fileURLWithPath: scope + "/item\(index)"), kind: kind, logicalBytes: nil, allocatedBytes: nil,
                        previewAvailability: .local, isDuplicateResource: false, cloud: .unknown)
    }
    return ScanResult(scope: URL(fileURLWithPath: scope), observedAt: Date(), observations: observations, logicalBytes: bytes, allocatedBytes: bytes,
                      allocatedUnknownCount: 0, volumeCapacityBytes: nil, volumeAvailableBytes: nil,
                      issues: issues.map { ScanIssue(url: URL(fileURLWithPath: $0.0), reason: $0.1) },
                      volumeAvailableMetric: "", exclusionFingerprint: "none", excludedEntryCount: excluded)
}
private func megabytes(_ bytes: Int64) -> String { "\(bytes / 1_000_000) MB" }
private func location(_ scan: ScanResult?, scope: String = "/tmp/Projects") -> ScannedLocationsSummary.Location {
    ScannedLocationsSummary.Location(scope: URL(fileURLWithPath: scope), scan: scan)
}

/// #345: each scanned location is one row on Overview, with its name and the size the scan found.
@Test func aScannedLocationShowsItsNameAndSize() {
    let row = location(scan())
    #expect(row.name == "Projects")
    #expect(row.value(megabytes) == "12 MB")
}

@Test func aLocationNotScannedYetSaysSo() {
    #expect(location(nil).value(megabytes) == "Not scanned")
}

@Test func aSizeThatLeavesSomethingOutIsALowerBound() {
    #expect(location(scan(issues: [("/tmp/Projects/a", .accessDenied)])).value(megabytes) == "At least 12 MB")
    #expect(location(scan(excluded: 2)).value(megabytes) == "At least 12 MB")
    #expect(location(scan(kinds: [.package])).value(megabytes) == "At least 12 MB")
}


/// #358: a location whose folders macOS kept from CacheDrop says how many, and offers Full Disk Access.
@Test func unreadableFoldersNameTheirCountAndOfferFullDiskAccess() {
    let row = location(scan(issues: [("/tmp/Projects/a", .accessDenied), ("/tmp/Projects/b", .accessRevoked), ("/tmp/Projects/b", .accessDenied)]))
    #expect(row.problem == "2 folders couldn’t be read")
    #expect(row.action == .grantFullDiskAccess)
    #expect(location(scan(issues: [("/tmp/Projects/a", .accessDenied)])).problem == "1 folder couldn’t be read")
}

/// #358: a scan that hit one of its limits, or whose folders changed under it, stopped early; Scan again is the fix.
@Test func aScanThatHitALimitStoppedEarly() {
    for reason: ScanIssue.Reason in [.timeLimit, .entryLimit, .issueLimit, .depthLimit, .directoryChanged] {
        let row = location(scan(issues: [("/tmp/Projects", reason)]))
        #expect(row.problem == "Scan stopped early")
        #expect(row.action == .scanAgain)
    }
}

/// Files that failed to read for another reason are counted; another scan may read them.
@Test func filesThatFailedToReadAreCounted() {
    let row = location(scan(issues: [("/tmp/Projects/a", .readFailed), ("/tmp/Projects/b", .metadataUnavailable)]))
    #expect(row.problem == "2 items couldn’t be read")
    #expect(row.action == .scanAgain)
}

/// Several reasons share one line; Full Disk Access is the fix that matters most.
@Test func reasonsShareOneLineAndFullDiskAccessComesFirst() {
    let row = location(scan(issues: [("/tmp/Projects", .timeLimit), ("/tmp/Projects/a", .accessDenied)]))
    #expect(row.problem == "1 folder couldn’t be read · Scan stopped early")
    #expect(row.action == .grantFullDiskAccess)
}

/// #358: what the user excluded, packages the scan doesn't open and other volumes are neutral notes, never a problem.
@Test func excludedEntriesAndPackagesAreNeutralNotes() {
    let row = location(scan(issues: [("/tmp/Projects/Volume", .differentVolume)], excluded: 3, kinds: [.package, .package, .file]))
    #expect(row.problem == nil)
    #expect(row.action == nil)
    #expect(row.notes == "3 excluded · 2 packages not measured · 1 on another volume")
    #expect(location(scan(kinds: [.package, .other])).notes == "1 package not measured · 1 special file not measured")
    #expect(location(scan()).notes == nil)
}

/// A file that vanished mid-scan, or exclusions that couldn't be checked, count as unread; another scan may read them.
@Test func itemsGoneOrUncheckedMidScanCountAsUnread() {
    let row = location(scan(issues: [("/tmp/Projects/a", .locationUnavailable), ("/tmp/Projects", .exclusionUnavailable)]))
    #expect(row.problem == "2 items couldn’t be read")
    #expect(row.action == .scanAgain)
}
