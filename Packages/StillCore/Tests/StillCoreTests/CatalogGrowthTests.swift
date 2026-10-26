import Foundation
import Testing
import StillCore

private func growthStore() -> (GrowthHistoryStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalogGrowth-" + UUID().uuidString)
    return (GrowthHistoryStore(directory: directory, minimumBaselineAge: 0), directory)
}
private let catalogFingerprint = GrowthFingerprint(scopeID: "catalog", rootID: "home", volumeID: "volume", access: "per-location", rules: "catalog", exclusions: "none", classification: "catalog")
private func location(_ id: String, _ category: CatalogCategory, _ bytes: Int64, measured: Bool = true) -> GrowthAggregate {
    GrowthAggregate(id: "location:" + id, label: "~/" + id, logicalBytes: bytes, dimension: .location, category: category, ruleID: id, measured: measured)
}
private func catalogSnapshot(_ time: Double, _ groups: [GrowthAggregate]) -> GrowthSnapshot {
    GrowthSnapshot(fingerprint: catalogFingerprint, scopeLabel: "Known locations", observedAt: Date(timeIntervalSince1970: time), groups: groups)
}

@Test func catalogComparisonReportsGrowthPerLocationAndPerCategory() async throws {
    let (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = catalogSnapshot(100, [location("npm", .developer, 100), location("yarn", .developer, 50), location("chrome", .browser, 10)])
    #expect(try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch()).state == .firstBaseline)
    let second = catalogSnapshot(200, [location("npm", .developer, 400), location("yarn", .developer, 20), location("chrome", .browser, 30)])
    let result = try await store.record(second, now: second.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .compared)
    #expect(result.logicalDelta == 290)
    #expect(result.groups.first { $0.id == "location:npm" }?.logicalDelta == 300)
    #expect(result.groups.first { $0.id == "location:yarn" }?.logicalDelta == -30)
    #expect(result.groups.first { $0.id == "category:developer" }?.logicalDelta == 270)
    #expect(result.groups.first { $0.id == "category:browser" }?.logicalDelta == 20)
    #expect(result.coverageChanges.isEmpty)
}

@Test func aLocationThatBecomesReadableOrUnreadableIsCoverageNeverGrowth() async throws {
    let (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = catalogSnapshot(100, [location("npm", .developer, 100), location("safari", .browser, 0, measured: false), location("mail", .logs, 500)])
    _ = try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch())
    let second = catalogSnapshot(200, [location("npm", .developer, 150), location("safari", .browser, 9_000, measured: true), location("mail", .logs, 0, measured: false)])
    let result = try await store.record(second, now: second.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.state == .compared)
    #expect(result.logicalDelta == 50)
    #expect(result.groups.first { $0.id == "location:safari" } == nil)
    #expect(result.groups.first { $0.id == "location:mail" } == nil)
    #expect(result.groups.first { $0.id == "category:browser" }?.logicalDelta ?? 0 == 0)
    #expect(result.groups.first { $0.id == "category:logs" }?.logicalDelta ?? 0 == 0)
    #expect(Dictionary(uniqueKeysWithValues: result.coverageChanges.map { ($0.id, $0.kind) }) == ["location:safari": .newlyReadable, "location:mail": .newlyUnreadable])
}

@Test func aLocationNewlyScannedOrNoLongerScannedIsCoverageNeverGrowth() async throws {
    let (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = catalogSnapshot(100, [location("npm", .developer, 100), location("gone", .developer, 700)])
    _ = try await store.record(first, now: first.observedAt, expectedEpoch: try await store.recordingEpoch())
    let second = catalogSnapshot(200, [location("npm", .developer, 100), location("new", .models, 5_000)])
    let result = try await store.record(second, now: second.observedAt, expectedEpoch: try await store.recordingEpoch())
    #expect(result.logicalDelta == 0)
    #expect(result.groups.first { $0.id == "category:models" }?.logicalDelta ?? 0 == 0)
    #expect(Dictionary(uniqueKeysWithValues: result.coverageChanges.map { ($0.id, $0.kind) }) == ["location:new": .newlyScanned, "location:gone": .noLongerScanned])
}

@Test func unmeasuredLocationsAreLeftOutOfTheRecordedTotal() {
    let snapshot = catalogSnapshot(100, [location("npm", .developer, 100), location("safari", .browser, 40, measured: false)])
    #expect(snapshot.logicalBytes == 100)
}

private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalogGrowthHome-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ bytes: Int, at path: String, in home: URL) throws {
    let file = home.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
private func recordCatalogScan(_ catalog: Catalog, home: URL, recorder: GrowthScanRecorder, access: FullDiskAccessStatus = .granted) async throws -> GrowthComparison {
    let token = try await recorder.beginCatalog(home: home, exclusionFingerprint: ExclusionPolicy().fingerprint)
    let discovery = catalog.discovery(fixture: home, access: access)
    return try await recorder.completeCatalog(discovery, catalog: catalog, fullDiskAccess: access, token: token)
}

@Test func theFirstCatalogScanRecordsABaselineAndTheNextShowsGrowthPerCategoryAndLocation() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let catalog = Catalog(rules: fixtureRules), recorder = GrowthScanRecorder(store: store)
    try write(10_000, at: ".npm/_cacache/content-v2/one", in: home)
    let first = try await recordCatalogScan(catalog, home: home, recorder: recorder)
    #expect(first.state == .firstBaseline)
    #expect(first.current?.fingerprint.isCatalog == true)
    let npm = try #require(first.current?.groups.first { $0.ruleID == "npm-cache" })
    #expect(npm.dimension == .location && npm.category == .developer && npm.label == "~/.npm/_cacache" && npm.measured == true)
    #expect(npm.logicalBytes >= 10_000)
    // Every scanned rule location is recorded, found or not, so a later appearance isn't mistaken for coverage.
    #expect(first.current?.groups.contains { $0.ruleID == "yarn-cache" && $0.logicalBytes == 0 } == true)

    try write(1_000_000, at: ".npm/_cacache/content-v2/two", in: home)
    try write(500_000, at: "Library/Caches/Yarn/blob", in: home)
    let second = try await recordCatalogScan(catalog, home: home, recorder: recorder)
    #expect(second.state == .compared)
    #expect(second.coverageChanges.isEmpty)
    let npmDelta = try #require(second.groups.first { $0.id == npm.id }?.logicalDelta)
    #expect(npmDelta >= 1_000_000)
    let developer = try #require(second.groups.first { $0.id == "category:developer" }?.logicalDelta)
    #expect(developer >= 1_500_000)
    #expect(second.logicalDelta == developer)
}

@Test func aCatalogLocationThatNeedsFullDiskAccessIsCoverageWhenAccessIsGranted() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let safari = CleanupRule(id: "safari-fixture", category: .browser, title: "Safari cache", detail: "", consequence: "", regen: .cache, action: .delete,
                             locations: ["Library/Caches/com.apple.Safari"], owner: nil, requiresFullDiskAccess: true)
    let catalog = Catalog(rules: [safari]), recorder = GrowthScanRecorder(store: store)
    try write(4_000_000, at: "Library/Caches/com.apple.Safari/blob", in: home)
    let first = try await recordCatalogScan(catalog, home: home, recorder: recorder, access: .notGranted)
    #expect(first.current?.groups.first?.measured == false)
    let second = try await recordCatalogScan(catalog, home: home, recorder: recorder, access: .granted)
    #expect(second.state == .compared)
    #expect(second.logicalDelta == 0)
    #expect(second.groups.first { $0.id == "category:browser" }?.logicalDelta ?? 0 == 0)
    #expect(second.coverageChanges.map(\.kind) == [.newlyReadable])
}

