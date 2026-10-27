import Foundation
import Testing
@testable import CacheDropCore

/// Developer tools are asked where their cache is (#170): npm, pip, pnpm and Homebrew name the folder, and a custom one
/// is found and cleaned. Every tool here is a stand-in script in a temp fixture; the real tools and caches are never touched.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropToolCache-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func makeFolder(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative).appendingPathComponent("entry")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
/// A stand-in tool named `name`: `query` runs when it's called with `asked` (its location question), `otherwise` for anything else.
private func fakeTool(_ home: URL, _ name: String, asked: String, query: String, otherwise: String = "exit 0") throws -> URL {
    let tool = home.appendingPathComponent("tools/\(name)")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    let script = "#!/bin/sh\nif [ \"$*\" = \"\(asked)\" ]; then\n\(query)\nelse\n\(otherwise)\nfi\n"
    try script.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}
private func fakeNPM(_ home: URL, answer: String) throws -> URL { try fakeTool(home, "npm", asked: "config get cache", query: answer) }
private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }
private struct SameVolume { func read(_ url: URL) -> CapacitySample? { CapacitySample(available: 1_000, total: 10_000, volumeID: "fake", metric: .important, date: Date()) } }

private func execute(_ candidate: Candidate, catalog: Catalog, home: URL) async throws -> CleanupRecord {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NothingRunning()), measure: SameVolume().read, trash: TrashNeverUsed())
    return try #require(await run.execute(CatalogApproval(candidates: [candidate], previewOnly: false)).records.first)
}

@Test func aCustomNPMCacheIsFoundAndCleanedAndThePlanSaysNPMNamedIt() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".npm/_cacache")
    try makeFolder(home, "Developer/npm-cache/_cacache", bytes: 3000)
    let npm = try fakeNPM(home, answer: "echo '\(home.path)/Developer/npm-cache'")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("npm", npm))
    let found = discovery.candidates.filter { $0.ruleID == "npm-cache" }
    #expect(found.map(\.url.path) == [home.appendingPathComponent("Developer/npm-cache/_cacache").path])
    #expect(found.first?.logicalBytes == 3000)
    #expect(discovery.notes.filter { $0.ruleID == "npm-cache" }
            == [CatalogNote(ruleID: "npm-cache", text: "npm keeps its cache in ~/Developer/npm-cache/_cacache, as `npm config get cache` says.")])

    let record = try await execute(try #require(found.first), catalog: catalog, home: home)
    #expect(record.state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Developer/npm-cache/_cacache").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache/entry").path))
}

@Test func whenNPMNamesItsUsualFolderThatFolderIsOfferedWithNoNote() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".npm/_cacache")
    let npm = try fakeNPM(home, answer: "echo '\(home.path)/.npm'")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: onlyTool("npm", npm))
    #expect(discovery.candidates.filter { $0.ruleID == "npm-cache" }.map(\.url.path) == [home.appendingPathComponent(".npm/_cacache").path])
    #expect(!discovery.notes.contains { $0.ruleID == "npm-cache" })
}

/// npm with a short time limit on its question, so a stand-in that hangs is stopped quickly.
private func npmRuleAskingWithin(_ timeout: TimeInterval) throws -> Catalog {
    var rules = fixtureRules
    let index = try #require(rules.firstIndex { $0.id == "npm-cache" })
    let rule = rules[index], asker = try #require(rule.locationTool)
    rules[index] = CleanupRule(id: rule.id, category: rule.category, title: rule.title, detail: rule.detail, consequence: rule.consequence, regen: rule.regen, action: rule.action,
                               locations: rule.locations, owner: rule.owner,
                               locationTool: ToolCommand(executables: asker.executables, arguments: [], timeout: 0, locationQuery: asker.locationQuery, locationQueryTimeout: timeout,
                                                         whenLocationUnanswered: asker.whenLocationUnanswered, reportedSubfolder: asker.reportedSubfolder))
    return Catalog(rules: rules)
}

/// A cache CacheDrop deletes itself falls back to its usual folder when the tool doesn't answer, and the plan says so,
/// unlike uv's, which is then never offered (Decision 44).
@Test func whenNPMDoesntSayWhereItsCacheIsItsUsualFolderIsOfferedAndThePlanSaysSo() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".npm/_cacache")
    let catalog = try npmRuleAskingWithin(0.3)
    for answer in ["echo 'npm ERR! config' >&2; exit 1", "sleep 5", "echo 'somewhere'", "echo ''", "echo '\(home.path)/../npm'"] {
        let npm = try fakeNPM(home, answer: answer)
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("npm", npm))
        #expect(discovery.candidates.filter { $0.ruleID == "npm-cache" }.map(\.url.path) == [home.appendingPathComponent(".npm/_cacache").path], "\(answer)")
        #expect(discovery.notes == [CatalogNote(ruleID: "npm-cache", text: "npm didn’t say where its cache is (`npm config get cache`), so its usual folder is offered.")], "\(answer)")
    }
}

@Test func withoutNPMItsUsualFolderIsOfferedAndThePlanSaysSo() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(!Catalog(rules: fixtureRules).discovery(fixture: home).notes.contains { $0.ruleID == "npm-cache" })
    try makeFolder(home, ".npm/_cacache")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home)
    #expect(discovery.candidates.contains { $0.ruleID == "npm-cache" })
    #expect(discovery.notes == [CatalogNote(ruleID: "npm-cache", text: "npm wasn’t found, so its usual folder is offered.")])
}

