import Foundation
import Testing
@testable import CacheDropCore

/// A temp stand-in for the user's own `/private/var/folders/<xx>/<id>` folder, with its `T`, `C` and `X` folders.
/// Never the real one.
private func fixtureUserFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropVarFolders-\(UUID())")
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
/// One installed app, so a `C` folder named after it has an owner.
private struct OneApp: AppLookup {
    func app(bundleID: String) -> InstalledApp? {
        bundleID == "com.example.editor" ? InstalledApp(name: "Editor", bundleID: bundleID, path: "/Applications/Editor-\(UUID()).app") : nil
    }
    func app(updaterCacheDirName name: String) -> InstalledApp? { nil }
}
private let catalog = Catalog(rules: BuiltInCatalog.rules(apps: OneApp()))
private func fixtureHome() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())") }
private func temporaryFiles(_ candidates: [Candidate]) -> [String] {
    candidates.filter { $0.ruleID.hasPrefix("temporary-") }.map(\.url.path).sorted()
}

@Test func oldItemsInTheTempAndCacheFoldersAreOfferedButNotRecentOrMacOSOnes() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let oldFile = try writeFile("T/old-download.tmp", in: folder, modified: daysAgo(30))
    try writeFile("T/old.session/blob", in: folder, modified: daysAgo(30))
    try age("T/old.session", in: folder, to: daysAgo(30))
    try writeFile("T/recent.tmp", in: folder, modified: daysAgo(1))
    try writeFile("T/com.apple.something/blob", in: folder, modified: daysAgo(30))
    try age("T/com.apple.something", in: folder, to: daysAgo(30))
    try writeFile("T/.hidden", in: folder, modified: daysAgo(30))
    try writeFile("T/empty.lock", in: folder, modified: daysAgo(30), bytes: 0)
    try writeFile("X/other/blob", in: folder, modified: daysAgo(30))
    try age("X/other", in: folder, to: daysAgo(30))
    let candidates = catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)
    #expect(temporaryFiles(candidates) == [oldFile.path, folder.appendingPathComponent("T/old.session").path])
    let rule = try #require(catalog.rule("temporary-files"))
    #expect(rule.category == .system && rule.action == .delete && rule.base == .userFolder)
    #expect(candidates.filter { $0.ruleID == "temporary-files" }.allSatisfy { ($0.allocatedBytes ?? 0) >= 8192 })
}

@Test func inTheCacheFolderOnlyAnInstalledAppsOldCacheIsOffered() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["com.example.editor", "com.example.uninstalled", "assessmentagent", "clang", "com.apple.metal", "AudioComponentRegistrar"] {
        try writeFile("C/\(name)/blob", in: folder, modified: daysAgo(30))
        try age("C/" + name, in: folder, to: daysAgo(30))
    }
    let candidates = catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)
    #expect(temporaryFiles(candidates) == [folder.appendingPathComponent("C/com.example.editor").path])
    let found = try #require(candidates.first { $0.ruleID == "temporary-app-caches" })
    #expect(found.appName == "Editor")
    // Its app must be closed, as for any app cache; a running or unknown one refuses it.
    struct Running: RunningAppChecking { let answer: Bool?; func isRunning(_ owner: RuleOwner) -> Bool? { owner.name == "Editor" ? answer : false } }
    let home = fixtureHome()
    #expect(CandidateCheck(catalog: catalog, running: Running(answer: false), inUse: FakeInUse(), home: home).check(found) == nil)
    #expect(CandidateCheck(catalog: catalog, running: Running(answer: true), inUse: FakeInUse(), home: home).check(found) == .ownerRunning("Editor"))
    #expect(CandidateCheck(catalog: catalog, running: Running(answer: nil), inUse: FakeInUse(), home: home).check(found) == .ownerUnknown("Editor"))
    // Closed, but another process has a file in it open.
    #expect(CandidateCheck(catalog: catalog, running: Running(answer: false), inUse: FakeInUse(open: [found.url.path]), home: home).check(found) == .inUse("An app"))
    // A recent one is never offered.
    try writeFile("C/com.example.editor/fresh", in: folder, modified: daysAgo(1))
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now)).isEmpty)
}

