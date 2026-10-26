import Foundation
import Testing
@testable import StillCore

/// A temp stand-in for the user's own `/private/var/folders/<xx>/<id>` folder, with its `T`, `C` and `X` folders.
/// Never the real one.
private func fixtureUserFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StillVarFolders-\(UUID())")
    for name in ["T", "C", "X"] { try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true) }
    return folder.resolvingSymlinksInPath()
}
/// The scan runs 10 days from now, so items created by the test count as changed 10 days before it.
private let now = Date().addingTimeInterval(10 * 86_400)
private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

/// A file of `bytes`, last modified `modified`.
@discardableResult
private func writeFile(_ relative: String, in folder: URL, modified: Date, bytes: Int = 8192) throws -> URL {
    let url = folder.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    return url
}
/// Sets the modification date of `relative` and everything inside it.
private func age(_ relative: String, in folder: URL, to date: Date) throws {
    let url = folder.appendingPathComponent(relative)
    let inside = FileManager.default.enumerator(atPath: url.path)?.allObjects as? [String] ?? []
    for path in inside.reversed() { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.appendingPathComponent(path).path) }
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}
/// Says which items are open, or that it can't tell.
private struct FakeInUse: InUseChecking {
    var open: Set<String> = []
    var unknown = false
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? {
        unknown ? nil : Set(folders.map(\.path)).intersection(open)
    }
}
private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }
private let catalog = Catalog(rules: fixtureRules)
private func fixtureHome() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalog-\(UUID())") }
private func temporaryFiles(_ candidates: [Candidate]) -> [String] {
    candidates.filter { $0.ruleID == "temporary-files" }.map(\.url.path).sorted()
}

@Test func oldItemsInTheTempAndCacheFoldersAreOfferedButNotRecentOrMacOSOnes() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let oldFile = try writeFile("T/old-download.tmp", in: folder, modified: daysAgo(30))
    try writeFile("C/old.cache/blob", in: folder, modified: daysAgo(30))
    try age("C/old.cache", in: folder, to: daysAgo(30))
    try writeFile("T/recent.tmp", in: folder, modified: daysAgo(1))
    try writeFile("T/com.apple.something/blob", in: folder, modified: daysAgo(30))
    try age("T/com.apple.something", in: folder, to: daysAgo(30))
    try writeFile("T/.hidden", in: folder, modified: daysAgo(30))
    try writeFile("T/empty.lock", in: folder, modified: daysAgo(30), bytes: 0)
    try writeFile("X/other/blob", in: folder, modified: daysAgo(30))
    try age("X/other", in: folder, to: daysAgo(30))
    let candidates = catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)
    #expect(temporaryFiles(candidates) == [folder.appendingPathComponent("C/old.cache").path, oldFile.path])
    let rule = try #require(catalog.rule("temporary-files"))
    #expect(rule.category == .system && rule.action == .delete && rule.base == .userFolder)
    #expect(candidates.filter { $0.ruleID == "temporary-files" }.allSatisfy { ($0.allocatedBytes ?? 0) >= 8192 })
}

@Test func anItemAProcessHasOpenIsNeverOfferedAndWhenUseCantBeCheckedNothingIs() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let open = try writeFile("T/open.tmp", in: folder, modified: daysAgo(30))
    let idle = try writeFile("C/idle.bin", in: folder, modified: daysAgo(30))
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), userFolder: folder, inUse: FakeInUse(open: [open.path]), now: now)) == [idle.path])
    let discovery = catalog.discovery(fixture: fixtureHome(), userFolder: folder, inUse: FakeInUse(unknown: true), now: now)
    #expect(temporaryFiles(discovery.candidates).isEmpty)
    #expect(discovery.notes.contains(CatalogNote(ruleID: "temporary-files", text: "Old temporary files: kept all, because Still couldn’t tell which ones apps are using.")))
}