@Test func theBuiltInCatalogFitsInOneGrowthSnapshot() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let result = try await recordCatalogScan(Catalog(rules: fixtureRules), home: home, recorder: GrowthScanRecorder(store: store))
    #expect(result.state == .firstBaseline)
}

@Test func itemsUnderAWildcardLocationAndLeftoversBesideItCountInThatLocation() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let rule = CleanupRule(id: "fixture-caches", category: .system, title: "Fixture caches", detail: "", consequence: "", regen: .cache, action: .delete,
                           locations: ["Library/FixtureCaches/*"], owner: nil)
    try write(1_000, at: "Library/FixtureCaches/one/blob", in: home)
    try write(2_000, at: "Library/FixtureCaches/two/blob", in: home)
    try write(4_000, at: "Library/FixtureCaches/.still-deleting-fixture-caches-\(UUID().uuidString)/blob", in: home)
    let result = try await recordCatalogScan(Catalog(rules: [rule]), home: home, recorder: GrowthScanRecorder(store: store))
    let groups = try #require(result.current?.groups)
    #expect(groups.count == 1)
    #expect(groups.first?.label == "~/Library/FixtureCaches")
    #expect((groups.first?.logicalBytes ?? 0) >= 7_000)
}

@Test func catalogSnapshotsKeepTheRetentionLimits() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillCatalogGrowth-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GrowthHistoryStore(directory: directory, policy: GrowthRetention(days: 1, baselines: 2))
    for time in [100.0, 200, 300] {
        _ = try await store.record(catalogSnapshot(time, [location("npm", .developer, Int64(time))]), now: Date(timeIntervalSince1970: time), expectedEpoch: try await store.recordingEpoch())
    }
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 300)).map(\.observedAt.timeIntervalSince1970) == [200, 300])
    #expect(try await store.snapshots(now: Date(timeIntervalSince1970: 300 + 86_401)).isEmpty)
    // The limits never loosen past 90 days and 30 baselines.
    let widest = GrowthRetention(days: 365, baselines: 100, bytes: .max)
    #expect(widest.days == 90 && widest.baselines == 30 && widest.bytes == 250_000_000)
}

