import Foundation
import Testing
@testable import CacheDropCore

// #627: one cleanup at a time across the app and `cachedrop clean`. A fixture folder only.

@Suite struct CleanupLockTests {
    /// The file both take: a stored name beside the journal.
    @Test func bothTakeTheSameLockBesideTheJournal() { #expect(LocalStateLocation.cleanupLockName == "cleanup.lock") }

    /// A second acquisition, through its own `open` as another process's would be, waits until the first is released;
    /// releasing twice is harmless, and dropping the lock releases it.
    @Test func aSecondCleanupWaitsUntilTheFirstEnds() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCleanupLock-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(LocalStateLocation.cleanupLockName)
        let first = try #require(try CleanupLock.acquire(at: url))
        #expect(try CleanupLock.acquire(at: url) == nil, "Held: the second waits")
        first.release(); first.release()
        var second = try CleanupLock.acquire(at: url)
        #expect(second != nil, "Released: the next one starts")
        second = nil
        #expect(try CleanupLock.acquire(at: url) != nil, "Dropped: released")
    }

    @Test func aLockThatCantBeOpenedThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropMissing-\(UUID())/cleanup.lock")
        #expect(throws: (any Error).self) { try CleanupLock.acquire(at: missing) }
    }
}
