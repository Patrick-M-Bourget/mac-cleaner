import Foundation
import Testing
import StillCore

// #159: Put back returns an item CacheDrop moved to the Trash to where it was. Every test uses a temp home whose
// `.Trash` stands in for the Finder Trash; the real Trash is never read or changed.

/// Moves items into the fixture home's `.Trash`, as Finder's Trash would.
private struct FixtureHomeTrash: TrashMoving {
    let home: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        let destination = home.appendingPathComponent(".Trash/" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
private struct Closed: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }

/// A fixture home with an empty `.Trash`, and one Downloads installer CacheDrop has moved to it.
private func trashedInstaller(named name: String = "Setup.dmg") async throws -> (home: URL, journal: SQLiteCleanupJournal, record: CleanupRecord) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillPutBack-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
    try Data(repeating: 4, count: 3_000).write(to: home.appendingPathComponent("Downloads/" + name))
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let executor = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: Catalog(rules: fixtureRules), running: Closed()), measure: { _ in nil },
                                   trash: FixtureHomeTrash(home: home))
    let result = await executor.execute(CatalogApproval(candidates: candidates, previewOnly: false))
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded && record.trashURL != nil)
    return (home, journal, record)
}

@Test func putBackRestoresTheItemToItsOriginalPathAndRecordsIt() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(record.canPutBack)

    let outcome = TrashPutBack(journal: journal).putBack(record)

    #expect(outcome == .restored(record.originalURL))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Downloads/Setup.dmg").path))
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/Setup.dmg").path))
    // Recorded in History: its own run, and the trashed item reads as put back.
    let history = try journal.completedHistory()
    let putBackRun = try #require(history.completedRuns.first { $0.isPutBack })
    #expect(putBackRun.title == "Put back from Trash")
    #expect(putBackRun.records.first?.outcomeTitle == "Put back")
    #expect(putBackRun.records.first?.putBackOf == record.id)
    #expect(history.putBackIDs == [record.id])
    let trashRun = try #require(history.completedRuns.first { $0.records.contains { $0.id == record.id } })
    #expect(trashRun.trashHeldAllocatedBytes == 0, "What was put back is no longer held in the Trash")
    // Once put back, it isn't offered again.
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.alreadyPutBack))
}

@Test func putBackNeverOverwritesWhatIsAtTheOriginalPathNow() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    let newer = Data(repeating: 9, count: 10)
    try newer.write(to: record.originalURL)

    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.originalTaken))
    #expect(PutBackRefusal.originalTaken.reason == "Something is already at its original location. Nothing was changed.")
    #expect(try Data(contentsOf: record.originalURL) == newer)
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/Setup.dmg").path))
    #expect(try journal.completedHistory().putBackIDs.isEmpty)
}

@Test func putBackRefusesAnItemNoLongerInTheTrash() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    // The user emptied the Trash, or moved the item out of it themselves.
    try FileManager.default.moveItem(at: home.appendingPathComponent(".Trash/Setup.dmg"), to: home.appendingPathComponent("Elsewhere.dmg"))

    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.notInTrash))
    #expect(!FileManager.default.fileExists(atPath: record.originalURL.path))
}

@Test func putBackRefusesAnItemThatChangedInTheTrash() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    let inTrash = home.appendingPathComponent(".Trash/Setup.dmg")
    // Another item of the same name took its place in the Trash.
    try FileManager.default.removeItem(at: inTrash)
    try Data(repeating: 1, count: 3_000).write(to: inTrash)
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.changed))
    #expect(FileManager.default.fileExists(atPath: inTrash.path))
    #expect(!FileManager.default.fileExists(atPath: record.originalURL.path))
}

@Test func putBackRefusesAnItemEditedInTheTrash() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    let inTrash = home.appendingPathComponent(".Trash/Setup.dmg")
    let handle = try FileHandle(forWritingTo: inTrash)
    try handle.seekToEnd(); try handle.write(contentsOf: Data([1])); try handle.close()
    var later = [timeval(tv_sec: 2_000_000_000, tv_usec: 0), timeval(tv_sec: 2_000_000_000, tv_usec: 0)]
    #expect(utimes(inTrash.path, &later) == 0)
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.changed))
    #expect(FileManager.default.fileExists(atPath: inTrash.path))
}