@Test func aLocationThatExistsButCantBeReadIsCoverageNeverGrowth() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    let folders = ["Library/FixtureCache", "Library/FixtureCaches", "FixtureDownloads"].map { home.appendingPathComponent($0) }
    defer { folders.forEach { chmod($0.path, 0o755) }; try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    // A plain folder, each folder inside one, and single files inside one.
    let rules = [
        CleanupRule(id: "fixture-cache", category: .developer, title: "Fixture cache", detail: "", consequence: "", regen: .cache, action: .delete,
                    locations: ["Library/FixtureCache"], owner: nil),
        CleanupRule(id: "fixture-caches", category: .developer, title: "Fixture caches", detail: "", consequence: "", regen: .cache, action: .delete,
                    locations: ["Library/FixtureCaches/*"], owner: nil),
        CleanupRule(id: "fixture-downloads", category: .downloads, title: "Fixture downloads", detail: "", consequence: "", regen: .installer, action: .trash,
                    locations: ["FixtureDownloads"], owner: nil, contents: ContentsMatch(extensions: ["dmg"])),
    ]
    let catalog = Catalog(rules: rules), recorder = GrowthScanRecorder(store: store)
    try write(3_000_000, at: "Library/FixtureCache/blob", in: home)
    try write(2_000_000, at: "Library/FixtureCaches/one/blob", in: home)
    try write(1_000_000, at: "FixtureDownloads/app.dmg", in: home)
    _ = try await recordCatalogScan(catalog, home: home, recorder: recorder)

    for folder in folders { #expect(chmod(folder.path, 0) == 0) }
    let unreadable = try await recordCatalogScan(catalog, home: home, recorder: recorder)
    #expect(unreadable.current?.groups.map(\.measured) == [false, false, false])
    #expect(unreadable.logicalDelta == 0)
    #expect(unreadable.coverageChanges.map(\.kind) == [.newlyUnreadable, .newlyUnreadable, .newlyUnreadable])

    for folder in folders { #expect(chmod(folder.path, 0o755) == 0) }
    let readable = try await recordCatalogScan(catalog, home: home, recorder: recorder)
    #expect(readable.logicalDelta == 0)
    #expect(readable.groups.filter { $0.dimension == .category }.allSatisfy { $0.logicalDelta == 0 })
    #expect(readable.coverageChanges.map(\.kind) == [.newlyReadable, .newlyReadable, .newlyReadable])
}

@Test func clearAndResetRejectAnEarlierCatalogScanEvenThroughAnotherStoreInstance() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let catalog = Catalog(rules: fixtureRules), recorder = GrowthScanRecorder(store: store)
    try write(10_000, at: ".npm/_cacache/content-v2/one", in: home)
    for reset in [false, true] {
        let token = try await recorder.beginCatalog(home: home, exclusionFingerprint: ExclusionPolicy().fingerprint)
        let discovery = catalog.discovery(fixture: home, access: .granted)
        let maintenance = GrowthHistoryStore(directory: directory)
        if reset { try await maintenance.resetHistory() } else { try await maintenance.clearCompletedHistory() }
        #expect(try await recorder.completeCatalog(discovery, catalog: catalog, fullDiskAccess: .granted, token: token).state == .unknown)
        let reopened = GrowthHistoryStore(directory: directory)
        #expect(try await reopened.snapshots().isEmpty)
        #expect(try await reopened.latest().state == (reset ? .firstBaseline : .clearedBaseline))
    }
}

@Test func changingCoverageRejectsAnInflightCatalogScanWithoutClearingHistory() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let catalog = Catalog(rules: fixtureRules), recorder = GrowthScanRecorder(store: store)
    try write(10_000, at: ".npm/_cacache/content-v2/one", in: home)
    #expect(try await recordCatalogScan(catalog, home: home, recorder: recorder).state == .firstBaseline)
    let stale = try await recorder.beginCatalog(home: home, exclusionFingerprint: ExclusionPolicy().fingerprint)
    let discovery = catalog.discovery(fixture: home, access: .granted)
    try await store.invalidateCoverage()
    #expect(try await recorder.completeCatalog(discovery, catalog: catalog, fullDiskAccess: .granted, token: stale).state == .unknown)
    #expect(try await store.snapshots().count == 1)
}

/// #126: the rescan after a cleanup is recorded as such, so it never becomes a later scan's baseline.
@Test func aCatalogRescanAfterACleanupIsRecordedAsOne() async throws {
    let home = try fixtureHome(), (store, directory) = growthStore()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: directory) }
    let catalog = Catalog(rules: fixtureRules), recorder = GrowthScanRecorder(store: store)
    let first = try await recordCatalogScan(catalog, home: home, recorder: recorder)
    #expect(first.current?.afterCleanup == false)
    let token = try await recorder.beginCatalog(home: home, exclusionFingerprint: ExclusionPolicy().fingerprint)
    let rescan = try await recorder.completeCatalog(catalog.discovery(fixture: home, access: .granted), catalog: catalog, fullDiskAccess: .granted, token: token,
                                                    afterCleanup: true)
    #expect(rescan.current?.afterCleanup == true)
    #expect(try await store.snapshots().last?.afterCleanup == true)
}