@Test func aFolderWithAnythingChangedInsideRecentlyIsNotOffered() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeFile("T/session/old/blob", in: folder, modified: daysAgo(30))
    try age("T/session", in: folder, to: daysAgo(30))
    try writeFile("T/session/old/fresh", in: folder, modified: daysAgo(1))
    try FileManager.default.setAttributes([.modificationDate: daysAgo(30)], ofItemAtPath: folder.appendingPathComponent("T/session/old").path)
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)).isEmpty)
    // Exactly at the limit is still too recent; a moment older is offered.
    try FileManager.default.removeItem(at: folder.appendingPathComponent("T/session/old/fresh"))
    try age("T/session", in: folder, to: daysAgo(3).addingTimeInterval(1))
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)).isEmpty)
    try age("T/session", in: folder, to: daysAgo(3).addingTimeInterval(-60))
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)) == [folder.appendingPathComponent("T/session").path])
}

@Test func withoutTheUserFolderNoTemporaryFilesAreLookedFor() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeFile("T/old.tmp", in: folder, modified: daysAgo(30))
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), now: now)).isEmpty)
}

@Test func anItemOpenedOrChangedSinceTheScanIsRefusedJustBeforeActing() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeFile("T/job/blob", in: folder, modified: daysAgo(30))
    try age("T/job", in: folder, to: daysAgo(30))
    let candidate = try #require(catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now).first { $0.ruleID == "temporary-files" })
    let home = fixtureHome()
    func check(_ inUse: FakeInUse) -> CheckRefusal? { CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: inUse, home: home).check(candidate) }
    #expect(check(FakeInUse()) == nil)
    let refusal = check(FakeInUse(open: [candidate.url.path]))
    #expect(refusal == .inUse("An app"))
    #expect(refusal?.reason == "An app is using it. It is kept.")
    #expect(check(FakeInUse(unknown: true)) == .inUseUnknown("An app"))
    // A file written inside after the scan means it's in use again.
    Thread.sleep(forTimeInterval: 0.01)
    try Data([1]).write(to: candidate.url.appendingPathComponent("new"))
    #expect(check(FakeInUse()) == .changed)
}

/// Available space grows by what each deleted item really frees.
private final class FakeVolume: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Int64 = 1_000_000
    var freedPerRead: [Int64] = []
    func read(_ url: URL) -> CapacitySample? {
        lock.lock(); defer { lock.unlock() }
        if !freedPerRead.isEmpty { available += freedPerRead.removeFirst() }
        return CapacitySample(available: available, total: 10_000_000, volumeID: "fake-volume", metric: .important, date: Date())
    }
}

@Test func deletingTemporaryFilesReportsMeasuredFreedSpace() async throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = try writeFile("T/old.tmp", in: folder, modified: daysAgo(30))
    try writeFile("C/old.cache/blob", in: folder, modified: daysAgo(30))
    try age("C/old.cache", in: folder, to: daysAgo(30))
    let recent = try writeFile("T/recent.tmp", in: folder, modified: daysAgo(1))
    let candidates = catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now).filter { $0.ruleID == "temporary-files" }
    #expect(candidates.count == 2)
    let volume = FakeVolume()
    volume.freedPerRead = [0, 8192, 0, 12_288]
    let journal = try SQLiteCleanupJournal(url: folder.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: FakeInUse(), home: fixtureHome())
    let run = CleanupExecutor(journal: journal, check: check, measure: volume.read, trash: TrashNeverUsed())
    let result = await run.execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.succeeded, .succeeded])
    #expect(result.measuredFreedBytes == 20_480)
    #expect(!FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("C/old.cache").path))
    #expect(FileManager.default.fileExists(atPath: recent.path))
}

@Test func theSystemCheckerSeesATempFileAnyProcessOfTheUsersHasOpen() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opened = try writeFile("T/open.tmp", in: folder, modified: daysAgo(30))
    let mapped = try writeFile("T/mapped.tmp", in: folder, modified: daysAgo(30))
    let idle = try writeFile("C/idle.bin", in: folder, modified: daysAgo(30))
    let descriptor = Darwin.open(opened.path, O_RDONLY)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    let mapping = try Data(contentsOf: mapped, options: .alwaysMapped)
    let used = SystemInUseChecker().inUse([opened, mapped, idle], by: .anyApp)
    #expect(used == [opened.path, mapped.path])
    #expect(mapping.count == 8192)
}
