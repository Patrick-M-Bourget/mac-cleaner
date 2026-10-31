import Foundation
import Testing
@testable import CacheDropCore

/// A scan of `scope` as the folder scanner would record it; nothing here touches disk.
private func scan(_ scope: String = "/tmp/Projects", bytes: Int64 = 12_000_000, allocated: Int64? = nil, issues: [(String, ScanIssue.Reason)] = [], excluded: Int = 0,
                  kinds: [ObservationKind] = []) -> ScanResult {
    let observations = kinds.enumerated().map { index, kind in
        FileObservation(id: "\(index)", resourceID: "1:\(index)", url: URL(fileURLWithPath: scope + "/item\(index)"), kind: kind, logicalBytes: nil, allocatedBytes: nil,
                        previewAvailability: .local, isDuplicateResource: false, cloud: .unknown)
    }
    return ScanResult(scope: URL(fileURLWithPath: scope), observedAt: Date(), observations: observations, logicalBytes: bytes, allocatedBytes: allocated ?? bytes,
                      issues: issues.map { ScanIssue(url: URL(fileURLWithPath: $0.0), reason: $0.1) },
                      exclusionFingerprint: "none", excludedEntryCount: excluded)
}
private func location(_ scan: ScanResult?, scope: String = "/tmp/Projects") -> ScannedLocation {
    ScannedLocation(scope: URL(fileURLWithPath: scope), scan: scan)
}

/// #345: each scanned location is one row on Overview, with its name and the size the scan found.
@Test func aScannedLocationShowsItsNameAndSize() {
    let row = location(scan())
    #expect(row.name == "Projects")
    #expect(row.value == "12 MB")
}

@Test func aLocationNotScannedYetSaysSo() {
    #expect(location(nil).value == "Not scanned")
}

@Test func aSizeThatLeavesSomethingOutIsALowerBound() {
    #expect(location(scan(issues: [("/tmp/Projects/a", .accessDenied)])).value == "At least 12 MB")
    #expect(location(scan(excluded: 2)).value == "At least 12 MB")
    #expect(location(scan(kinds: [.package])).value == "At least 12 MB")
}


/// #527: a folder read failure alone does not establish that Full Disk Access is missing.
@Test func unreadableFoldersNameTheirCountWithoutAssumingFullDiskAccess() {
    let row = location(scan(issues: [("/tmp/Projects/a", .accessDenied), ("/tmp/Projects/b", .accessRevoked), ("/tmp/Projects/b", .accessDenied)]))
    #expect(row.problem == "2 folders couldn’t be read")
    #expect(row.action == .openLocations)
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

/// Several reasons share one line; folder guidance comes before retrying an incomplete scan.
@Test func reasonsShareOneLineAndFolderGuidanceComesFirst() {
    let row = location(scan(issues: [("/tmp/Projects", .timeLimit), ("/tmp/Projects/a", .accessDenied)]))
    #expect(row.problem == "1 folder couldn’t be read · Scan stopped early")
    #expect(row.action == .openLocations)
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

/// #376, #388: a location's size is what it takes on disk, as Explore storage's "On disk" shows it. A sparse disk image (Docker's
/// `Docker.raw`: 288 GB logical, 4 GB used) never makes its folder look huge.
@Test func aLocationsSizeIsItsOnDiskSize() {
    #expect(location(scan(bytes: 288_000_000_000, allocated: 4_000_000_000)).value == "4 GB")
    #expect(location(scan(bytes: 288_000_000_000, allocated: 4_000_000_000, excluded: 1)).value == "At least 4 GB")
}
