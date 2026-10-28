import Foundation
import Darwin
import Testing
@testable import CacheDropCore

// #319: the read-only report runs the real scan and lists what Smart clean would pick. Here it runs against a fixture home
// only; the fixture's installed apps, receipts, tools and running apps are stand-ins, so nothing about this Mac is read.

private let day: TimeInterval = 86_400

private func write(_ home: URL, _ relative: String, bytes: Int = 4_000, age: TimeInterval = 0, now: Date = Date()) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
    guard age > 0 else { return }
    let date = now.addingTimeInterval(-age)
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: file.path)
    var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(file.path, &times) == 0)
}

private struct Apps: AppPresence {
    func installedApps() -> [InstalledApp]? { [] }
    func isRegistered(bundleID: String) -> Bool { false }
}
private struct Receipts: InstallerReceiptReading {
    let all: [InstallerReceipt]
    func receipts() -> [InstallerReceipt] { all }
}
private struct NothingRuns: RunningAppChecking {
    func isRunning(_ owner: RuleOwner) -> Bool? { false }
}

/// A fixture home with an npm cache, an old and a new installer, a receipt-tied leftover and a possibly related one.
private func fixture(now: Date) throws -> (home: URL, sources: SmartCleanReport.Sources) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropSmartCleanReport-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try write(home, ".npm/_cacache/content-v2/blob", bytes: 50_000)
    try write(home, "Downloads/Old Setup.dmg", bytes: 30_000, age: 200 * day, now: now)
    try write(home, "Downloads/New Setup.dmg", bytes: 20_000, age: 2 * day, now: now)
    try write(home, "Library/Application Support/FooData/presets.db", bytes: 10_000)
    try write(home, "Library/Application Support/Gone/x", bytes: 10_000)
    try write(home, "Library/Preferences/com.gone.app.plist")
    let receipts = Receipts(all: [InstallerReceipt(id: "com.foocorp.foo.pkg", apps: [home.path + "/Applications/Foo.app"],
                                                   paths: [home.path + "/Library/Application Support/FooData/presets.db"])])
    let sources = SmartCleanReport.Sources(catalog: Catalog(rules: fixtureRules), home: home, userFolder: nil, exclusions: ExclusionPolicy(), apps: Apps(),
                                           receipts: receipts, locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), inUse: FixtureNothingInUse(),
                                           running: NothingRuns(), access: .granted)
    return (home, sources)
}

/// Everything about every entry under `root` a run could change: kind, size, times, inode, flags and extended attributes.
private func snapshot(_ root: URL) -> [String: String] {
    var entries: [String: String] = [:]
    _ = FileTree.walk(root) { entry in
        let path = String(cString: entry.pointee.fts_path)
        guard let info = entry.pointee.fts_statp?.pointee, Int32(entry.pointee.fts_info) != FTS_DP else { return .continue }
        let size = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        var names = [CChar](repeating: 0, count: max(size, 1))
        if size > 0 { _ = listxattr(path, &names, size, XATTR_NOFOLLOW) }
        entries[path] = "\(info.st_mode) \(info.st_size) \(info.st_ino) \(info.st_flags) m\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec) "
            + "c\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec) x\(String(decoding: names.map { UInt8(bitPattern: $0) }, as: UTF8.self))"
        return .continue
    }
    return entries
}

@Test func theReportListsWhatSmartCleanWouldPickByCategoryWithAReasonEach() throws {
    let now = Date()
    let (home, sources) = try fixture(now: now)
    defer { try? FileManager.default.removeItem(at: home) }

    let report = SmartCleanReport.run(sources, now: now)

    #expect(Set(report.picked.map(\.candidate.url.lastPathComponent)) == ["_cacache", "Old Setup.dmg", "FooData"])
    let text = report.text
    #expect(text.contains("Nothing on disk was changed"))
    #expect(text.contains("~/Downloads/Old Setup.dmg"))
    #expect(text.contains("not opened or changed in 200 days"))
    #expect(text.contains("tied to Foo by installer receipt com.foocorp.foo.pkg"))
    #expect(text.contains("Comes back on its own when your tools and Xcode need it"))
    #expect(text.contains("Goes to the Trash; Put back works"))
    #expect(!text.contains("New Setup.dmg"))
    #expect(!text.contains("Gone"))
}

@Test func theReportChangesNothingOnDisk() throws {
    let now = Date()
    let (home, sources) = try fixture(now: now)
    defer { try? FileManager.default.removeItem(at: home) }
    let before = snapshot(home)
    #expect(before.count > 10)

    let report = SmartCleanReport.run(sources, now: now)

    #expect(!report.picked.isEmpty)
    #expect(snapshot(home) == before)
}

@Test func theReportSaysWhatTheChecksWouldSkipAndWhy() throws {
    let now = Date()
    let (home, sources) = try fixture(now: now)
    defer { try? FileManager.default.removeItem(at: home) }
    let found = SmartCleanReport.scan(sources)
    let report = SmartCleanReport(catalog: sources.catalog, home: home, found: found, now: now) { $0.ruleID == "npm-cache" ? .ownerRunning("npm") : nil }

    #expect(!report.picked.contains { $0.candidate.ruleID == "npm-cache" })
    #expect(report.text.contains("will be skipped: npm is running."))
}

/// Opt-in: the owner's own run against the real home (`CACHEDROP_SMART_CLEAN_REPORT=1`), printed only, never saved.
/// Read-only like the tests above: it scans and checks, and nothing in it can act. Off in every normal test run.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CACHEDROP_SMART_CLEAN_REPORT"] == "1", "Runs only when the owner asks"))
func smartCleanReportForThisMac() throws {
    let report = SmartCleanReport.run(try SmartCleanReport.Sources.thisMac())
    print(report.text)
}

/// #319, #312: the reason agrees with what comes back: "build files that come back", "a cache that comes back".
@Test func theReasonAgreesWithWhatComesBack() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropReason-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    var rules: [CleanupRule] = []
    for (id, regen) in [("build", RegenClass.build), ("cache", .cache)] {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(id), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: home.appendingPathComponent(id + "/entry"))
        rules.append(CleanupRule(id: id, category: .developer, title: id, detail: "", consequence: "", regen: regen, action: .delete, locations: [id], owner: nil))
    }
    let catalog = Catalog(rules: rules)
    let found = catalog.discover(fixture: home, locateTool: { _ in nil })
    func reason(_ id: String) throws -> String {
        let candidate = try #require(found.first { $0.ruleID == id })
        return SmartCleanReport.reason(candidate, rule: rules.first { $0.id == id }!, now: Date())
    }
    #expect(try reason("build") == "build, build files that come back on their own")
    #expect(try reason("cache") == "cache, a cache that comes back on its own")
}
