import Foundation
import Testing
import CacheDropCore

/// A temp home folder; tests never read or write the real home or the real Xcode folders.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropXcode-\(UUID())")
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
    let catalog = Catalog(rules: fixtureRules)
    try makeFolder(home, "Library/Developer/Xcode/Archives/2026-10-01/CacheDrop.xcarchive/dSYMs/CacheDrop.app.dSYM")
    try makeFolder(home, "Library/Developer/Xcode/UserData/CodeSnippets")
    try makeFolder(home, "Projects/CacheDrop/CacheDrop.xcodeproj")
    #expect(catalog.discover(fixture: home).isEmpty)
    // Built products and dSYMs inside DerivedData are regenerable (Decision 22).
    try makeFolder(home, derivedData + "/CacheDrop-abc/Build/Products/Debug/CacheDrop.app/Contents/MacOS", bytes: 300)
    try makeFolder(home, derivedData + "/CacheDrop-abc/Build/Products/Debug/CacheDrop.app.dSYM", bytes: 200)
    try makeFolder(home, derivedData + "/Other-def/Index.noindex")
    try makeFolder(home, derivedData + "/ModuleCache.noindex")
    try Data(repeating: 1, count: 10).write(to: home.appendingPathComponent(derivedData + "/stray-file"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(derivedData + "/Linked-ghi"),
                                               withDestinationURL: home.appendingPathComponent("Projects/CacheDrop"))
    let found = catalog.discover(fixture: home)
    #expect(Set(found.map(\.url.lastPathComponent)) == ["CacheDrop-abc", "Other-def", "ModuleCache.noindex"])
    #expect(found.allSatisfy { $0.ruleID == "xcode-derived-data" && $0.action == .delete && $0.isDirectory })
    #expect(found.first { $0.url.lastPathComponent == "CacheDrop-abc" }?.logicalBytes == 500)
    // Archives and project source are never candidates.
    #expect(!found.contains { !$0.url.path.hasPrefix(home.appendingPathComponent(derivedData).path + "/") })
}

/// Stands in for the process list: an owner runs when any of these command lines belongs to it.
private struct Processes: RunningAppChecking {
    let commandLines: [[String]]
    func isRunning(_ owner: RuleOwner) -> Bool? { commandLines.contains { owner.matches($0) } }
}

@Test func xcodeAndItsBuildProcessesOwnDerivedDataButOtherToolsDoNot() throws {
    let owner = try #require(fixtureRules.first { $0.id == "xcode-derived-data" }?.owner)
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
        ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil", "CacheDrop"],
    ]
    for argv in builds { #expect(owner.matches(argv), "should see \(argv)") }
    for argv in [["/Applications/Visual Studio Code.app/Contents/MacOS/Electron"], ["/opt/homebrew/bin/node", "xcode.js"], ["/usr/bin/swift-format"]] {
        #expect(!owner.matches(argv), "should ignore \(argv)")
    }
}

@Test func derivedDataIsRefusedWithAReasonWhileXcodeOrABuildRuns() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, derivedData + "/CacheDrop-abc/Build/Intermediates.noindex")
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home).first)
    let building = Processes(commandLines: [["/usr/bin/xcodebuild", "build"]])
    #expect(CandidateCheck(catalog: catalog, running: building).check(candidate) == .ownerRunning("Xcode"))
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: building), trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: [candidate], previewOnly: false))
    let record = try #require(result.records.first)
    #expect(record.state == .skipped)
    #expect(record.message == "Xcode is running. Quit it, then scan again.")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(derivedData + "/CacheDrop-abc/Build/Intermediates.noindex/entry").path))
    // Once nothing runs, the whole project folder is permanently removed.
    let idle = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: Processes(commandLines: [])), trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: [candidate], previewOnly: false))
    #expect(idle.records.first?.state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(derivedData + "/CacheDrop-abc").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(derivedData).path))
}

