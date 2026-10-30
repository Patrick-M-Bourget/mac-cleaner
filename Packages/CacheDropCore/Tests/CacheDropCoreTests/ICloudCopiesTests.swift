import Foundation
import Testing
@testable import CacheDropCore

/// A temp home whose iCloud Drive folder holds plain fixture files; their iCloud state comes from a `FakeCloud`.
private func cloudHome() throws -> (home: URL, drive: URL) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCloud-\(UUID())").resolvingSymlinksInPath()
    let drive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
    return (home.resolvingSymlinksInPath(), drive.resolvingSymlinksInPath())
}
@discardableResult private func write(_ url: URL, bytes: Int = 5000) throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: bytes).write(to: url)
    return url
}
private func state(downloaded: CloudDownloadState = .current, uploaded: Bool? = true, uploading: Bool? = false, conflicts: Bool? = false, pinned: Bool? = false) -> CloudMetadata {
    CloudMetadata(membership: true, downloadState: downloaded, uploaded: uploaded, uploading: uploading, downloading: false, conflicts: conflicts, pinned: pinned)
}

@Test func onlyUploadedSettledLocalCopiesNotKeptDownloadedAreOffered() throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cloud = FakeCloud()
    cloud.set(try write(drive.appendingPathComponent("ready.pdf")), state())
    cloud.set(try write(drive.appendingPathComponent("pinned.pdf")), state(pinned: true))
    cloud.set(try write(drive.appendingPathComponent("pin-unknown.pdf")), state(pinned: nil))
    cloud.set(try write(drive.appendingPathComponent("not-uploaded.mov")), state(uploaded: false))
    cloud.set(try write(drive.appendingPathComponent("uploading.mov")), state(uploading: true))
    cloud.set(try write(drive.appendingPathComponent("conflicted.key")), state(conflicts: true))
    cloud.set(try write(drive.appendingPathComponent("placeholder.zip")), state(downloaded: .notDownloaded))
    try write(drive.appendingPathComponent("unknown.txt"))
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud)
    #expect(candidates.map(\.url.lastPathComponent) == ["ready.pdf"])
    let candidate = try #require(candidates.first)
    #expect(candidate.ruleID == "icloud-local-copies")
    #expect(candidate.action == .evict)
    #expect(candidate.logicalBytes == 5000)
    #expect((candidate.allocatedBytes ?? 0) >= 5000)
    #expect(candidate.sizeComplete)
}

@Test func aFolderIsOfferedForTheLocalCopiesInsideItThatCanBeRemoved() throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = drive.appendingPathComponent("Projects")
    let cloud = FakeCloud()
    cloud.set(try write(folder.appendingPathComponent("a.psd"), bytes: 4000), state())
    cloud.set(try write(folder.appendingPathComponent("deep/b.mov"), bytes: 6000), state())
    cloud.set(try write(folder.appendingPathComponent("deep/kept.mov"), bytes: 9000), state(pinned: true))
    cloud.set(try write(folder.appendingPathComponent("repo/.git/HEAD"), bytes: 7000), state())
    let package = folder.appendingPathComponent("Talk.key")
    try write(package.appendingPathComponent("Index.zip"), bytes: 2000)
    cloud.set(package, state())
    let candidate = try #require(Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud).first)
    #expect(candidate.url.path == folder.path)
    #expect(candidate.isDirectory)
    #expect(candidate.logicalBytes == 12_000)
    // A folder whose every local copy must stay isn't offered.
    cloud.set(folder.appendingPathComponent("a.psd"), state(conflicts: true))
    cloud.set(folder.appendingPathComponent("deep/b.mov"), state(uploaded: false))
    cloud.set(package, state(downloaded: .notDownloaded))
    #expect(Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud).isEmpty)
}

@Test func scanningReadsOnlyMetadataWithDownloadsBlockedAndChangesNothing() throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cloud = FakeCloud()
    cloud.set(try write(drive.appendingPathComponent("ready.pdf")), state())
    cloud.set(try write(drive.appendingPathComponent("Folder/inside.pdf")), state())
    cloud.set(try write(drive.appendingPathComponent("Folder/placeholder.pdf")), state(downloaded: .notDownloaded))
    let before = try Data(contentsOf: drive.appendingPathComponent("ready.pdf"))
    #expect(Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud).count == 2)
    #expect(cloud.downloadableReads.isEmpty)
    #expect(cloud.evicted.isEmpty)
    #expect(try Data(contentsOf: drive.appendingPathComponent("ready.pdf")) == before)
    // The policy is the calling thread's own and is restored afterwards.
    #expect(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) != IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
}

