import Foundation
import Testing
@testable import CacheDropCore

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
private let cargoOnly = Catalog(rules: fixtureRules.filter { $0.id == "cargo-cache" })

@Test func aCacheReachedThroughASymlinkOutOfHomeIsNeverOffered() throws {
    let home = try fixtureFolder("CacheDropScopeHome"), outside = try fixtureFolder("CacheDropScopeOutside")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: outside) }
    try write(outside, "cargo/registry/index/entry")
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".cargo"), withDestinationURL: outside.appendingPathComponent("cargo"))
    #expect(cargoOnly.discover(fixture: home).isEmpty)
}

@Test func aSymlinkSwappedInAfterTheScanIsRefused() throws {
    let home = try fixtureFolder("CacheDropScopeHome"), outside = try fixtureFolder("CacheDropScopeOutside")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: outside) }
    try write(home, ".cargo/registry/index/entry")
    let candidate = try #require(cargoOnly.discover(fixture: home).first)
    // The same folder, moved out of home and reached through a symlink: identity alone would pass it.
    try FileManager.default.moveItem(at: home.appendingPathComponent(".cargo"), to: outside.appendingPathComponent("cargo"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".cargo"), withDestinationURL: outside.appendingPathComponent("cargo"))
    #expect(CandidateCheck(catalog: cargoOnly, running: FixtureNothingRunning()).check(candidate) == .changed)
}

@Test func excludedItemsAreNeverCandidates() throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, ".cargo/registry/index/entry")
    try write(home, ".cargo/git/db/entry")
    try write(home, "Downloads/setup.dmg")
    let catalog = Catalog(rules: fixtureRules.filter { ["cargo-cache", "downloads"].contains($0.id) })
    #expect(catalog.discover(fixture: home).count == 3)
    // An excluded folder, a folder holding an exclusion, and an excluded file.
    let exclusions = ProtectedItemsPolicy(rules: try [".cargo/registry", ".cargo/git/db", "Downloads/setup.dmg"].map { try ProtectedItemsRule.capture(home.appendingPathComponent($0)) })
    #expect(catalog.discover(fixture: home, exclusions: exclusions).isEmpty)
}

@Test func aGitCheckoutFourLevelsDownIsNeverOfferedAndRefusedIfItAppears() throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, ".cargo/git/checkouts/x/y/.git/HEAD")
    try write(home, ".cargo/registry/index/entry")
    #expect(cargoOnly.discover(fixture: home).map(\.url.lastPathComponent) == ["registry"])
    let registry = try #require(cargoOnly.discover(fixture: home).first)
    try write(home, ".cargo/registry/src/crate/v1/.git/HEAD")
    #expect(CandidateCheck(catalog: cargoOnly, running: FixtureNothingRunning()).check(registry) == .protected(".git"))
}

@Test func aDeleteThatFailsPartwayIsRecordedAsPartlyRemovedAndOfferedAgain() async throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    let locked = home.appendingPathComponent(".cargo/registry/locked")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: home)
    }
    try write(home, ".cargo/registry/index/entry")
    try write(home, ".cargo/registry/locked/kept")
    let candidate = try #require(cargoOnly.discover(fixture: home).first)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: cargoOnly, running: FixtureNothingRunning()), measure: { _ in nil }, trash: TrashNeverUsed())
    let record = try #require(await run.execute(CatalogApproval(candidates: [candidate], dryRun: false)).records.first)
    #expect(record.state == .failed)
    #expect(record.partlyRemoved == true)
    #expect(record.outcomeTitle == "Partly removed")
    #expect(!record.recoveryStateText.contains("Not changed"))

    // The rest is offered again under the same rule, and the next cleanup finishes it.
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".cargo").path).filter { $0.hasPrefix(".cachedrop-deleting-") }
    #expect(leftovers.count == 1)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.appendingPathComponent(".cargo/" + leftovers[0] + "/locked").path)
    let again = cargoOnly.discover(fixture: home)
    #expect(again.map(\.url.lastPathComponent) == leftovers)
    #expect(again.first?.ruleID == "cargo-cache" && again.first?.action == .delete)
    let second = await run.execute(CatalogApproval(candidates: again, dryRun: false))
    #expect(second.records.map(\.state) == [.succeeded])
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".cargo").path).isEmpty)
}

