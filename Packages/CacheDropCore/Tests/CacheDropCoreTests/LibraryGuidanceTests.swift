import Foundation
import Testing
@testable import CacheDropCore

/// Library guidance (#180, #178) on fake library packages in a temp home, which also stands in for the system root,
/// so `<home>/Volumes/External` is a connected volume. Tests never read the real home or volumes.
private func libraryHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropLibraries-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ bytes: Int, at relative: String, in home: URL) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: bytes).write(to: file)
}

@Test func everyPhotosLibraryIsFoundRenamedAndExternalWithItsSizeAndVolume() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(40_960, at: "Pictures/Photos Library.photoslibrary/originals/a.heic", in: home)
    try write(20_480, at: "Pictures/Trip 2019.photoslibrary/originals/b.heic", in: home)
    // A library inside a library is part of it: the search never goes inside one.
    try write(4096, at: "Pictures/Trip 2019.photoslibrary/resources/Inner.photoslibrary/c", in: home)
    try write(8192, at: "Volumes/External/Archive/Family.photoslibrary/originals/d.heic", in: home)
    // ~/Library holds apps' own data: never searched.
    try write(4096, at: "Library/Containers/Some.app/Old.photoslibrary/e", in: home)
    let catalog = Catalog(rules: fixtureRules)

    let photos = try #require(catalog.guidance(fixture: home).first { $0.ruleID == "photos-library" })
    let libraries = try #require(photos.libraries)
    #expect(libraries.map(\.name).sorted() == ["Family", "Photos Library", "Trip 2019"])
    #expect(libraries.first { $0.name == "Family" }?.volume == "External")
    #expect(libraries.first { $0.name == "Trip 2019" }?.volume != "External")
    guard case .measured(let trip) = try #require(libraries.first { $0.name == "Trip 2019" }).size else { Issue.record("Expected a measured size"); return }
    #expect(trip >= 24_576)
    guard case .estimate(.measured(let total)) = photos.size else { Issue.record("Expected a measured total, got \(photos.size)"); return }
    #expect(total >= 73_728)
}

@Test func aPhotosLibraryIsNeverOffered() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "Pictures/Renamed.photoslibrary/database/Photos.sqlite", in: home)
    let catalog = Catalog(rules: fixtureRules)

    #expect(catalog.discover(fixture: home).isEmpty)
    #expect(catalog.rule("photos-library")?.action == .guidance)
    #expect(catalog.guidance(fixture: home).first { $0.ruleID == "photos-library" }?.libraries?.count == 1)
}

@Test func withoutFullDiskAccessNoLibraryIsSearchedFor() throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "Pictures/Photos Library.photoslibrary/a", in: home)
    let finding = Catalog(rules: fixtureRules).guidance(home: home, systemRoot: home, snapshots: FixtureSnapshots(), fullDiskAccess: .notGranted)
        .first { $0.ruleID == "photos-library" }
    #expect(finding?.size == .notAccessible && finding?.libraries == nil)
}

@Test func theLibrariesSummaryCountsThemAndNamesTheirVolumes() {
    func library(_ path: String, _ volume: String) -> FoundLibrary { FoundLibrary(url: URL(fileURLWithPath: path), volume: volume, size: .measured(1)) }
    #expect(FoundLibrary.summary([library("/a/One.fcpbundle", "Macintosh HD")]) == "1 library · Macintosh HD")
    #expect(FoundLibrary.summary([library("/a/One.photoslibrary", "Macintosh HD"), library("/b/Two.photoslibrary", "Macintosh HD"),
                                  library("/Volumes/X/Three.photoslibrary", "External")]) == "3 libraries · Macintosh HD, External")
}

/// Records what would open; opens nothing.
private actor RecordingOpener: GuidanceOpening {
    private(set) var targets: [GuidanceTarget] = []
    func open(_ target: GuidanceTarget) async -> Bool { targets.append(target); return true }
}

@Test func everyFinalCutLibraryIsFoundAndOpeningFinalCutCleansNothing() async throws {
    let home = try libraryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(30_000, at: "Movies/Untitled.fcpbundle/Event 1/Render Files/a.mov", in: home)
    try write(10_000, at: "Documents/Client Cut.fcpbundle/Event 1/Original Media/b.mov", in: home)
    try write(20_000, at: "Volumes/Shuttle/Projects/2026/Edit.fcpbundle/Event 1/Transcoded Media/c.mov", in: home)
    let catalog = Catalog(rules: fixtureRules)

    let finding = try #require(catalog.guidance(fixture: home).first { $0.ruleID == "final-cut-libraries" })
    let libraries = try #require(finding.libraries)
    #expect(libraries.map(\.name).sorted() == ["Client Cut", "Edit", "Untitled"])
    #expect(libraries.first { $0.name == "Edit" }?.volume == "Shuttle")
    let rule = try #require(catalog.rule("final-cut-libraries"))
    #expect(rule.action == .guidance && rule.guidance?.openTitle == "Open Final Cut Pro")
    #expect(rule.detail.contains("Delete Generated Library Files"))

    // Guidance is never a candidate, so its bytes can never count as freed; opening reports only that it opened.
    #expect(catalog.discover(fixture: home).isEmpty)
    let opener = RecordingOpener()
    #expect(await catalog.open(finding, using: opener))
    #expect(await opener.targets == [.app(bundleID: "com.apple.FinalCut")])
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Movies/Untitled.fcpbundle/Event 1/Render Files/a.mov").path))
}

