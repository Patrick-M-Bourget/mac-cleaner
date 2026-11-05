import Foundation
import Testing
@testable import CacheDropCore

// #626: `cachedrop scan` and `plan` say what Overview and Smart clean say for the same scan. A fixture home only; the
// installed apps, receipts, tools and running apps are stand-ins, so nothing about this Mac is read.

private struct NoApps: AppPresence {
    func installedApps() -> [InstalledApp]? { [] }
    func isRegistered(bundleID: String) -> Bool { false }
}
private struct NoReceipts: InstallerReceiptReading { func receipts() -> [InstallerReceipt] { [] } }

func commandLineFixture() throws -> (home: URL, sources: SmartCleanReport.Sources) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropCommandLine-\(UUID())").resolvingSymlinksInPath()
    func write(_ relative: String, bytes: Int, age: TimeInterval = 0) throws {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: file)
        if age > 0 {
            let date = Date().addingTimeInterval(-age)
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: file.path)
        }
    }
    try write(".npm/_cacache/content-v2/blob", bytes: 50_000)
    try write("Downloads/Old Setup.dmg", bytes: 30_000, age: 200 * 86_400)
    try write("Downloads/New Setup.dmg", bytes: 20_000, age: 2 * 86_400)
    let sources = SmartCleanReport.Sources(catalog: Catalog(rules: fixtureRules), home: home, userFolder: nil, exclusions: ProtectedItemsPolicy(), apps: NoApps(),
                                           receipts: NoReceipts(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), inUse: FixtureNothingInUse(),
                                           running: FixtureNothingRunning(), access: .granted)
    return (home, sources)
}

private func keys(_ json: String) throws -> Set<String> {
    Set(try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]).keys)
}

@Suite struct CommandLineReportTests {
    @Test func scanSaysWhatOverviewSays() throws {
        let (home, sources) = try commandLineFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let discovery = SmartCleanReport.discover(sources)
        let scan = CommandLineReport.Scan(catalog: sources.catalog, discovery: discovery, home: home, access: .granted)
        let overview = CatalogOverview(catalog: sources.catalog, candidates: discovery.candidates, notAccessible: discovery.notAccessible)
        #expect(scan.categories.map(\.title) == overview.visibleRows.map(\.category.overviewTitle), "Same rows in Overview's order")
        for (category, row) in zip(scan.categories, overview.visibleRows) where !row.isEmpty {
            #expect(category.size?.text == row.valueText)
            #expect(category.items == row.itemCount)
            #expect(category.status == "found")
        }
        #expect(scan.recommended.text == CatalogOverview.recommendedText(overview.recommended))
        #expect(scan.text.contains("Can be cleaned: " + scan.recommended.text), "Overview's header (#764)")
        #expect(scan.text.hasSuffix("Read-only · Nothing was changed"))
    }

    /// Decision 151: the Audio software category is a row like any other, with its own id.
    @Test func scanListsAudioSoftwareWithAbletonsCache() throws {
        let (home, sources) = try commandLineFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let empty = CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: home, access: .granted)
        #expect(empty.categories.first { $0.id == "audio" }?.status == "empty")
        let file = home.appendingPathComponent("Library/Caches/Ableton/Cache/Decoding/loop.mp3.wav")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: file)
        let scan = CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: home, access: .granted)
        let audio = try #require(scan.categories.first { $0.id == "audio" })
        #expect(audio.title == "Audio software" && audio.status == "found" && audio.items == 1)
        // Smart clean recommends the cache as it did under App caches, so `plan` lists it under Audio software.
        let plan = CommandLineReport.Plan(SmartCleanReport.run(sources))
        #expect(plan.categories.first { $0.id == "audio" }?.items.map(\.path) == [file.deletingLastPathComponent().deletingLastPathComponent().path])
    }

    /// Decision 164: Photo and video is a row like any other, with its own id, holding Adobe's media cache.
    @Test func scanListsPhotoAndVideoWithAdobesMediaCache() throws {
        let (home, sources) = try commandLineFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let empty = CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: home, access: .granted)
        #expect(empty.categories.first { $0.id == "photo-video" }?.status == "empty")
        let file = home.appendingPathComponent("Library/Application Support/Adobe/Common/Peak Files/2026-11-03/clip 48000.pek")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: file)
        let scan = CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: home, access: .granted)
        let media = try #require(scan.categories.first { $0.id == "photo-video" })
        #expect(media.title == "Photo and video" && media.status == "found" && media.items == 1)
        let plan = CommandLineReport.Plan(SmartCleanReport.run(sources))
        let peakFiles = file.deletingLastPathComponent().deletingLastPathComponent().path
        let planned = plan.categories.first { $0.id == "photo-video" }?.items.map(\.path)
        #expect(planned == [peakFiles])
    }

    @Test func planSaysWhatSmartCleanWouldClean() throws {
        let (home, sources) = try commandLineFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let report = SmartCleanReport.run(sources)
        let plan = CommandLineReport.Plan(report)
        let paths = plan.categories.flatMap(\.items).map(\.path)
        #expect(Set(paths) == Set(report.picked.map(\.candidate.url.path)))
        #expect(paths.contains(home.appendingPathComponent("Downloads/Old Setup.dmg").path))
        #expect(!paths.contains(home.appendingPathComponent("Downloads/New Setup.dmg").path), "Downloads opened or changed in the last 7 days stay")
        #expect(plan.categories.flatMap(\.items).allSatisfy { !$0.reason.isEmpty })
        let installer = try #require(report.picked.first { $0.candidate.url.lastPathComponent == "Old Setup.dmg" }?.candidate)
        #expect(plan.toTrash.bytes == installer.estimatedBytes, "Only the old installer goes to the Trash")
        #expect(plan.text.hasPrefix("Smart clean would clean \(paths.count) items, \(plan.total.text)"))
    }

    @Test func jsonKeysArePinned() throws {
        let (home, sources) = try commandLineFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let scan = try CommandLineReport.json(CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: home, access: .notGranted))
        #expect(try keys(scan) == ["home", "scannedAt", "fullDiskAccess", "recommended", "toTrash", "categories"])
        #expect(scan.contains("\"fullDiskAccess\" : \"notGranted\""))
        let plan = try CommandLineReport.json(CommandLineReport.Plan(SmartCleanReport.run(sources)))
        #expect(try keys(plan) == ["home", "scannedAt", "total", "toTrash", "categories", "skipped"])
        let category = try #require((try JSONSerialization.jsonObject(with: Data(plan.utf8)) as? [String: Any])?["categories"] as? [[String: Any]]).first
        #expect(Set(category?.keys.map { $0 } ?? []) == ["id", "title", "size", "consequence", "items"])
        let item = try #require((category?["items"] as? [[String: Any]])?.first)
        #expect(Set(item.keys) == ["path", "size", "action", "reason"])
        #expect(Set(try #require(item["size"] as? [String: Any]).keys) == ["text", "bytes", "kind"])
    }

    @Test func anUnknownSizeHasNoBytes() {
        let size = CommandLineReport.Size(.unknown, text: SizeFormatter.text(SizeEstimate.unknown))
        #expect(size.bytes == nil && size.kind == "unknown" && size.text == "Unknown")
    }
}
