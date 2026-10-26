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
