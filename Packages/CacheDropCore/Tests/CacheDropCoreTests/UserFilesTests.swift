import Foundation
import Testing
@testable import CacheDropCore

/// A temp folder standing in for one the user picked; tests never scan real user folders.
private func pickedFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropPicked-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return URL(fileURLWithPath: try #require(realPath(folder.path)))
}
private let day: TimeInterval = 86_400
private let megabyte: Int64 = 1_000_000
/// Large, for these tests: files that really take 500 MB on disk would make each test slow (#394). Sizes below are scaled to it.
private let large: Int64 = 5 * megabyte
/// Writes a file of `size` bytes last opened, changed and created `age` ago. A large one takes its size on disk through
/// preallocation, without writing it; `sparse` leaves it taking almost nothing, as a VM disk image does (#394).
@discardableResult
private func file(_ folder: URL, _ path: String, size: Int64 = 10, sparse: Bool = false, age: TimeInterval = 0, now: Date) throws -> URL {
    let url = folder.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: Int(min(size, 10))))
    if size > 10 {
        let fd = open(url.path, O_RDWR)
        defer { close(fd) }
        if !sparse {
            var store = fstore_t(fst_flags: UInt32(F_ALLOCATEALL), fst_posmode: F_PEOFPOSMODE, fst_offset: 0, fst_length: off_t(size), fst_bytesalloc: 0)
            #expect(fcntl(fd, F_PREALLOCATE, &store) == 0)
        }
        #expect(ftruncate(fd, off_t(size)) == 0)
    }
    let date = now.addingTimeInterval(-age)
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
    return url
}
/// The picked folder's files as the explorer offers them, relative to the folder.
private func offered(_ folder: URL, now: Date, rule: CleanupRule = UserFiles.rule, exclusions: ExclusionPolicy = ExclusionPolicy()) async throws -> [String: Candidate] {
    let scan = try await FolderScanner().scan(folder)
    let found = UserFiles.candidates(in: scan, rule: rule, exclusions: exclusions, home: fixtureNoHome, now: now, large: large)
    return Dictionary(uniqueKeysWithValues: found.map { (String($0.url.path.dropFirst(folder.path.count + 1)), $0) })
}

@Test func aPickedFolderOffersLargeFilesAndFilesNotOpenedIn90DaysForTrash() async throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    try file(folder, "movie.mov", size: 6 * megabyte, age: 5 * day, now: now)
    try file(folder, "old/report.pdf", size: 2 * megabyte, age: 200 * day, now: now)
    try file(folder, "recent.txt", age: 10 * day, now: now)
    try file(folder, "almost-large.bin", size: 4_990_000, age: 10 * day, now: now)

    let found = try await offered(folder, now: now)
    #expect(Set(found.keys) == ["movie.mov", "old/report.pdf"])
    #expect(found.values.allSatisfy { $0.ruleID == "user-files" && $0.action == .trash && !$0.isDirectory && $0.sizeComplete })
    #expect(found["movie.mov"]?.logicalBytes == 6 * megabyte)
    let lastUsed = try #require(found["old/report.pdf"]?.lastUsed)
    #expect(abs(lastUsed.timeIntervalSince(now.addingTimeInterval(-200 * day))) < 2)
    #expect(found["movie.mov"]?.lastUsed != nil)
}

/// #394: "large" is what a file takes on disk. A sparse disk image (a VM's, large logical size, little used) isn't large, and the
/// list sorts by on-disk size.
@Test func aSparseDiskImageIsNotLargeAndTheListSortsByOnDiskSize() async throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    try file(folder, "VM.raw", size: 40 * megabyte, sparse: true, age: 5 * day, now: now)
    try file(folder, "movie.mov", size: 6 * megabyte, age: 5 * day, now: now)
    try file(folder, "Old VM.raw", size: 40 * megabyte, sparse: true, age: 200 * day, now: now)
    try file(folder, "old/report.pdf", size: 2 * megabyte, age: 200 * day, now: now)

    let scan = try await FolderScanner().scan(folder)
    let found = UserFiles.candidates(in: scan, home: fixtureNoHome, now: now, large: large).map { String($0.url.path.dropFirst(folder.path.count + 1)) }
    // The old sparse image is still offered for its age, sorted by what it takes on disk: last.
    #expect(found == ["movie.mov", "old/report.pdf", "Old VM.raw"])
}

@Test func protectedExtensionsGitCheckoutsAndExclusionsAreNeverOffered() async throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date(), old = 200 * day
    try file(folder, "keep.mov", age: old, now: now)
    try file(folder, "Notes.sqlite", age: old, now: now)
    try file(folder, "Logic.band", age: old, now: now)
    try file(folder, "project/.git/objects/pack.bin", age: old, now: now)
    try file(folder, "project/assets/big.psd", size: 6 * megabyte, now: now)
    try file(folder, "a/deep/repo/.git/HEAD", now: now)
    try file(folder, "a/deep/repo/sub/old.bin", age: old, now: now)
    try file(folder, "private/old.txt", age: old, now: now)
    let excluded = ExclusionPolicy(rules: [try ExclusionRule.capture(folder.appendingPathComponent("private"))])

    let found = try await offered(folder, now: now, exclusions: excluded)
    #expect(Set(found.keys) == ["keep.mov"])
}

@Test func aPickedFolderInsideAGitCheckoutOffersNothing() async throws {
    let repo = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: repo) }
    try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try file(repo, "build/huge.bin", size: 6 * megabyte, now: Date())
    #expect(try await offered(repo.appendingPathComponent("build"), now: Date()).isEmpty)
}