@Test func anItemAProcessHasOpenIsNeverOfferedAndWhenUseCantBeCheckedNothingIs() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let open = try writeFile("T/open.tmp", in: folder, modified: daysAgo(30))
    let idle = try writeFile("T/idle.bin", in: folder, modified: daysAgo(30))
    #expect(temporaryFiles(catalog.discover(fixture: fixtureHome(), userFolder: folder, inUse: FakeInUse(open: [open.path]), now: now)) == [idle.path])
    let discovery = catalog.discovery(fixture: fixtureHome(), userFolder: folder, inUse: FakeInUse(unknown: true), now: now)
    #expect(temporaryFiles(discovery.candidates).isEmpty)
    #expect(discovery.notes.contains(CatalogNote(ruleID: "temporary-files", text: "Old temporary files: kept all, because CacheDrop couldn’t tell which ones apps are using.")))
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
    try writeFile("C/com.example.editor/blob", in: folder, modified: daysAgo(30))
    try age("C/com.example.editor", in: folder, to: daysAgo(30))
    let recent = try writeFile("T/recent.tmp", in: folder, modified: daysAgo(1))
    let candidates = catalog.discover(fixture: fixtureHome(), userFolder: folder, now: now).filter { $0.ruleID.hasPrefix("temporary-") }
    #expect(candidates.count == 2)
    let volume = FakeVolume()
    volume.freedPerRead = [0, 8192, 0, 12_288]
    let journal = try SQLiteCleanupJournal(url: folder.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: FakeInUse(), home: fixtureHome())
    let run = CleanupExecutor(journal: journal, check: check, measure: volume.read, trash: TrashNeverUsed())
    let result = await run.execute(CatalogApproval(candidates: candidates, previewOnly: false))
    #expect(result.records.map(\.state) == [.succeeded, .succeeded])
    #expect(result.measuredFreedBytes == 20_480)
    #expect(!FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("C/com.example.editor").path))
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
    // Only this test's own process is read, so other processes can't make the answer unknown.
    let used = SystemInUseChecker(onlyProcess: getpid()).inUse([opened, mapped, idle], by: .anyApp)
    #expect(used == [opened.path, mapped.path])
    #expect(mapping.count == 8192)
}

/// Counts how often the process table would be read: once per snapshot.
private final class CountingInUse: InUseChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var taken = 0
    var snapshots: Int { lock.lock(); defer { lock.unlock() }; return taken }
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? { [] }
    func snapshot() -> any InUseChecking { lock.lock(); taken += 1; lock.unlock(); return self }
}

/// The run's clock stands still (#258): a reading is re-taken once it is older than `inUseReadingMaxAge`, and on a loaded
/// strict pool this test can take half a minute of wall time, so the real clock would make a third reading.
/// Re-reading after that age is covered by `aLongRunReadsWhatIsInUseAgainBeforeAnItemOnceTheLastReadingIsTooOld`.
@Test func aDiscoveryAndACleanupRunEachReadWhatIsInUseOnce() async throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["a", "b", "c"] { try writeFile("T/\(name).tmp", in: folder, modified: daysAgo(30)) }
    let clone = folder.appendingPathComponent("X/com.google.Chrome.code_sign_clone/code_sign_clone.old/blob")
    try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4096).write(to: clone)
    let counting = CountingInUse()
    let candidates = catalog.discover(fixture: fixtureHome(), userFolder: folder, inUse: counting, now: now)
    #expect(temporaryFiles(candidates).count == 3)
    #expect(counting.snapshots == 1)
    let journal = try SQLiteCleanupJournal(url: folder.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: counting, home: fixtureHome()),
                              measure: { _ in nil }, trash: TrashNeverUsed(), clock: { now })
    let result = await run.execute(CatalogApproval(candidates: candidates.filter { $0.ruleID.hasPrefix("temporary-") }, previewOnly: true))
    #expect(result.records.count == 3)
    #expect(counting.snapshots == 2)
}

@Test func aSystemSnapshotAnswersForManyItemsAndOwners() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opened = try writeFile("T/open.tmp", in: folder, modified: daysAgo(30))
    let idle = try writeFile("T/idle.tmp", in: folder, modified: daysAgo(30))
    let descriptor = Darwin.open(opened.path, O_RDONLY)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    // Only this test's own process is read: the real process table changes while tests run.
    let snapshot = SystemInUseChecker(onlyProcess: getpid()).snapshot()
    #expect(snapshot.inUse([opened], by: .anyApp) == [opened.path])
    #expect(snapshot.inUse([idle], by: .anyApp) == [])
    #expect(snapshot.inUse([opened, idle], by: RuleOwner(name: "Nobody", executables: ["no-such-process-\(UUID())"])) == [])
}

