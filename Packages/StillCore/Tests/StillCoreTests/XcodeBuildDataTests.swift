import Foundation
import Testing
import StillCore

/// A temp home folder; tests never read or write the real home or the real Xcode folders.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillXcode-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func makeFolder(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative).appendingPathComponent("entry")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
private let derivedData = "Library/Developer/Xcode/DerivedData"

@Test func everyFolderInsideDerivedDataIsACandidateAndNothingOutsideIt() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    try makeFolder(home, "Library/Developer/Xcode/Archives/2026-10-01/Still.xcarchive/dSYMs/Still.app.dSYM")
    try makeFolder(home, "Library/Developer/Xcode/UserData/CodeSnippets")
    try makeFolder(home, "Projects/Still/Still.xcodeproj")
    #expect(catalog.discover(home: home).isEmpty)
    // Built products and dSYMs inside DerivedData are regenerable (Decision 22).
    try makeFolder(home, derivedData + "/Still-abc/Build/Products/Debug/Still.app/Contents/MacOS", bytes: 300)
    try makeFolder(home, derivedData + "/Still-abc/Build/Products/Debug/Still.app.dSYM", bytes: 200)
    try makeFolder(home, derivedData + "/Other-def/Index.noindex")
    try makeFolder(home, derivedData + "/ModuleCache.noindex")
    try Data(repeating: 1, count: 10).write(to: home.appendingPathComponent(derivedData + "/stray-file"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(derivedData + "/Linked-ghi"),
                                               withDestinationURL: home.appendingPathComponent("Projects/Still"))
    let found = catalog.discover(home: home)
    #expect(Set(found.map(\.url.lastPathComponent)) == ["Still-abc", "Other-def", "ModuleCache.noindex"])
    #expect(found.allSatisfy { $0.ruleID == "xcode-derived-data" && $0.action == .delete && $0.isDirectory })
    #expect(found.first { $0.url.lastPathComponent == "Still-abc" }?.logicalBytes == 500)
    // Archives and project source are never candidates.
    #expect(!found.contains { !$0.url.path.hasPrefix(home.appendingPathComponent(derivedData).path + "/") })
}

/// Stands in for the process list: an owner runs when any of these command lines belongs to it.
private struct Processes: RunningAppChecking {
    let commandLines: [[String]]
    func isRunning(_ owner: RuleOwner) -> Bool? { commandLines.contains { owner.matches($0) } }
}

@Test func xcodeAndItsBuildProcessesOwnDerivedDataButOtherToolsDoNot() throws {
    let owner = try #require(BuiltInCatalog.rules.first { $0.id == "xcode-derived-data" }?.owner)
    #expect(owner.bundleIDs == ["com.apple.dt.Xcode"])
    let builds: [[String]] = [
        ["/Applications/Xcode.app/Contents/MacOS/Xcode"],
        ["/Applications/Xcode-beta.app/Contents/MacOS/Xcode"],
        ["/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", "build"],
        ["/usr/bin/xcodebuild", "test"],
        ["/Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/MacOS/SWBBuildService"],
        ["/Applications/Xcode.app/Contents/SharedFrameworks/XCBuild.framework/PlugIns/XCBBuildService.bundle/Contents/MacOS/XCBBuildService"],
        ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend", "-frontend", "-c"],
        ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang", "-c", "x.m"],
        ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld"],
        ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil", "Still"],
    ]
    for argv in builds { #expect(owner.matches(argv), "should see \(argv)") }
    for argv in [["/Applications/Visual Studio Code.app/Contents/MacOS/Electron"], ["/opt/homebrew/bin/node", "xcode.js"], ["/usr/bin/swift-format"]] {
        #expect(!owner.matches(argv), "should ignore \(argv)")
    }
}

@Test func derivedDataIsRefusedWithAReasonWhileXcodeOrABuildRuns() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, derivedData + "/Still-abc/Build/Intermediates.noindex")
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    let candidate = try #require(catalog.discover(home: home).first)
    let building = Processes(commandLines: [["/usr/bin/xcodebuild", "build"]])
    #expect(CandidateCheck(catalog: catalog, running: building).check(candidate) == .ownerRunning("Xcode"))
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: building))
        .execute(CatalogApproval(candidates: [candidate], previewOnly: false))
    let record = try #require(result.records.first)
    #expect(record.state == .skipped)
    #expect(record.message == "Xcode is running. Quit it, then scan again.")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(derivedData + "/Still-abc/Build/Intermediates.noindex/entry").path))
    // Once nothing runs, the whole project folder is permanently removed.
    let idle = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: Processes(commandLines: [])))
        .execute(CatalogApproval(candidates: [candidate], previewOnly: false))
    #expect(idle.records.first?.state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(derivedData + "/Still-abc").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(derivedData).path))
}