/// Stands in for the Finder Trash so tests never touch the user's real Trash.
private func executor(trash: URL) -> CleanupExecutor {
    let journal = try! SQLiteCleanupJournal(url: trash.deletingLastPathComponent().appendingPathComponent("journal-\(UUID()).sqlite"))
    return CleanupExecutor(journal: journal, check: CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FixtureNothingRunning()), measure: { _ in nil }, trash: FixtureFolderTrash(folder: trash))
}

@Test func chosenFilesFromAPickedFolderGoToTrashAndOthersStay() async throws {
    let folder = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: trash) }
    let now = Date()
    let movie = try file(folder, "movie.mov", size: 6 * megabyte, now: now)
    let other = try file(folder, "other.mov", size: 7 * megabyte, now: now)
    let found = try await offered(folder, now: now)
    let chosen = try #require(found["movie.mov"])

    let result = await executor(trash: trash).execute(CatalogApproval(candidates: [chosen], dryRun: false))
    #expect(result.records.map(\.state) == [.succeeded])
    #expect(result.records.first?.action == "moveToTrash")
    #expect(result.records.first?.trashURL == trash.appendingPathComponent("movie.mov"))
    #expect(!FileManager.default.fileExists(atPath: movie.path))
    #expect(FileManager.default.fileExists(atPath: other.path))
    #expect(result.movedToTrashBytes == chosen.allocatedBytes)
}

@Test func dryRunLeavesPickedFilesInPlace() async throws {
    let folder = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: trash) }
    let movie = try file(folder, "movie.mov", size: 6 * megabyte, now: Date())
    let found = try await offered(folder, now: Date())

    let result = await executor(trash: trash).execute(CatalogApproval(candidates: Array(found.values), dryRun: true))
    #expect(result.records.map(\.state) == [.skipped])
    #expect(result.records.first?.message.hasPrefix("Dry run: would move to Trash") == true)
    #expect(FileManager.default.fileExists(atPath: movie.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
}

@Test func aFileThatJoinedAGitCheckoutAfterTheScanIsSkipped() async throws {
    let folder = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: trash) }
    let movie = try file(folder, "work/movie.mov", size: 6 * megabyte, now: Date())
    let chosen = try #require(try await offered(folder, now: Date())["work/movie.mov"])
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("work/.git"), withIntermediateDirectories: true)

    let result = await executor(trash: trash).execute(CatalogApproval(candidates: [chosen], dryRun: false))
    #expect(result.records.map(\.state) == [.skipped])
    #expect(result.records.first?.message == CheckRefusal.protected(".git").reason)
    #expect(FileManager.default.fileExists(atPath: movie.path))
}

@Test func nothingInsideTheHomeLibraryIsOfferedOrActedOn() async throws {
    let home = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: trash) }
    let cookies = try file(home, "Library/Application Support/Browser/Default/Cookies", age: 200 * day, now: Date())
    try file(home, "Documents/old.key", age: 200 * day, now: Date())
    let scan = try await FolderScanner().scan(home)
    let found = UserFiles.candidates(in: scan, home: home, now: Date())
    #expect(found.map(\.url.lastPathComponent) == ["old.key"])

    // A candidate from before the rule applied is refused just before acting.
    let fromEarlierScan = try #require(UserFiles.candidates(in: scan, home: trash, now: Date()).first { $0.url == cookies })
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FixtureNothingRunning(), home: home)
    #expect(check.check(fromEarlierScan) == .protected("Library"))
}

@Test func aPickedFolderThatJoinedAGitCheckoutAboveItAfterTheScanIsSkipped() async throws {
    let outer = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: outer); try? FileManager.default.removeItem(at: trash) }
    let picked = outer.appendingPathComponent("build")
    let movie = try file(picked, "movie.mov", size: 6 * megabyte, now: Date())
    let chosen = try #require(try await offered(picked, now: Date())["movie.mov"])
    // The check just before acting looks above the picked folder, as discovery does.
    try FileManager.default.createDirectory(at: outer.appendingPathComponent(".git"), withIntermediateDirectories: true)

    let result = await executor(trash: trash).execute(CatalogApproval(candidates: [chosen], dryRun: false))
    #expect(result.records.map(\.state) == [.skipped])
    #expect(result.records.first?.message == CheckRefusal.protected(".git").reason)
    #expect(FileManager.default.fileExists(atPath: movie.path))
}

/// #125: a cleanup run removes from the explorer only the picked files it acted on; the rest stay offered.
@Test func aRunKeepsOfferingThePickedFilesItDidNotActOn() async throws {
    let folder = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: trash) }
    let now = Date()
    try file(folder, "movie.mov", size: 6 * megabyte, now: now)
    try file(folder, "other.mov", size: 7 * megabyte, now: now)
    let found = try await offered(folder, now: now)
    let movie = try #require(found["movie.mov"]), other = try #require(found["other.mov"])

    let result = await executor(trash: trash).execute(CatalogApproval(candidates: [movie], dryRun: false))
    #expect(UserFiles.remaining([movie, other], after: result) == [other])
}

@Test func aPreviewRunKeepsOfferingEveryPickedFile() async throws {
    let folder = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: trash) }
    try file(folder, "movie.mov", size: 6 * megabyte, now: Date())
    let movie = try #require(try await offered(folder, now: Date())["movie.mov"])

    let result = await executor(trash: trash).execute(CatalogApproval(candidates: [movie], dryRun: true))
    #expect(UserFiles.remaining([movie], after: result) == [movie])
}
