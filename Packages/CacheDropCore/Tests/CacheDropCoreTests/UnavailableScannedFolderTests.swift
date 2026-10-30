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
        == "Folder not found · last scanned 27 Oct 2026 at 10:02")
    #expect(UnavailableScannedFolder.text(reason: "Folder not found", lastObserved: nil) == "Folder not found")
    // #257: a folder that is there but unreadable gives its reason alone, as Overview does; a date wouldn't explain it.
    #expect(UnavailableScannedFolder.text(reason: "Access unavailable", lastObserved: "27 Oct 2026 at 10:02") == "Access unavailable")
}

/// #254: Overview tells a deleted or moved folder from one that is there but unreadable, in the explorer's words.
@Test func overviewSaysFolderNotFoundWithTheLastObservationOnlyWhenTheFolderIsGone() {
    #expect(UnavailableScannedFolder.overviewText(name: "Picked", reason: "Folder not found", lastObserved: "27 Oct 2026 at 10:02")
        == "Picked · Folder not found · last scanned 27 Oct 2026 at 10:02")
    #expect(UnavailableScannedFolder.overviewText(name: "Picked", reason: "Folder not found", lastObserved: nil) == "Picked · Folder not found")
    // Present but unreadable keeps today's row: no last observation, which wouldn't explain the problem.
    #expect(UnavailableScannedFolder.overviewText(name: "Downloads", reason: "Access unavailable", lastObserved: "27 Oct 2026 at 10:02")
        == "Downloads · Access unavailable")
    #expect(UnavailableScannedFolder.overviewText(name: "Projects", reason: "Location unavailable", lastObserved: nil) == "Projects · Location unavailable")
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
                   issues: [], exclusionFingerprint: "none", excludedEntryCount: 0)
    }
}
