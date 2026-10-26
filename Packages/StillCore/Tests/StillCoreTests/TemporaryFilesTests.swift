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
