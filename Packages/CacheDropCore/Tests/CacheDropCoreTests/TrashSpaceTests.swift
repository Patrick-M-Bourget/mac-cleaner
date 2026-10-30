import Foundation
import Testing
@testable import CacheDropCore

/// A temp home folder with its own `.Trash`; tests never read or open the real Trash.
private func trashHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropTrash-\(UUID())")
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    return URL(fileURLWithPath: try #require(realPath(home.path)))
}
private func write(_ url: URL, bytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: bytes).write(to: url)
}

@Test func anEmptyOrMissingTrashIsEmpty() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(TrashSpace.measure(home: home) == .empty)
    try write(home.appendingPathComponent(".Trash/.DS_Store"), bytes: 6_148)
    #expect(TrashSpace.measure(home: home) == .empty)
    try FileManager.default.removeItem(at: home.appendingPathComponent(".Trash"))
    #expect(TrashSpace.measure(home: home) == .empty)
}

@Test func theTrashIsSizedByTheSpaceItsItemsUse() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home.appendingPathComponent(".Trash/Setup.dmg"), bytes: 200_000)
    try write(home.appendingPathComponent(".Trash/Old project/notes.txt"), bytes: 50_000)
    guard case .holds(let bytes) = TrashSpace.measure(home: home) else { Issue.record("expected a size"); return }
    #expect(bytes >= 250_000)
    #expect(bytes < 400_000)
}

@Test func anUnreadableTrashIsUnknownNeverZero() throws {
    let home = try trashHome()
    defer { chmod(home.appendingPathComponent(".Trash").path, 0o755); try? FileManager.default.removeItem(at: home) }
    try write(home.appendingPathComponent(".Trash/Setup.dmg"), bytes: 10_000)
    #expect(chmod(home.appendingPathComponent(".Trash").path, 0) == 0)
    #expect(TrashSpace.measure(home: home) == .unknown)
}

@Test func aPartlyUnreadableTrashIsUnknown() throws {
    let home = try trashHome()
    let locked = home.appendingPathComponent(".Trash/Locked")
    defer { chmod(locked.path, 0o755); try? FileManager.default.removeItem(at: home) }
    try write(locked.appendingPathComponent("secret.bin"), bytes: 10_000)
    #expect(chmod(locked.path, 0) == 0)
    #expect(TrashSpace.measure(home: home) == .unknown)
}

@Test func aTrashThatIsASymlinkIsUnknown() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let elsewhere = home.appendingPathComponent("elsewhere")
    try write(elsewhere.appendingPathComponent("big.bin"), bytes: 10_000)
    try FileManager.default.removeItem(at: home.appendingPathComponent(".Trash"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".Trash"), withDestinationURL: elsewhere)
    #expect(TrashSpace.measure(home: home) == .unknown)
}

@Test func measuringTheTrashChangesNothingInIt() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent(".Trash/Setup.dmg")
    try write(file, bytes: 10_000)
    let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    _ = TrashSpace.measure(home: home)
    #expect(try Data(contentsOf: file) == Data(repeating: 3, count: 10_000))
    #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == before)
}

@Test func overviewSaysWhatTheTrashHoldsOnlyWhenItIsKnownAndNotEmpty() {
    #expect(TrashContents.empty.overviewText == nil)
    #expect(TrashContents.holds(2_400_000_000).overviewText == "Trash holds 2.4 GB")
    #expect(TrashContents.unknown.overviewText == nil)
}

/// #359: Overview names CacheDrop's own part of the Trash, from its recorded sizes; the whole Trash shows only when readable.
@Test func overviewNamesWhatCacheDropMovedToTheTrash() {
    #expect(TrashContents.holds(9_400_000_000).overviewText(fromCacheDrop: 7_100_000_000) == "Trash holds 9.4 GB · 7.1 GB from CacheDrop")
    #expect(TrashContents.unknown.overviewText(fromCacheDrop: 7_100_000_000) == "7.1 GB from CacheDrop")
    // Nothing of CacheDrop's left: the line is unchanged.
    #expect(TrashContents.holds(9_400_000_000).overviewText(fromCacheDrop: 0) == "Trash holds 9.4 GB")
    #expect(TrashContents.unknown.overviewText(fromCacheDrop: 0) == nil)
}

/// #359: Results says what CacheDrop's items hold in the Trash, never the whole Trash's size, and nothing when none is left.
@Test func resultsSayWhatIsInTheTrashUntilItIsEmptied() {
    #expect(TrashSpace.emptyHint(bytes: 7_100_000_000) == "7.1 GB is in the Trash. Empty it to free the space.")
    #expect(TrashSpace.emptyHint(bytes: 0) == nil)
}

