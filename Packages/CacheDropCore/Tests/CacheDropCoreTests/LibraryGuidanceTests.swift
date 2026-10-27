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
