import Foundation
import Testing
import StillCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalog-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func writeNpmCache(in home: URL, files: [String: Int] = ["index-v5/aa/one": 3, "content-v2/sha512/ab/blob": 5000]) throws -> URL {
    let cache = home.appendingPathComponent(".npm/_cacache")
    for (path, size) in files {
        let file = cache.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: size).write(to: file)
    }
    return cache
}

@Test func npmRuleDiscoversTheCacheFolderWithItsSize() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = try writeNpmCache(in: home)
    let candidates = Catalog(rules: BuiltInCatalog.rules).discover(home: home)
    #expect(candidates.count == 1)
    let candidate = try #require(candidates.first)
    #expect(candidate.ruleID == "npm-cache")
    #expect(candidate.url.path == cache.path)
    #expect(candidate.action == .delete)
    #expect(candidate.logicalBytes == 5003)
    #expect(candidate.sizeComplete)
    #expect((candidate.allocatedBytes ?? 0) >= 5003)
}

@Test func aRuleWhoseFolderIsMissingOffersNothing() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(Catalog(rules: BuiltInCatalog.rules).discover(home: home).isEmpty)
}