/// A directory reader that hangs on one volume, as a dropped SMB share can, until the test lets it go (#244).
private final class StuckReader: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let stuckName: String
    init(stuck name: String) { stuckName = name }
    func volumes(network: Set<String> = []) -> LibraryVolumes {
        LibraryVolumes(isLocal: { !network.contains($0.lastPathComponent) }, walk: { [self] root, visit in
            if root.lastPathComponent == stuckName { release.wait() }
            return FileTree.walk(root, visit)
        })
    }
}

@Test func aStuckVolumeIsAbandonedAtTheDeadlineAndReportedNotSearched() throws {
    let base = try libraryHome(), home = base.appendingPathComponent("Home"), system = base.appendingPathComponent("System")
    defer { try? FileManager.default.removeItem(at: base) }
    try write(4096, at: "Home/Pictures/Photos Library.photoslibrary/a", in: base)
    try write(4096, at: "System/Volumes/External/Family.photoslibrary/b", in: base)
    try write(4096, at: "System/Volumes/Stuck/Old.photoslibrary/c", in: base)
    let reader = StuckReader(stuck: "Stuck")
    defer { reader.release.signal() }

    let started = ProcessInfo.processInfo.systemUptime
    let result = LibrarySearch.find(extensions: ["photoslibrary"], home: home, systemRoot: system,
                                    sizer: KnownLocationSizer(timeBudget: 0.5), volumes: reader.volumes())
    #expect(ProcessInfo.processInfo.systemUptime - started < 5)
    #expect(result.found["photoslibrary"]?.map(\.name).sorted() == ["Family", "Photos Library"])
    #expect(result.notSearched == ["Stuck"])
    #expect(!result.complete)
}

@Test func aNetworkVolumeIsNeverSearched() throws {
    let base = try libraryHome(), home = base.appendingPathComponent("Home"), system = base.appendingPathComponent("System")
    defer { try? FileManager.default.removeItem(at: base) }
    try write(4096, at: "System/Volumes/External/Family.photoslibrary/b", in: base)
    try write(4096, at: "System/Volumes/Share/Team.photoslibrary/c", in: base)
    // The share would hang if it were read at all.
    let reader = StuckReader(stuck: "Share")
    defer { reader.release.signal() }

    let result = LibrarySearch.find(extensions: ["photoslibrary"], home: home, systemRoot: system,
                                    sizer: KnownLocationSizer(timeBudget: 5), volumes: reader.volumes(network: ["Share"]))
    #expect(result.found["photoslibrary"]?.map(\.name) == ["Family"])
    #expect(result.notSearched.isEmpty && result.complete)
}

@Test func theSummaryNamesAVolumeThatWasNotSearched() {
    let one = FoundLibrary(url: URL(fileURLWithPath: "/a/One.photoslibrary"), volume: "Macintosh HD", size: .measured(1))
    #expect(FoundLibrary.summary([one], notSearched: ["NAS"]) == "1 library · Macintosh HD · NAS not searched")
    #expect(FoundLibrary.summary([one], notSearched: ["NAS", "Old Disk"]) == "1 library · Macintosh HD · NAS, Old Disk not searched")
}

@Test func aFindingCarriesTheVolumesNotSearched() throws {
    let base = try libraryHome(), home = base.appendingPathComponent("Home"), system = base.appendingPathComponent("System")
    defer { try? FileManager.default.removeItem(at: base) }
    try write(4096, at: "Home/Pictures/Photos Library.photoslibrary/a", in: base)
    try write(4096, at: "System/Volumes/Stuck/Old.photoslibrary/c", in: base)
    let reader = StuckReader(stuck: "Stuck")
    defer { reader.release.signal() }

    let finding = Catalog(rules: fixtureRules).guidance(home: home, systemRoot: system, sizer: KnownLocationSizer(timeBudget: 0.5),
                                                        snapshots: FixtureSnapshots(), libraryVolumes: reader.volumes())
        .first { $0.ruleID == "photos-library" }
    #expect(finding?.libraries?.map(\.name) == ["Photos Library"])
    #expect(finding?.notSearched == ["Stuck"])
}
