import Foundation
import Testing
@testable import StillCore

/// A temp home folder; tests never read or write the real home, its caches or its logs.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillAppCaches-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

@Test func logsAndCrashReportsAreTheirOwnCategories() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Logs/DiagnosticReports/Editor-2026-10-01.ips", bytes: 300)
    try write(home, "Library/Logs/Editor/main.log", bytes: 200)
    try write(home, "Library/Logs/JetBrains/idea.log")
    let found = Catalog(rules: BuiltInCatalog.rules).discover(home: home)
    let logs = home.appendingPathComponent("Library/Logs").path
    #expect(Dictionary(found.map { ($0.url.path, $0.ruleID) }, uniquingKeysWith: { a, _ in a })
            == [logs + "/DiagnosticReports": "crash-reports", logs + "/Editor": "app-logs", logs + "/JetBrains": "app-logs"])
    #expect(found.allSatisfy { $0.action == .delete })
    let categories = Set(found.compactMap { c in BuiltInCatalog.rules.first { $0.id == c.ruleID }?.category })
    #expect(categories == [.logs])
    #expect(CatalogOverview(catalog: Catalog(rules: BuiltInCatalog.rules), candidates: found).rows.map(\.category) == [.logs])
}
