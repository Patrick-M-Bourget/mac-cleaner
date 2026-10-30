import Foundation
import Testing
@testable import CacheDropCore

/// A temp stand-in for the user's own `/private/var/folders/<xx>/<id>` folder, with its `T`, `C` and `X` folders.
private func fixtureUserFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropVarFolders-\(UUID())")
    for name in ["T", "C", "X"] { try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true) }
    return folder.resolvingSymlinksInPath()
}
/// One Chrome code-sign copy, created at `created`, holding a small `Google Chrome.app`.
@discardableResult
private func writeClone(_ name: String, in folder: URL, created: Date) throws -> URL {
    let clone = folder.appendingPathComponent("X/com.google.Chrome.code_sign_clone/" + name)
    let executable = clone.appendingPathComponent("Google Chrome.app/Contents/MacOS/Google Chrome")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4096).write(to: executable)
    try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: clone.path)
    return clone
}
/// Says which copies are open, or that it can't tell.
private struct FakeInUse: InUseChecking {
    var open: Set<String> = []
    var unknown = false
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? {
        unknown ? nil : Set(folders.map(\.path)).intersection(open)
    }
}
private let catalog = Catalog(rules: fixtureRules)
private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + n * 86_400) }

@Test func everyCodeSignCopyIsOfferedExceptTheNewestAndTheOneInUseIsKeptHeldByChrome() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())")
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let oldest = try writeClone("code_sign_clone.aaaaaa", in: folder, created: day(1))
    let inUse = try writeClone("code_sign_clone.bbbbbb", in: folder, created: day(2))
    let middle = try writeClone("code_sign_clone.cccccc", in: folder, created: day(3))
    try writeClone("code_sign_clone.dddddd", in: folder, created: day(4))
    let candidates = catalog.discover(fixture: home, userFolder: folder, inUse: FakeInUse(open: [inUse.path]))
    #expect(candidates.map(\.url.path).sorted() == [oldest.path, inUse.path, middle.path])
    #expect(candidates.allSatisfy { $0.ruleID == "chrome-code-sign-clones" && $0.action == .delete && $0.isDirectory })
    // The copy Chrome uses stays visible, held, never offered as free (#374).
    let held = try #require(candidates.first { $0.url.path == inUse.path }?.hold)
    #expect(held.refusal == .inUse("Google Chrome") && held.app?.bundleIDs == ["com.google.Chrome"])
    #expect(held.line == "In use by Google Chrome · Quit Google Chrome to clean it")
    #expect(candidates.filter { $0.hold != nil }.map(\.url.path) == [inUse.path])
    // Ticked, it is checked again at Clean up: skipped with the same reason while Chrome uses it, cleaned once free. No force.
    let heldCopy = try #require(candidates.first { $0.hold != nil })
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FakeInUse(open: [inUse.path])).check(heldCopy) == held.refusal)
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FakeInUse()).check(heldCopy) == nil)
    #expect(candidates.allSatisfy { ($0.allocatedBytes ?? 0) >= 4096 })
}

@Test func whenInUseCantBeDeterminedEveryCopyIsKeptAndTheNoteSaysWhy() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())")
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for (index, name) in ["a", "b", "c"].enumerated() { try writeClone("code_sign_clone." + name, in: folder, created: day(Double(index))) }
    let discovery = catalog.discovery(fixture: home, userFolder: folder, inUse: FakeInUse(unknown: true))
    #expect(discovery.candidates.isEmpty)
    #expect(discovery.notes == [CatalogNote(ruleID: "chrome-code-sign-clones",
                                            text: "Chrome code-sign copies: kept all 3 copies, because CacheDrop couldn’t tell which one Google Chrome is using.")])
}

@Test func withoutTheUserFolderNoCopiesAreLookedFor() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())")
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeClone("code_sign_clone.a", in: folder, created: day(1))
    try writeClone("code_sign_clone.b", in: folder, created: day(2))
    #expect(catalog.discover(fixture: home, inUse: FakeInUse()).isEmpty)
    #expect(catalog.discover(fixture: home, userFolder: folder, inUse: FakeInUse()).count == 1)
}