@Test func putBackRefusesWhenTheOriginalFolderIsGone() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.removeItem(at: home.appendingPathComponent("Downloads"))
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.originalFolderMissing))
    // A new folder of the same name, or a symlink to one elsewhere, is not the folder it came from.
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Elsewhere"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Downloads"), withDestinationURL: home.appendingPathComponent("Elsewhere"))
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.originalFolderMissing))
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Elsewhere/Setup.dmg").path))
    try FileManager.default.removeItem(at: home.appendingPathComponent("Downloads"))
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.originalFolderMissing))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/Setup.dmg").path))
}

@Test func onlyItemsMovedToTheTrashCanBePutBack() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    let records = try journal.records()
    // A dry-run record and a record whose recorded Trash location isn't in a Trash are never put back.
    var preview = record; preview.previewOnly = true
    var outside = record; outside.trashURL = home.appendingPathComponent("Downloads/Elsewhere.dmg")
    for refused in [preview, outside] {
        #expect(!refused.canPutBack)
        #expect(TrashPutBack(journal: journal).putBack(refused) == .refused(.notPutBackable))
    }
    #expect(try journal.records().count == records.count, "A refusal before acting writes nothing")
}

// SPEC section 2: CacheDrop never empties the Trash and never deletes anything from it. Put back only ever renames one
// item out of it; every refusal leaves the Trash exactly as it was.
@Test func putBackNeverDeletesAnythingFromTheTrash() async throws {
    let (home, journal, record) = try await trashedInstaller()
    defer { try? FileManager.default.removeItem(at: home) }
    let trash = home.appendingPathComponent(".Trash")
    try Data(repeating: 2, count: 50).write(to: trash.appendingPathComponent("Other.dmg"))
    try FileManager.default.createDirectory(at: trash.appendingPathComponent("Folder"), withIntermediateDirectories: true)
    try Data(repeating: 3, count: 50).write(to: trash.appendingPathComponent("Folder/notes.txt"))
    func trashListing() throws -> [String: Data] {
        var listing: [String: Data] = [:]
        let enumerator = try #require(FileManager.default.enumerator(atPath: trash.path))
        for case let path as String in enumerator {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: trash.appendingPathComponent(path).path, isDirectory: &isDirectory)
            listing[path] = isDirectory.boolValue ? Data() : try Data(contentsOf: trash.appendingPathComponent(path))
        }
        return listing
    }
    let before = try trashListing()

    // Refused: something is at the original path. Nothing in the Trash changes.
    try Data([1]).write(to: record.originalURL)
    #expect(TrashPutBack(journal: journal).putBack(record) == .refused(.originalTaken))
    #expect(try trashListing() == before)

    // Refused: the recorded original lies inside the Trash, so put back would only move things around in it.
    var intoTrash = record
    intoTrash = try intoTrash.withOriginal(trash.appendingPathComponent("Folder/Setup.dmg"))
    #expect(TrashPutBack(journal: journal).putBack(intoTrash) == .refused(.notPutBackable))
    #expect(try trashListing() == before)

    // Restored: exactly one item leaves the Trash, and everything else in it is untouched.
    try FileManager.default.removeItem(at: record.originalURL)
    #expect(TrashPutBack(journal: journal).putBack(record) == .restored(record.originalURL))
    var expected = before; expected["Setup.dmg"] = nil
    #expect(try trashListing() == expected)
}

@Test func journalsWrittenBeforePutBackStillDecode() throws {
    // The record shape before #159 has no put-back field; decoding must not need one.
    let json = #"{"action":"moveToTrash","allocatedBytes":4096,"approvedAt":814724718.878114,"batchID":"FD8FB579-0EB5-4CC1-925B-F038F4B44EEB","id":"x","logicalBytes":3,"message":"Moved to Trash","modifiedNanoseconds":0,"modifiedSeconds":1,"observedAt":814724718.877688,"originalURL":"file:\/\/\/private\/tmp\/StillLegacy\/Setup.dmg","policyVersion":2,"resourceID":"1:2","scopeResourceID":"1:3","scopeURL":"file:\/\/\/private\/tmp\/StillLegacy\/","state":"succeeded","trashURL":"file:\/\/\/Users\/someone\/.Trash\/Setup.dmg"}"#
    let record = try JSONDecoder().decode(CleanupRecord.self, from: Data(json.utf8))
    #expect(record.putBackOf == nil)
    #expect(!record.isPutBack)
    #expect(record.canPutBack)
}

private extension CleanupRecord {
    /// The same record with another recorded original location, through its stored form.
    func withOriginal(_ url: URL) throws -> CleanupRecord {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any])
        object["originalURL"] = url.absoluteString
        return try JSONDecoder().decode(CleanupRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