private final class RecordingOpener: TrashOpening, @unchecked Sendable {
    var opened: [URL] = []
    func open(_ folder: URL) -> Bool { opened.append(folder); return true }
}

@Test func openTrashOpensTheTrashFolderInFinder() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let opener = RecordingOpener()
    #expect(TrashSpace.open(home: home, with: opener))
    #expect(opener.opened == [home.appendingPathComponent(".Trash", isDirectory: true)])
}

// SPEC section 2, Decision 68: CacheDrop never empties the Trash, and no cleanup acts on anything in it. Every path that
// could act on an item goes through discovery or a picked folder's listing, and then the check; each is held to that here.
// Deleting CacheDrop's own items from the Trash, when asked, is `TrashEmptying` (TrashEmptyingTests).

/// A home whose Trash holds what rules would otherwise take: an old installer, a large file and a cache folder.
private func homeWithAFullTrash(now: Date) throws -> URL {
    let home = try trashHome()
    let old = now.addingTimeInterval(-400 * 86_400)
    for (path, bytes) in [("Setup.dmg", 10), ("movie.mov", 10), ("_cacache/content-v2/blob", 5_000), ("Caches/com.example/data", 5_000)] {
        let url = home.appendingPathComponent(".Trash/" + path)
        try write(url, bytes: bytes)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: url.path)
        var times = [timeval(tv_sec: Int(old.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(old.timeIntervalSince1970), tv_usec: 0)]
        utimes(url.path, &times)
    }
    let movie = home.appendingPathComponent(".Trash/movie.mov")
    let handle = try FileHandle(forWritingTo: movie); try handle.truncate(atOffset: 600_000_000); try handle.close()
    return home
}
private func inTrash(_ url: URL, _ home: URL) -> Bool { url.standardizedFileURL.path.hasPrefix(home.appendingPathComponent(".Trash").path + "/") }

@Test func noCatalogRuleOffersAnythingInTheTrash() throws {
    let home = try homeWithAFullTrash(now: Date())
    defer { try? FileManager.default.removeItem(at: home) }
    let found = Catalog(rules: fixtureRules).discover(fixture: home)
    #expect(!found.contains { inTrash($0.url, home) })
}

@Test func aPickedFolderOffersNothingInTheTrashEvenWhenTheTrashIsThePickedFolder() async throws {
    let home = try homeWithAFullTrash(now: Date())
    defer { try? FileManager.default.removeItem(at: home) }
    for picked in [home, home.appendingPathComponent(".Trash"), home.appendingPathComponent(".Trash/_cacache")] {
        let scan = try await FolderScanner().scan(picked)
        let offered = UserFiles.candidates(in: scan, home: home)
        #expect(offered.isEmpty, "offered from \(picked.lastPathComponent): \(offered.map(\.url.lastPathComponent))")
    }
}

@Test func theCheckRefusesAnyItemInTheTrashSoNoRunEverActsOnIt() async throws {
    let now = Date()
    let home = try homeWithAFullTrash(now: now)
    defer { try? FileManager.default.removeItem(at: home) }
    let trash = home.appendingPathComponent(".Trash")
    let catalog = Catalog(rules: fixtureRules + [UserFiles.rule])
    let npm = try #require(catalog.rule("npm-cache"))
    func forged(_ rule: CleanupRule, _ path: String, under root: URL) -> Candidate {
        let url = trash.appendingPathComponent(path)
        var info = stat(); lstat(url.path, &info)
        return catalog.candidate(rule, url, info, logical: Int64(info.st_size), allocated: nil, complete: true, lastUsed: nil).found(under: root)
    }
    // Items a picked Trash folder, or one inside it, would hold; and a cache folder a rule might be pointed at.
    let candidates = [forged(UserFiles.rule, "movie.mov", under: trash), forged(UserFiles.rule, "Setup.dmg", under: trash),
                      forged(npm, "_cacache", under: trash.appendingPathComponent("_cacache")), forged(npm, "_cacache", under: home)]
    let check = CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FixtureNothingInUse(), cloud: FakeCloud())
    for candidate in candidates {
        #expect(check.check(candidate) == .protected(".Trash"), "\(candidate.ruleID) \(candidate.url.lastPathComponent)")
    }
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: candidates, dryRun: false))
    #expect(result.records.allSatisfy { $0.state == .skipped })
    for path in ["movie.mov", "Setup.dmg", "_cacache/content-v2/blob"] { #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent(path).path)) }
}