@Test func theSystemCheckerSeesCopiesThisProcessHasOpenOrMapped() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opened = try writeClone("code_sign_clone.open", in: folder, created: day(1))
    let mapped = try writeClone("code_sign_clone.mapped", in: folder, created: day(2))
    let idle = try writeClone("code_sign_clone.idle", in: folder, created: day(3))
    let inside = "Google Chrome.app/Contents/MacOS/Google Chrome"
    let descriptor = open(opened.appendingPathComponent(inside).path, O_RDONLY)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    let mapping = try Data(contentsOf: mapped.appendingPathComponent(inside), options: .alwaysMapped)
    // This test process stands in for Chrome.
    let me = RuleOwner(name: "Test", executables: [URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).resolvingSymlinksInPath().lastPathComponent, ProcessInfo.processInfo.processName])
    let used = SystemInUseChecker().inUse([opened, mapped, idle], by: me)
    #expect(used == [opened.path, mapped.path], "\(String(describing: used)) \(me)")
    #expect(mapping.count == 4096)
    #expect(SystemInUseChecker().inUse([idle], by: RuleOwner(name: "Nobody", executables: ["no-such-process-\(UUID())"])) == [])
}

@Test func theUserFolderIsTheOwnedFolderHoldingTheTempFolder() throws {
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("T"), withIntermediateDirectories: true)
    let found = try #require(Catalog.userFolder(holding: folder.appendingPathComponent("T").path + "/"))
    let real = try #require(realpath(folder.path, nil))
    defer { free(real) }
    #expect(found.path == String(cString: real))
    #expect(Catalog.userFolder(holding: folder.appendingPathComponent("missing/T").path) == nil)
}

@Test func aCopyThatCameIntoUseSinceTheScanIsRefusedJustBeforeActing() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())")
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = try writeClone("code_sign_clone.a", in: folder, created: day(1))
    try writeClone("code_sign_clone.b", in: folder, created: day(2))
    let candidate = try #require(catalog.discover(fixture: home, userFolder: folder, inUse: FakeInUse()).first)
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FakeInUse()).check(candidate) == nil)
    let refusal = CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FakeInUse(open: [old.path])).check(candidate)
    #expect(refusal == .inUse("Google Chrome"))
    #expect(refusal?.reason == "Google Chrome is using it. It is kept.")
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FakeInUse(unknown: true)).check(candidate) == .inUseUnknown("Google Chrome"))
}

/// Available space grows by what each deleted copy really frees.

@Test func deletingCopiesReportsMeasuredFreedSpaceAndTheEstimateIsAnUpperBound() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCatalog-\(UUID())")
    let folder = try fixtureUserFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = try writeClone("code_sign_clone.a", in: folder, created: day(1))
    let older = try writeClone("code_sign_clone.b", in: folder, created: day(0))
    let newest = try writeClone("code_sign_clone.c", in: folder, created: day(2))
    let candidates = catalog.discover(fixture: home, userFolder: folder, inUse: FakeInUse())
    #expect(Set(candidates.map(\.url.path)) == [old.path, older.path])
    #expect(catalog.rule("chrome-code-sign-clones")?.estimateIsUpperBound == true)
    #expect(catalog.rule("npm-cache")?.estimateIsUpperBound == false)
    // Clones share blocks: each copy frees far less than its size.
    let volume = FixtureVolume()
    volume.freedPerRead = [0, 100, 0, 200]
    let journal = try SQLiteCleanupJournal(url: folder.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), inUse: FakeInUse()), measure: volume.read, trash: TrashNeverUsed())
    let result = await run.execute(CatalogApproval(candidates: candidates, dryRun: false))
    #expect(result.records.map(\.state) == [.succeeded, .succeeded])
    #expect(result.measuredFreedBytes == 300)
    #expect(result.estimatedBytes >= 8192)
    #expect(!FileManager.default.fileExists(atPath: old.path) && !FileManager.default.fileExists(atPath: older.path))
    #expect(FileManager.default.fileExists(atPath: newest.path))
}

/// Discovery must use the same known-owner rule as review: an arbitrary process never becomes an app to quit.
@Test func aLeakedCopyUsedByAnyAppDoesNotOfferAnAppToQuit() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropAnyAppCopies-\(UUID())")
    defer { try? FileManager.default.removeItem(at: home) }
    let copy = home.appendingPathComponent("copies/old-copy")
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
    try Data([1]).write(to: copy.appendingPathComponent("entry"))
    let rule = CleanupRule(id: "copies", category: .browser, title: "Copies", detail: "", consequence: "", regen: .leakedCopy,
                           action: .delete, locations: ["copies"], owner: nil, copies: LeakedCopies(owner: .anyApp, keepNewest: 0))
    let found = Catalog(rules: [rule]).discover(fixture: home, inUse: FakeInUse(open: [copy.path]))
    let hold = try #require(found.first?.hold)
    #expect(hold.refusal == .inUse(RuleOwner.anyApp.name))
    #expect(hold.app == nil)
    #expect(hold.line == hold.refusal.reason)
}