/// Homebrew's `brew cleanup -s` runs as a tool; what it leaves half-deleted comes back as a plain delete. Still's leftovers
/// (`.still-deleting-`, its former marker) come back the same way.
@Test func aLeftoverFromAToolRuleIsOfferedAsADelete() throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Caches/.cachedrop-deleting-homebrew-\(UUID().uuidString)/downloads/x")
    try write(home, "Library/Caches/.still-deleting-pip-cache-\(UUID().uuidString)/http/x")
    let catalog = Catalog(rules: fixtureRules.filter { ["homebrew", "pip-cache"].contains($0.id) })
    let found = catalog.discover(fixture: home, locateTool: { _ in URL(fileURLWithPath: "/usr/bin/true") })
    #expect(Set(found.map(\.ruleID)) == ["homebrew", "pip-cache"])
    #expect(found.allSatisfy { $0.action == .delete })
    for leftover in found {
        #expect(catalog.owner(for: leftover) == nil)
        #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning()).check(leftover) == nil)
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
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Downloads/setup.dmg")
    let catalog = Catalog(rules: fixtureRules.filter { $0.id == "downloads" })
    let candidate = try #require(catalog.discover(fixture: home).first)
    let file = candidate.url
    // The space reading runs after the check and before the move: swap the file there.
    let swap: @Sendable (URL) -> CapacitySample? = { _ in
        try? FileManager.default.removeItem(at: file)
        try? Data(repeating: 2, count: 100).write(to: file)
        return nil
    }
    let trash = RecordingTrash()
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: swap, trash: trash)
    let record = try #require(await run.execute(CatalogApproval(candidates: [candidate], dryRun: false)).records.first)
    #expect(trash.calls.isEmpty)
    #expect(record.state == .skipped)
    #expect(record.message == CheckRefusal.changed.reason)
}

@Test func logsOfMacOSAndStillAreNeverOffered() throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    for folder in ["com.apple.xpc.launchd", "com.apple.Safari", "Still", "com.patrickbourget.Still", "Editor"] { try write(home, "Library/Logs/\(folder)/log.txt") }
    let catalog = Catalog(rules: fixtureRules.filter { $0.id == "app-logs" })
    let found = catalog.discover(fixture: home)
    #expect(found.map(\.url.lastPathComponent) == ["Editor"])
}

@Test func cacheDropsAndStillsOwnFoldersAreNeverOffered() throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    let own = ["CacheDrop", "com.patrickbourget.CacheDrop", "Still", "com.patrickbourget.Still"]
    for folder in own + ["Editor"] { try write(home, "Library/Logs/\(folder)/log.txt") }
    for folder in own { try write(home, "Downloads/\(folder)/setup.dmg") }
    let found = Catalog(rules: fixtureRules.filter { $0.id == "app-logs" || $0.id == "downloads" }).discover(fixture: home)
    #expect(found.map(\.url.lastPathComponent) == ["Editor"])
}

@Test func huggingFaceCLIIsMatchedWhenItRunsAsAPythonScript() throws {
    let owner = try #require(fixtureRules.first { $0.id == "huggingface-models" }?.owner)
    #expect(owner.matches(["/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/hf", "download", "org/model"]))
    #expect(owner.matches(["/usr/bin/python3", "/Users/me/.local/bin/huggingface-cli", "login"]))
    #expect(owner.matches(["/Users/me/.local/bin/hf", "cache", "scan"]))
    #expect(!owner.matches(["/usr/bin/python3", "train.py", "hf"]))
    #expect(!owner.matches(["/usr/bin/python3", "/p/serve.py"]))
}

@Test func aScanNeverOffersWhatTheCheckRefuses() throws {
    let home = try fixtureFolder("CacheDropScopeHome")
    defer { try? FileManager.default.removeItem(at: home) }
    for file in ["Downloads/ccache/setup.dmg", "Downloads/Still/setup.dmg", "Downloads/com.apple.Thing/setup.zip", "Downloads/kept.dmg",
                 "Library/Logs/Editor/log.txt", "Library/Logs/com.apple.xpc/log.txt", ".cargo/registry/index/entry"] { try write(home, file) }
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discover(fixture: home)
    #expect(Set(found.map(\.url.lastPathComponent)) == ["kept.dmg", "Editor", "registry"])
    let check = CandidateCheck(catalog: catalog, running: FixtureNothingRunning())
    for candidate in found { #expect(check.check(candidate) == nil, "\(candidate.url.path)") }
}
