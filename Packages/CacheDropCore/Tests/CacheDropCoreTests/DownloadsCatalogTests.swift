import Foundation
import Testing
import CacheDropCore

/// A temp home with a Downloads folder; tests never read or write the real Downloads.
private func downloadsHome() throws -> (home: URL, downloads: URL) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillDownloads-\(UUID())").resolvingSymlinksInPath()
    let downloads = home.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    return (home.resolvingSymlinksInPath(), downloads.resolvingSymlinksInPath())
}
private let day: TimeInterval = 86_400
/// Writes a file of `size` logical bytes (sparse when large) last opened, changed and created `age` ago.
@discardableResult
private func file(_ downloads: URL, _ path: String, size: Int64 = 10, age: TimeInterval = 0, now: Date) throws -> URL {
    let url = downloads.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: Int(min(size, 10))))
    if size > 10 { let handle = try FileHandle(forWritingTo: url); try handle.truncate(atOffset: UInt64(size)); try handle.close() }
    let date = now.addingTimeInterval(-age)
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
    return url
}
private let megabyte: Int64 = 1_000_000

@Test func downloadsOffersInstallersAtAnyAgeAndOnlyLargeFilesNotOpenedIn90Days() throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    try file(downloads, "Setup.dmg", now: now)
    try file(downloads, "Old Tool.PKG", age: 400 * day, now: now)
    try file(downloads, "nested/archive.zip", now: now)
    try file(downloads, "notes.txt", age: 400 * day, now: now)
    try file(downloads, "movie-old.mov", size: 600 * megabyte, age: 120 * day, now: now)
    try file(downloads, "movie-recent.mov", size: 600 * megabyte, age: 30 * day, now: now)
    try file(downloads, "small-old.mov", size: 499 * megabyte, age: 120 * day, now: now)
    try file(downloads, "big-old.dmg", size: 600 * megabyte, age: 120 * day, now: now)
    try file(downloads, "Thing.app/Contents/inner.dmg", now: now)
    try file(downloads, "Projects.photoslibrary/big.mov", size: 600 * megabyte, age: 120 * day, now: now)
    try FileManager.default.createSymbolicLink(at: downloads.appendingPathComponent("link.dmg"), withDestinationURL: downloads.appendingPathComponent("Setup.dmg"))

    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, now: now)
    let found = Dictionary(uniqueKeysWithValues: candidates.map { (String($0.url.path.dropFirst(downloads.path.count + 1)), $0) })
    #expect(Set(found.keys) == ["Setup.dmg", "Old Tool.PKG", "nested/archive.zip", "big-old.dmg", "movie-old.mov"])
    #expect(found["Setup.dmg"]?.ruleID == "downloads-installers")
    #expect(found["big-old.dmg"]?.ruleID == "downloads-installers")
    #expect(found["movie-old.mov"]?.ruleID == "downloads-old-large")
    #expect(candidates.allSatisfy { $0.action == .trash && !$0.isDirectory && $0.sizeComplete })
    #expect(found["movie-old.mov"]?.logicalBytes == 600 * megabyte)
    let lastUsed = try #require(found["movie-old.mov"]?.lastUsed)
    #expect(abs(lastUsed.timeIntervalSince(now.addingTimeInterval(-120 * day))) < 2)
}

@Test func aLargeFileOpenedRecentlyIsNotOld() throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    let url = try file(downloads, "video.mov", size: 600 * megabyte, age: 200 * day, now: now)
    let opened = now.addingTimeInterval(-10 * day)
    var times = [timeval(tv_sec: Int(opened.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(now.addingTimeInterval(-200 * day).timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
    #expect(Catalog(rules: fixtureRules).discover(fixture: home, now: now).isEmpty)
}

/// Stands in for the Finder Trash so tests never touch the user's real Trash.
private struct FixtureTrash: TrashMoving {
    let folder: URL
    var substitute = false
    func moveToTrash(_ url: URL) throws -> URL? {
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: destination)
        if substitute { try FileManager.default.removeItem(at: destination); try Data([9]).write(to: destination) }
        return destination
    }
}
private struct AlwaysClosed: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }
private func trashExecutor(_ home: URL, trash: FixtureTrash) throws -> (CleanupExecutor, SQLiteCleanupJournal) {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: AlwaysClosed())
    return (CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: trash), journal)
}

@Test func chosenDownloadsGoToTrashAndCountAsHeldNotFreed() async throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = try file(downloads, "Setup.dmg", size: 2048, now: Date())
    try file(downloads, "Other.pkg", now: Date())
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home)
    let chosen = try #require(candidates.first { $0.url == installer })
    let trash = FixtureTrash(folder: home.appendingPathComponent("FixtureTrash"))
    let (run, journal) = try trashExecutor(home, trash: trash)
    let result = await run.execute(CatalogApproval(candidates: [chosen], previewOnly: false))
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded)
    #expect(record.action == "moveToTrash")
    #expect(record.message == "Moved to Trash")
    #expect(record.trashURL == trash.folder.appendingPathComponent("Setup.dmg"))
    #expect(!FileManager.default.fileExists(atPath: installer.path))
    #expect(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("Other.pkg").path))
    #expect(result.movedToTrashBytes == chosen.allocatedBytes)
    #expect(result.measuredFreedBytes == 0)
    #expect(try journal.completedHistory().completedRuns.first?.trashHeldAllocatedBytes == chosen.allocatedBytes)
}