@Test func theCheckJustBeforeActingRefusesCopiesThatMustNowStay() throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = try write(drive.appendingPathComponent("ready.pdf"))
    let cloud = FakeCloud([file: state()])
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home, cloud: cloud).first)
    let check = CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), cloud: cloud)
    #expect(check.check(candidate) == nil)
    let cases: [(CloudMetadata, CheckRefusal)] = [
        (state(pinned: true), .keptDownloaded), (state(pinned: nil), .cloudUnknown), (state(uploaded: false), .notUploaded),
        (state(uploading: true), .notUploaded), (state(conflicts: true), .conflicted), (state(downloaded: .notDownloaded), .notDownloaded), (.unknown, .cloudUnknown),
    ]
    for (now, refusal) in cases {
        cloud.set(file, now)
        #expect(check.check(candidate) == refusal)
    }
    #expect(CheckRefusal.keptDownloaded.reason == "Set to Keep Downloaded. Its local copy stays.")
    #expect(cloud.downloadableReads.isEmpty)
}

/// Available space that grows by what each removal frees.
private func evictor(_ home: URL, cloud: FakeCloud, volume: FixtureVolume = FixtureVolume()) throws -> CleanupExecutor {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: FixtureNothingRunning(), cloud: cloud)
    return CleanupExecutor(journal: journal, check: check, measure: volume.read, trash: TrashNeverUsed())
}

@Test func evictingRemovesOnlyLocalCopiesAndMeasuresFreedSpace() async throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = try write(drive.appendingPathComponent("ready.pdf"))
    let inside = [try write(drive.appendingPathComponent("Folder/a.pdf")), try write(drive.appendingPathComponent("Folder/deep/b.pdf"))]
    let kept = try write(drive.appendingPathComponent("Folder/kept.pdf"))
    let cloud = FakeCloud([file: state(), inside[0]: state(), inside[1]: state(), kept: state(pinned: true)])
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud)
    #expect(candidates.count == 2)
    let volume = FixtureVolume()
    volume.freedPerRead = [0, 8192, 0, 4096]
    let result = try await evictor(home, cloud: cloud, volume: volume).execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.succeeded, .succeeded])
    #expect(Set(cloud.evicted) == Set(([file] + inside).map(\.path)))
    #expect(result.records.map(\.action) == ["evict", "evict"])
    #expect(result.records.map(\.outcomeTitle) == ["Removed local copy", "Removed local copy"])
    #expect(result.records[0].message == "Removed local copies of 2 files. The originals stay in iCloud.")
    #expect(result.records[1].message == "Removed local copy. The original stays in iCloud.")
    #expect(result.measuredFreedBytes == 12_288)
    #expect(result.movedToTrashBytes == 0)
    #expect(cloud.downloadableReads.isEmpty)
    let history = try #require(CleanupHistorySnapshot(records: try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite")).records()).completedRuns.first)
    #expect(history.title == "Cleanup · Removed local iCloud copies")
}

@Test func previewOnlyListsWhatWouldBeEvictedAndChangesNothing() async throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = try write(drive.appendingPathComponent("ready.pdf"))
    let cloud = FakeCloud([file: state()])
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud)
    let result = try await evictor(home, cloud: cloud).execute(CatalogApproval(candidates: candidates, previewOnly: true))
    let record = try #require(result.records.first)
    #expect(cloud.evicted.isEmpty)
    #expect(record.state == .skipped)
    #expect(record.message.hasPrefix("Dry run: would remove the local copy"))
    #expect(record.outcomeTitle == "Would remove local copy")
    #expect(result.measuredFreedBytes == nil)
}

@Test func aCopyThatMustNowStayIsSkippedAndAFailedEvictionIsReported() async throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let pinned = try write(drive.appendingPathComponent("a.pdf")), failing = try write(drive.appendingPathComponent("b.pdf"))
    let cloud = FakeCloud([pinned: state(), failing: state()])
    let candidates = Catalog(rules: fixtureRules).discover(fixture: home, cloud: cloud)
    cloud.set(pinned, state(pinned: true))
    cloud.evictionError = CocoaError(.fileWriteUnknown)
    let result = try await evictor(home, cloud: cloud).execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.skipped, .failed])
    #expect(result.records[0].message == CheckRefusal.keptDownloaded.reason)
    #expect(result.records[1].message == "Couldn’t remove the local copy. Nothing was changed.")
    #expect(cloud.evicted.isEmpty)
}

@Test func historyAndRecoverySayAnEvictionNeverDeletesTheOriginal() throws {
    let (home, drive) = try cloudHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = try write(drive.appendingPathComponent("ready.pdf"))
    let candidate = try #require(Catalog(rules: fixtureRules).discover(fixture: home, cloud: FakeCloud([file: state()])).first)
    var record = CleanupRecord(batchID: UUID(), approvedAt: Date(), candidate: candidate, previewOnly: false)
    #expect(record.actionTitle == "Remove local copy")
    record.state = .intent
    #expect(record.recoveryStateText == "Unfinished · Local copies may be removed · The original stays in iCloud")
    record.state = .failed; record.partlyRemoved = true
    #expect(record.outcomeTitle == "Partly removed local copies")
    #expect(record.recoveryStateText == "Failed · Some local copies were removed · The originals stay in iCloud")
    #expect(CleanupHistoryRun(id: record.batchID, records: [record]).title == "Cleanup · Partly removed local iCloud copies")
}