/// Only each tool's known install locations are asked, never whatever is on a PATH.
@Test func onlyToolsInTheirKnownLocationsAreAsked() throws {
    let catalog = Catalog(rules: fixtureRules)
    let askers = try ["npm-cache", "pip-cache", "pnpm-store", "homebrew", "uv-cache"].map { try #require(catalog.rule($0)?.locationAsker, "\($0)") }
    #expect(askers.map(\.executables) == [
        ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"],
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Developer/CommandLineTools/usr/bin/python3"],
        ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm", NSHomeDirectory() + "/Library/pnpm/pnpm"],
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
        [NSHomeDirectory() + "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.cargo/bin/uv"],
    ])
    #expect(askers.map { ([URL(fileURLWithPath: $0.executables[0]).lastPathComponent] + ($0.locationQuery ?? [])).joined(separator: " ") }
            == ["npm config get cache", "python3 -m pip cache dir", "pnpm store path", "brew --cache", "uv cache dir"])
    // A tool on PATH but not in a known location is never found.
    let elsewhere = ToolCommand(executables: ["npm"], arguments: [], timeout: 0, locationQuery: ["config", "get", "cache"])
    #expect(ToolCommand.installed(elsewhere) == nil)
}

/// The write-scope checks are unchanged: a folder outside home, home itself, or one that holds more than the cache is refused.
@Test func aReportedFolderOutsideWhatTheCacheMayTakeIsRefusedAndThePlanSaysWhy() throws {
    let home = try fixtureHome(), outside = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: outside) }
    try makeFolder(home, ".npm/_cacache")
    try makeFolder(outside, "npm/_cacache")
    try makeFolder(home, "_cacache")
    try makeFolder(home, "Library/Caches/_cacache")
    try makeFolder(home, "Library/Caches/pip")
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("linked"), withDestinationURL: outside.appendingPathComponent("npm"))
    let catalog = Catalog(rules: fixtureRules)
    let cases: [(String, String)] = [
        ("\(outside.path)/npm", "npm names \(outside.path)/npm/_cacache as its cache (`npm config get cache`), which is outside your home folder, so it isn’t offered."),
        ("\(home.path)/linked", "npm names ~/linked/_cacache as its cache (`npm config get cache`), which is outside your home folder, so it isn’t offered."),
        ("\(home.path)/missing", "npm names ~/missing/_cacache as its cache (`npm config get cache`), but there’s no folder there, so it isn’t offered."),
    ]
    for (answer, note) in cases {
        let npm = try fakeNPM(home, answer: "echo '\(answer)'")
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("npm", npm))
        #expect(!discovery.candidates.contains { $0.ruleID == "npm-cache" }, "\(answer)")
        #expect(discovery.notes.filter { $0.ruleID == "npm-cache" } == [CatalogNote(ruleID: "npm-cache", text: note)], "\(answer)")
    }
    // pip set to the home folder or to all of Library/Caches would take other data with it.
    for (answer, shown) in [(home.path, home.path), ("\(home.path)/Library/Caches", "~/Library/Caches"), ("\(home.path)/Documents", "~/Documents")] {
        try makeFolder(home, "Documents")
        let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(answer)'")
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("python3", python))
        #expect(!discovery.candidates.contains { $0.ruleID == "pip-cache" }, "\(answer)")
        #expect(discovery.notes.filter { $0.ruleID == "pip-cache" } == [CatalogNote(ruleID: "pip-cache", text: "pip names \(shown) as its cache (`python3 -m pip cache dir`), which holds more than its cache, so it isn’t offered.")], "\(answer)")
    }
}

@Test func aCustomPipCacheIsFoundAndCleaned() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    try makeFolder(home, ".pip-cache", bytes: 700)
    let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(home.path)/.pip-cache'")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("python3", python))
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "pip-cache" })
    #expect(candidate.url.path == home.appendingPathComponent(".pip-cache").path && candidate.logicalBytes == 700)
    #expect(discovery.notes == [CatalogNote(ruleID: "pip-cache", text: "pip keeps its cache in ~/.pip-cache, as `python3 -m pip cache dir` says.")])
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".pip-cache").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/pip/entry").path))
}

/// pnpm's store is pruned with pnpm's own command wherever pnpm keeps it; the folder itself is kept.
@Test func aCustomPnpmStoreIsFoundAndPruned() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Developer/pnpm-store/v10")
    let marker = home.appendingPathComponent("ran")
    let pnpm = try fakeTool(home, "pnpm", asked: "store path", query: "echo '\(home.path)/Developer/pnpm-store/v10'", otherwise: "echo \"$@\" > '\(marker.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("pnpm", pnpm))
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "pnpm-store" })
    #expect(candidate.url.path == home.appendingPathComponent("Developer/pnpm-store/v10").path)
    #expect(discovery.notes == [CatalogNote(ruleID: "pnpm-store", text: "pnpm keeps its cache in ~/Developer/pnpm-store/v10, as `pnpm store path` says.")])
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "store prune\n")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Developer/pnpm-store/v10/entry").path))
}

/// Homebrew's cleanup runs, then the cache folder brew names is removed, not the usual one.
@Test func aCustomHomebrewCacheIsFoundAndCleaned() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew")
    try makeFolder(home, ".brew-cache")
    let marker = home.appendingPathComponent("ran")
    let brew = try fakeTool(home, "brew", asked: "--cache", query: "echo '\(home.path)/.brew-cache'", otherwise: "echo \"$@\" > '\(marker.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("brew", brew))
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "homebrew" })
    #expect(candidate.url.path == home.appendingPathComponent(".brew-cache").path)
    #expect(discovery.notes == [CatalogNote(ruleID: "homebrew", text: "Homebrew keeps its cache in ~/.brew-cache, as `brew --cache` says.")])
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "cleanup -s\n")
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".brew-cache").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
}
