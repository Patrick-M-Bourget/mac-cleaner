import Foundation
import Testing
@testable import StillCore

/// Temp folders only; tests never read or write the real home.
private func fixtureFolder(_ prefix: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.resolvingSymlinksInPath()
}
private func write(_ root: URL, _ relative: String, bytes: Int = 100) throws {
    let file = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }
private let cargoOnly = Catalog(rules: BuiltInCatalog.rules.filter { $0.id == "cargo-cache" })

@Test func aCacheReachedThroughASymlinkOutOfHomeIsNeverOffered() throws {
    let home = try fixtureFolder("StillScopeHome"), outside = try fixtureFolder("StillScopeOutside")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: outside) }
    try write(outside, "cargo/registry/index/entry")
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".cargo"), withDestinationURL: outside.appendingPathComponent("cargo"))
    #expect(cargoOnly.discover(home: home).isEmpty)
}

@Test func aSymlinkSwappedInAfterTheScanIsRefused() throws {
    let home = try fixtureFolder("StillScopeHome"), outside = try fixtureFolder("StillScopeOutside")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: outside) }
    try write(home, ".cargo/registry/index/entry")
    let candidate = try #require(cargoOnly.discover(home: home).first)
    // The same folder, moved out of home and reached through a symlink: identity alone would pass it.
    try FileManager.default.moveItem(at: home.appendingPathComponent(".cargo"), to: outside.appendingPathComponent("cargo"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".cargo"), withDestinationURL: outside.appendingPathComponent("cargo"))
    #expect(CandidateCheck(catalog: cargoOnly, running: NothingRunning()).check(candidate) == .changed)
}

@Test func excludedItemsAreNeverCandidates() throws {
    let home = try fixtureFolder("StillScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, ".cargo/registry/index/entry")
    try write(home, ".cargo/git/db/entry")
    try write(home, "Downloads/setup.dmg")
    let catalog = Catalog(rules: BuiltInCatalog.rules.filter { ["cargo-cache", "downloads-installers"].contains($0.id) })
    #expect(catalog.discover(home: home).count == 3)
    // An excluded folder, a folder holding an exclusion, and an excluded file.
    let exclusions = ExclusionPolicy(rules: try [".cargo/registry", ".cargo/git/db", "Downloads/setup.dmg"].map { try ExclusionRule.capture(home.appendingPathComponent($0)) })
    #expect(catalog.discover(home: home, exclusions: exclusions).isEmpty)
}

@Test func aGitCheckoutFourLevelsDownIsNeverOfferedAndRefusedIfItAppears() throws {
    let home = try fixtureFolder("StillScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, ".cargo/git/checkouts/x/y/.git/HEAD")
    try write(home, ".cargo/registry/index/entry")
    #expect(cargoOnly.discover(home: home).map(\.url.lastPathComponent) == ["registry"])
    let registry = try #require(cargoOnly.discover(home: home).first)
    try write(home, ".cargo/registry/src/crate/v1/.git/HEAD")
    #expect(CandidateCheck(catalog: cargoOnly, running: NothingRunning()).check(registry) == .protected(".git"))
}

@Test func aDeleteThatFailsPartwayIsRecordedAsPartlyRemovedAndOfferedAgain() async throws {
    let home = try fixtureFolder("StillScopeHome")
    let locked = home.appendingPathComponent(".cargo/registry/locked")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: home)
    }
    try write(home, ".cargo/registry/index/entry")
    try write(home, ".cargo/registry/locked/kept")
    let candidate = try #require(cargoOnly.discover(home: home).first)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: cargoOnly, running: NothingRunning()), measure: { _ in nil })
    let record = try #require(await run.execute(CatalogApproval(candidates: [candidate], previewOnly: false)).records.first)
    #expect(record.state == .failed)
    #expect(record.partlyRemoved == true)
    #expect(record.outcomeTitle == "Partly removed")
    #expect(!record.recoveryStateText.contains("Not changed"))

    // The rest is offered again under the same rule, and the next cleanup finishes it.
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".cargo").path).filter { $0.hasPrefix(".still-deleting-") }
    #expect(leftovers.count == 1)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.appendingPathComponent(".cargo/" + leftovers[0] + "/locked").path)
    let again = cargoOnly.discover(home: home)
    #expect(again.map(\.url.lastPathComponent) == leftovers)
    #expect(again.first?.ruleID == "cargo-cache" && again.first?.action == .delete)
    let second = await run.execute(CatalogApproval(candidates: again, previewOnly: false))
    #expect(second.records.map(\.state) == [.succeeded])
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".cargo").path).isEmpty)
}

/// Homebrew's `brew cleanup -s` runs as a tool; what it leaves half-deleted comes back as a plain delete.
@Test func aLeftoverFromAToolRuleIsOfferedAsADelete() throws {
    let home = try fixtureFolder("StillScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Caches/.still-deleting-homebrew-\(UUID().uuidString)/downloads/x")
    try write(home, "Library/Caches/.still-deleting-pip-cache-\(UUID().uuidString)/http/x")
    let catalog = Catalog(rules: BuiltInCatalog.rules.filter { ["homebrew", "pip-cache"].contains($0.id) })
    let found = catalog.discover(home: home, locateTool: { _ in URL(fileURLWithPath: "/usr/bin/true") })
    #expect(Set(found.map(\.ruleID)) == ["homebrew", "pip-cache"])
    #expect(found.allSatisfy { $0.action == .delete })
    for leftover in found {
        #expect(catalog.owner(for: leftover) == nil)
        #expect(CandidateCheck(catalog: catalog, running: NothingRunning()).check(leftover) == nil)
    }
}

/// Records what it was asked to move; the real Trash is never touched.
private final class RecordingTrash: TrashMoving, @unchecked Sendable {
    private let lock = NSLock()
    private var moved: [URL] = []
    var calls: [URL] { lock.lock(); defer { lock.unlock() }; return moved }
    func moveToTrash(_ url: URL) throws -> URL? { lock.lock(); moved.append(url); lock.unlock(); return nil }
}

@Test func aFileSwappedJustBeforeTheMoveToTrashIsNotMoved() async throws {
    let home = try fixtureFolder("StillScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Downloads/setup.dmg")
    let catalog = Catalog(rules: BuiltInCatalog.rules.filter { $0.id == "downloads-installers" })
    let candidate = try #require(catalog.discover(home: home).first)
    let file = candidate.url
    // The space reading runs after the check and before the move: swap the file there.
    let swap: @Sendable (URL) -> CapacitySample? = { _ in
        try? FileManager.default.removeItem(at: file)
        try? Data(repeating: 2, count: 100).write(to: file)
        return nil
    }
    let trash = RecordingTrash()
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NothingRunning()), measure: swap, trash: trash)
    let record = try #require(await run.execute(CatalogApproval(candidates: [candidate], previewOnly: false)).records.first)
    #expect(trash.calls.isEmpty)
    #expect(record.state == .skipped)
    #expect(record.message == CheckRefusal.changed.reason)
}
