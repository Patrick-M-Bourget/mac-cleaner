import Foundation
import Testing
@testable import CacheDropCore

/// Observations as a folder scan reports them. Nothing here touches disk.
private func observed(_ path: String, _ kind: ObservationKind = .file, bytes: Int64? = 1_000, resource: String? = nil) -> FileObservation {
    FileObservation(id: path, resourceID: resource ?? "r:" + path, url: URL(fileURLWithPath: path), kind: kind, logicalBytes: bytes, allocatedBytes: bytes,
                    previewAvailability: .local, isDuplicateResource: false, cloud: .unknown)
}
private func scan(_ scope: String, at time: Double = 0, _ observations: [FileObservation], issues: [ScanIssue] = []) -> ScanResult {
    ScanResult(scope: URL(fileURLWithPath: scope), observedAt: Date(timeIntervalSince1970: time), observations: observations, logicalBytes: 0, allocatedBytes: 0,
               allocatedUnknownCount: 0, volumeCapacityBytes: nil, volumeAvailableBytes: nil, issues: issues,
               volumeAvailableMetric: "", exclusionFingerprint: "none", excludedEntryCount: 0)
}
private func index(_ scans: [ScanResult], reports: [ScanResult] = []) -> StorageExplorerIndex {
    StorageExplorerIndex(scans: scans, reports: reports, allowedScopes: nil) { _, _ in false }
}
private let picked = scan("/P", [
    observed("/P/b.txt"), observed("/P/Sub", .folder), observed("/P/A file 10.txt"), observed("/P/A file 9.txt"),
    observed("/P/Sub/x.bin", bytes: 4_000), observed("/P/Sub/link.bin", bytes: 4_000, resource: "r:/P/Sub/x.bin"), observed("/P/Sub/unknown", bytes: nil),
])

@Test func aFoldersChildrenComeFoldersFirstThenInFindersOrder() {
    #expect(index([picked]).children(of: URL(fileURLWithPath: "/P")).map(\.item.url.lastPathComponent) == ["Sub", "A file 9.txt", "A file 10.txt", "b.txt"])
}

@Test func aSubtotalCountsEachFileIdentityOnceAndUnknownSizesLeaveARemainder() {
    let subtotal = index([picked]).allocatedSubtotal(in: URL(fileURLWithPath: "/P/Sub"))
    #expect(subtotal == StorageExplorerIndex.Subtotal(bytes: 4_000, hasUnknownRemainder: true))
    #expect(index([picked]).allocatedSubtotal(in: URL(fileURLWithPath: "/P")).bytes == 7_000)
}

@Test func aPartlyScannedLocationLeavesARemainder() {
    let partial = scan("/Q", [observed("/Q/a")], issues: [ScanIssue(url: URL(fileURLWithPath: "/Q/locked"), reason: .accessDenied)])
    #expect(index([partial]).allocatedSubtotal(in: URL(fileURLWithPath: "/Q")) == StorageExplorerIndex.Subtotal(bytes: 1_000, hasUnknownRemainder: true))
}

@Test func theLatestScanOfALocationWinsAndItsFoldersAndEntriesCanBeFound() {
    let older = scan("/P", at: 0, [observed("/P/old.txt")])
    let explorer = index([older], reports: [scan("/P", at: 10, picked.observations)])
    #expect(explorer.scans.count == 1)
    #expect(explorer.entry(id: "/P/old.txt", resource: "r:/P/old.txt") == nil)
    #expect(explorer.entry(id: "/P/b.txt", resource: "r:/P/b.txt")?.item.url.lastPathComponent == "b.txt")
    #expect(explorer.contains(folder: URL(fileURLWithPath: "/P/Sub")))
    #expect(explorer.contains(folder: URL(fileURLWithPath: "/P")))
    #expect(!explorer.contains(folder: URL(fileURLWithPath: "/P/b.txt")))
}

@Test func searchingAFolderReachesEveryDescendantByItsPathInside() {
    let explorer = index([picked])
    #expect(explorer.matches(in: URL(fileURLWithPath: "/P"), query: "SUB/").map(\.item.url.lastPathComponent) == ["link.bin", "unknown", "x.bin"])
    #expect(explorer.matches(in: URL(fileURLWithPath: "/P/Sub"), query: "sub").isEmpty, "Only the path inside the folder is searched")
    #expect(explorer.entry(resource: "r:/P/b.txt")?.item.url.lastPathComponent == "b.txt")
}

/// #346: the scanner keeps up to 100,000 entries a location, and Explore storage froze on a real Mac with two: the
/// explorer re-merged and re-sorted every observation, and walked them all again for each row's size, on every redraw.
/// The index is built once per change in the scans, off the main thread (bounded here in a debug build); listing a large
/// folder with each child's size, what a redraw asks for, is then nearly free. The old code was still running after a minute on this test's data (2026-10-28).
@Test func aLargeScannedFolderIsIndexedOnceAndListedQuickly() {
    var observations: [FileObservation] = []
    for folder in 0..<1_000 {
        observations.append(observed("/Big/Folder \(folder)", .folder))
        for file in 0..<99 { observations.append(observed("/Big/Folder \(folder)/file \(file).dat")) }
    }
    let large = scan("/Big", observations)
    let started = Date()
    let explorer = index([large])
    let built = Date().timeIntervalSince(started)
    let listing = Date()
    let listed = explorer.children(of: URL(fileURLWithPath: "/Big"))
    let sizes = listed.map { explorer.allocatedSubtotal(in: $0.item.url).bytes }
    let listedIn = Date().timeIntervalSince(listing)
    #expect(listed.count == 1_000)
    #expect(listed.prefix(3).map(\.item.url.lastPathComponent) == ["Folder 0", "Folder 1", "Folder 2"])
    #expect(sizes.allSatisfy { $0 == 99_000 })
    // The build runs once, off the main thread; this only bounds it, loosely, since other tests share the machine.
    #expect(built < 30, "Built in \(built) s")
    #expect(listedIn < 0.1, "Listed in \(listedIn) s")
}

/// #346 review: a file seen only through a location nested in another still counts toward the outer one's folders.
@Test func aNestedLocationsFilesCountTowardTheOuterLocation() {
    let outer = scan("/U", at: 0, [observed("/U/top.txt"), observed("/U/Docs", .folder)])
    let inner = scan("/U/Docs", at: 10, [observed("/U/Docs/report.pdf", bytes: 5_000)])
    #expect(index([outer, inner]).allocatedSubtotal(in: URL(fileURLWithPath: "/U")).bytes == 6_000)
}

@Test func searchingFromTheRootFindsEntries() {
    #expect(index([picked]).matches(in: URL(fileURLWithPath: "/"), query: "b.txt").map(\.item.url.path) == ["/P/b.txt"])
}

/// #346 review: which observation stands for a shared file identity doesn't depend on dictionary order.
@Test func aSharedIdentityIsAlwaysRepresentedByTheSamePath() {
    let paths = (0..<20).map { _ in index([picked]).entry(resource: "r:/P/Sub/x.bin")?.item.url.path }
    #expect(Set(paths) == ["/P/Sub/link.bin"])
}