@Test func aTrashMoveThatLandsADifferentItemIsUnresolvedAndStopsTheRun() async throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try file(downloads, "a.dmg", now: Date()); try file(downloads, "b.dmg", now: Date())
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home).sorted { $0.url.path < $1.url.path }
    let (run, _) = try trashExecutor(home, trash: FixtureTrash(folder: home.appendingPathComponent("FixtureTrash"), substitute: true))
    let result = await run.execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.unknown, .cancelled])
    #expect(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("b.dmg").path))
}

@Test func previewOnlyLeavesDownloadsInPlace() async throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = try file(downloads, "Setup.dmg", now: Date())
    let (run, _) = try trashExecutor(home, trash: FixtureTrash(folder: home.appendingPathComponent("FixtureTrash")))
    let result = await run.execute(CatalogApproval(candidates: Catalog(rules: fixtureRules).discover(fixture: home), previewOnly: true))
    #expect(result.records.map(\.state) == [.skipped])
    #expect(result.records.first?.message.hasPrefix("Dry run: would move to Trash") == true)
    #expect(result.movedToTrashBytes == 0)
    #expect(FileManager.default.fileExists(atPath: installer.path))
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("FixtureTrash").path))
}

@Test func aDownloadsFileInsideAGitCheckoutIsNotOffered() throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try file(downloads, "repo/.git/HEAD", now: Date())
    try file(downloads, "repo/dist/Setup.dmg", now: Date())
    try file(downloads, "Other.dmg", now: Date())
    #expect(Catalog(rules: fixtureRules).discover(fixture: home).map(\.url.lastPathComponent) == ["Other.dmg"])
}

// MARK: Old iOS update files (#135)

@Test func oldIOSUpdateFilesAreTrashCandidatesWithSizeAndLastUse() throws {
    let (home, _) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    try file(home, "Library/iTunes/iPhone Software Updates/iPhone15,2_17.0_21A329_Restore.ipsw", size: 7_000 * megabyte, age: 300 * day, now: now)
    try file(home, "Library/iTunes/iPad Software Updates/iPad_64bit_TouchID_16.6_20G75_Restore.ipsw", size: 6_000 * megabyte, age: 30 * day, now: now)
    try file(home, "Library/iTunes/iPod Software Updates/iPod_7.1_Restore.ipsw", size: 2_000 * megabyte, age: 900 * day, now: now)
    // Only IPSW files: the folder's other files and other iTunes folders are not offered.
    try file(home, "Library/iTunes/iPhone Software Updates/notes.txt", now: now)
    try file(home, "Library/iTunes/Other/old.ipsw", now: now)

    let catalog = Catalog(rules: fixtureRules)
    let candidates = catalog.discover(fixture: home)
    #expect(candidates.allSatisfy { $0.ruleID == "ios-software-updates" && $0.action == .trash && !$0.isDirectory })
    let found = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url.lastPathComponent, $0) })
    #expect(Set(found.keys) == ["iPhone15,2_17.0_21A329_Restore.ipsw", "iPad_64bit_TouchID_16.6_20G75_Restore.ipsw", "iPod_7.1_Restore.ipsw"])
    #expect(found["iPhone15,2_17.0_21A329_Restore.ipsw"]?.logicalBytes == 7_000 * megabyte)
    let used = try #require(found["iPad_64bit_TouchID_16.6_20G75_Restore.ipsw"]?.lastUsed)
    #expect(abs(used.timeIntervalSince(now) + 30 * day) < 5)
    let rule = try #require(catalog.rule("ios-software-updates"))
    #expect(rule.category == .updaters)
}

@Test func aChosenIOSUpdateFileGoesToTrash() async throws {
    let (home, _) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let ipsw = try file(home, "Library/iTunes/iPhone Software Updates/iPhone_Restore.ipsw", size: 4096, now: Date())
    let chosen = try #require(Catalog(rules: fixtureRules).discover(fixture: home).first { $0.url == ipsw })
    let trash = FixtureTrash(folder: home.appendingPathComponent("FixtureTrash"))
    let (run, _) = try trashExecutor(home, trash: trash)
    let record = try #require(await run.execute(CatalogApproval(candidates: [chosen], previewOnly: false)).records.first)
    #expect(record.state == .succeeded)
    #expect(record.action == "moveToTrash")
    #expect(!FileManager.default.fileExists(atPath: ipsw.path))
    #expect(FileManager.default.fileExists(atPath: trash.folder.appendingPathComponent("iPhone_Restore.ipsw").path))
}
