import Foundation
import Testing
@testable import CacheDropCore

/// #249: a scanned folder a recheck can't find keeps its last observation, marked as gone, never as current.
@Test func aRecheckThatCannotFindTheFolderSaysFolderNotFound() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropGone-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(UnavailableScannedFolder.reason(path: root.appendingPathComponent("Deleted").path, otherwise: "Access unavailable") == "Folder not found")
    // A folder that is still there but can't be read keeps the access reason Overview gives.
    #expect(UnavailableScannedFolder.reason(path: root.path, otherwise: "Access unavailable") == "Access unavailable")
}

@Test func theExplorerRowNamesTheReasonAndWhenTheFolderWasLastObserved() {
    #expect(UnavailableScannedFolder.text(reason: "Folder not found", lastObserved: "27 Oct 2026 at 10:02")
        == "Folder not found · last observed 27 Oct 2026 at 10:02")
    #expect(UnavailableScannedFolder.text(reason: "Folder not found", lastObserved: nil) == "Folder not found")
}

@Test func aFolderInsideAGoneLocationBelongsToThatLocation() {
    let gone = [URL(fileURLWithPath: "/tmp/Picked"), URL(fileURLWithPath: "/tmp/Other")]
    #expect(UnavailableScannedFolder.location(holding: URL(fileURLWithPath: "/tmp/Picked"), among: gone) == URL(fileURLWithPath: "/tmp/Picked"))
    #expect(UnavailableScannedFolder.location(holding: URL(fileURLWithPath: "/tmp/Picked/Inner/Deeper"), among: gone) == URL(fileURLWithPath: "/tmp/Picked"))
    #expect(UnavailableScannedFolder.location(holding: URL(fileURLWithPath: "/tmp/PickedTwo"), among: gone) == nil)
    #expect(UnavailableScannedFolder.location(holding: URL(fileURLWithPath: "/tmp"), among: gone) == nil)
}

@Test func aGoneLocationsOldContentsAreNotCurrent() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let picked = ScanResultFixture.scan(scope: "/tmp/Picked", at: now)
    let kept = ScanResultFixture.scan(scope: "/tmp/Kept", at: now)
    let current = UnavailableScannedFolder.current([picked, kept], gone: [URL(fileURLWithPath: "/tmp/Picked/")])
    #expect(current.map(\.scope.path) == ["/tmp/Kept"])
}

@Test func theLastObservationIsTheNewestScanOfThatLocation() {
    let older = ScanResultFixture.scan(scope: "/tmp/Picked", at: Date(timeIntervalSince1970: 1_000))
    let newer = ScanResultFixture.scan(scope: "/tmp/Picked", at: Date(timeIntervalSince1970: 2_000))
    let other = ScanResultFixture.scan(scope: "/tmp/Other", at: Date(timeIntervalSince1970: 3_000))
    #expect(UnavailableScannedFolder.lastObserved(URL(fileURLWithPath: "/tmp/Picked"), in: [older, other, newer]) == Date(timeIntervalSince1970: 2_000))
    #expect(UnavailableScannedFolder.lastObserved(URL(fileURLWithPath: "/tmp/Never"), in: [older]) == nil)
}

private enum ScanResultFixture {
    static func scan(scope: String, at date: Date) -> ScanResult {
        ScanResult(scope: URL(fileURLWithPath: scope), observedAt: date, observations: [], logicalBytes: 0, allocatedBytes: 0,
                   allocatedUnknownCount: 0, volumeCapacityBytes: nil, volumeAvailableBytes: nil, issues: [],
                   volumeAvailableMetric: "", exclusionFingerprint: "none", excludedEntryCount: 0)
    }
}