@Test func deviceSupportKeepsTheTwoNewestVersionsOfEachPlatform() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let ios = "Library/Developer/Xcode/iOS DeviceSupport/"
    // Older Xcode names folders "<version> (<build>)"; newer ones prefix the device model.
    for name in ["16.4 (20E247)", "17.0 (21A329)", "iPhone15,2 17.0.1 (21A340)", "17.5 (21F79)", "iPhone15,2 18.1 (22B83)", "iPhone16,1 18.1 (22B83)", "Unknown"] {
        try makeFolder(home, ios + name)
    }
    try makeFolder(home, "Library/Developer/Xcode/watchOS DeviceSupport/Watch6,1 10.0 (21R356)")
    try makeFolder(home, "Library/Developer/Xcode/watchOS DeviceSupport/Watch6,1 9.6 (20U73)")
    try makeFolder(home, "Library/Developer/Xcode/watchOS DeviceSupport/Watch6,1 9.1 (20S75)")
    let found = Catalog(rules: fixtureRules).discover(fixture: home)
    #expect(found.allSatisfy { $0.ruleID == "xcode-device-support" && $0.action == .delete })
    // 18.1 and 17.5 stay for iOS, 10.0 and 9.6 for watchOS; a name without a version is never offered.
    #expect(Set(found.map(\.url.lastPathComponent)) == ["16.4 (20E247)", "17.0 (21A329)", "iPhone15,2 17.0.1 (21A340)", "Watch6,1 9.1 (20S75)"])
}

/// A stand-in simctl inside the fixture; tests never run the real one.
private func fakeSimctl(_ home: URL, _ script: String) throws -> URL {
    let tool = home.appendingPathComponent("tools/simctl")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ("#!/bin/sh\n" + script + "\n").write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}
private let devices = "Library/Developer/CoreSimulator/Devices"

@Test func unavailableSimulatorsAreOfferedOnlyWithSimctlAndTheirSizeIsUnknown() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: fixtureRules)
    let simctl = try fakeSimctl(home, "exit 0")
    try makeFolder(home, devices + "/0A1B2C3D-0000-0000-0000-000000000000/data", bytes: 5000)
    #expect(catalog.discover(fixture: home, locateTool: { _ in nil }).isEmpty)
    let candidate = try #require(catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).first)
    #expect(candidate.ruleID == "xcode-simulators")
    #expect(candidate.action == .tool)
    // simctl removes only the unavailable devices, so the folder's total isn't what it frees. Without simctl's list
    // (this stand-in prints none) their size is unknown; with it, they are sized (#209, DeveloperDevicesTests).
    #expect(SizeEstimate(candidate) == .unknown)
    let tool = try #require(catalog.rule("xcode-simulators")?.tool)
    #expect(tool.commandLine == "simctl delete unavailable")
    #expect(tool.deletesLocationAfter == false)
}

@Test func simulatorCleanupRunsThroughTheToolActionAndReportsItsResult() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, devices + "/0A1B2C3D-0000-0000-0000-000000000000/data")
    let marker = home.appendingPathComponent("ran")
    // Discovery also lists simulators (#134); only the cleanup command is recorded.
    let simctl = try fakeSimctl(home, "[ \"$1\" = list ] || [ \"$1\" = runtime ] && exit 1\necho \"$@\" > '\(marker.path)'\necho 'Deleted: iPhone 12 (0A1B2C3D)'")
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).first)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: catalog, running: FixtureNothingRunning())

    let preview = await CleanupExecutor(journal: journal, check: check, trash: TrashNeverUsed()).execute(CatalogApproval(candidates: [candidate], previewOnly: true))
    #expect(preview.records.first?.message.hasPrefix("Dry run: would run simctl delete unavailable") == true)
    #expect(!FileManager.default.fileExists(atPath: marker.path))

    let result = await CleanupExecutor(journal: journal, check: check, trash: TrashNeverUsed()).execute(CatalogApproval(candidates: [candidate], previewOnly: false))
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded)
    #expect(record.message == "Ran simctl delete unavailable")
    #expect(record.toolOutput == "Deleted: iPhone 12 (0A1B2C3D)")
    #expect(try String(contentsOf: marker, encoding: .utf8) == "delete unavailable\n")
    // The tool decides what goes; CacheDrop never deletes the Devices folder itself.
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(devices + "/0A1B2C3D-0000-0000-0000-000000000000/data/entry").path))
}