/// A clock a test moves forward by hand.
private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

/// Records when each snapshot was taken, by the step clock, and answers from what is open at that moment.
private final class TimedInUse: InUseChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: StepClock
    private var takenAt: [Date] = []
    var open: Set<String> = []
    init(clock: StepClock) { self.clock = clock }
    var snapshots: [Date] { lock.lock(); defer { lock.unlock() }; return takenAt }
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? { Set(folders.map(\.path)).intersection(open) }
    func snapshot() -> any InUseChecking {
        lock.lock(); takenAt.append(clock.now); let frozen = FakeInUse(open: open); lock.unlock()
        return frozen
    }
}

@Test func aLongRunReadsWhatIsInUseAgainBeforeAnItemOnceTheLastReadingIsTooOld() async throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["a", "b", "c", "d"] { try writeFile("T/\(name).tmp", in: folder, modified: daysAgo(30)) }
    let approved = catalog.discover(fixture: fixtureHome(), userFolder: folder, inUse: FakeInUse(), now: now)
        .filter { $0.ruleID == "temporary-files" }.sorted { $0.url.path < $1.url.path }
    #expect(approved.count == 4)
    let clock = StepClock()
    let inUse = TimedInUse(clock: clock)
    let journal = try SQLiteCleanupJournal(url: folder.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: inUse, home: fixtureHome()),
                              measure: { _ in nil }, trash: TrashNeverUsed(), clock: { clock.now })
    let start = clock.now
    // Each item takes a little longer than the reading may be old, except the third, which follows quickly.
    let steps: [TimeInterval] = [CleanupExecutor.inUseReadingMaxAge + 1, 1, CleanupExecutor.inUseReadingMaxAge + 1]
    let result = await run.execute(CatalogApproval(candidates: approved, previewOnly: true)) { progress in
        if progress.resolved >= 1, progress.resolved <= steps.count { clock.advance(steps[progress.resolved - 1]) }
    }
    #expect(result.records.count == 4)
    let maxAge = CleanupExecutor.inUseReadingMaxAge
    #expect(inUse.snapshots == [start, start + maxAge + 1, start + maxAge + 1 + 1 + maxAge + 1])
}

@Test func aFileOpenedAfterTheRunStartedIsRefused() async throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try writeFile("T/a.tmp", in: folder, modified: daysAgo(30))
    let later = try writeFile("T/b.tmp", in: folder, modified: daysAgo(30))
    let approved = catalog.discover(fixture: fixtureHome(), userFolder: folder, inUse: FakeInUse(), now: now)
        .filter { $0.ruleID == "temporary-files" }.sorted { $0.url.path < $1.url.path }
    #expect(approved.map(\.url.path) == [first.path, later.path])
    let clock = StepClock()
    let journal = try SQLiteCleanupJournal(url: folder.appendingPathComponent("journal.sqlite"))
    // Only this test's own process is read, so other processes can't make the answer unknown.
    let check = CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: SystemInUseChecker(onlyProcess: getpid()), home: fixtureHome())
    let run = CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: TrashNeverUsed(), clock: { clock.now })
    let descriptor = Descriptor()
    defer { descriptor.close() }
    // After the first item, this process opens the second file, and the run goes on long enough for a new reading.
    let result = await run.execute(CatalogApproval(candidates: approved, previewOnly: true)) { progress in
        guard progress.resolved == 1 else { return }
        descriptor.open(later.path)
        clock.advance(CleanupExecutor.inUseReadingMaxAge + 1)
    }
    #expect(descriptor.value >= 0)
    #expect(result.records.map(\.state) == [.skipped, .skipped])
    #expect(result.records.first?.message.hasPrefix(CleanupRecord.previewPrefix) == true)
    #expect(result.records.last?.message == CheckRefusal.inUse("An app").reason)
}

/// A file descriptor a sendable closure can open and a test closes.
private final class Descriptor: @unchecked Sendable {
    private(set) var value: Int32 = -1
    func open(_ path: String) { value = Darwin.open(path, O_RDONLY) }
    func close() { if value >= 0 { Darwin.close(value) } }
}

@Test func theTemporaryRulesSayTheDaysTheyUse() {
    for id in ["temporary-files", "temporary-app-caches"] {
        let rule = catalog.rule(id)
        #expect(rule?.unused?.unusedDays == 3)
        #expect(rule?.detail.hasSuffix("unchanged for 3 days.") == true)
    }
}
