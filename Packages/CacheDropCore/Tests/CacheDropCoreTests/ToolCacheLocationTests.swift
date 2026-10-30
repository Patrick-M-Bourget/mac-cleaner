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

private func execute(_ candidate: Candidate, catalog: Catalog, home: URL) async throws -> CleanupRecord {
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: FixtureSameVolume().read, trash: TrashNeverUsed())
    return try #require(await run.execute(CatalogApproval(candidates: [candidate], dryRun: false)).records.first)
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
    // Where the folder came from is on the item, so the plan stays quiet (#206).
    #expect(found.first?.folderSource == "Location from npm")
    #expect(!discovery.notes.contains { $0.ruleID == "npm-cache" })

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
    // The tool confirmed it, and the item says so (#206).
    #expect(discovery.candidates.first { $0.ruleID == "npm-cache" }?.folderSource == "Location from npm")
}

/// npm with a short time limit on its question, so a stand-in that hangs is stopped quickly.
private func npmRuleAskingWithin(_ timeout: TimeInterval) throws -> Catalog {
    var rules = fixtureRules
    let index = try #require(rules.firstIndex { $0.id == "npm-cache" })
    let rule = rules[index], asker = try #require(rule.locationTool)
    rules[index] = CleanupRule(id: rule.id, category: rule.category, title: rule.title, detail: rule.detail, consequence: rule.consequence, regen: rule.regen, action: rule.action,
                               locations: rule.locations, owner: rule.owner,
                               locationTool: LocationTool(executables: asker.executables,
                                                          query: LocationQuery(asker.query.arguments, timeout: timeout, whenUnanswered: asker.query.whenUnanswered,
                                                                               reportedSubfolder: asker.query.reportedSubfolder)))
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
        #expect(discovery.notes == [CatalogNote(ruleID: "npm-cache", text: "npm didn’t say where its cache is, so its default folder is shown.")], "\(answer)")
    }
}

@Test func withoutNPMItsUsualFolderIsOfferedAndThePlanSaysSo() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(!Catalog(rules: fixtureRules).discovery(fixture: home).notes.contains { $0.ruleID == "npm-cache" })
    try makeFolder(home, ".npm/_cacache")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home)
    #expect(discovery.candidates.contains { $0.ruleID == "npm-cache" })
    #expect(discovery.notes == [CatalogNote(ruleID: "npm-cache", text: "CacheDrop couldn’t find npm, so its default cache folder is shown.")])
    #expect(discovery.candidates.first { $0.ruleID == "npm-cache" }?.folderSource == "Default location")
}

/// Only each tool's known install locations are asked, never whatever is on a PATH.
@Test func onlyToolsInTheirKnownLocationsAreAsked() throws {
    let catalog = Catalog(rules: fixtureRules)
    let askers = try ["npm-cache", "pip-cache", "pnpm-store", "homebrew", "uv-cache"].map { try #require(catalog.rule($0)?.locationAsker?.tool, "\($0)") }
    #expect(askers.map(\.executables) == [
        ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"],
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Developer/CommandLineTools/usr/bin/python3"],
        ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm", NSHomeDirectory() + "/Library/pnpm/pnpm"],
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
        [NSHomeDirectory() + "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.cargo/bin/uv"],
    ])
    #expect(askers.map { ([$0.name] + $0.query.arguments).joined(separator: " ") }
            == ["npm config get cache", "python3 -m pip cache dir", "pnpm store path", "brew --cache", "uv cache dir"])
    // A tool on PATH but not in a known location is never found.
    #expect(ToolCommand.installed(LocationTool(executables: ["npm"], query: LocationQuery(["config", "get", "cache"])).lookup) == nil)
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
        ("\(outside.path)/npm", "npm names \(outside.path)/npm/_cacache as its cache, which is outside your home folder, so it isn’t offered."),
        ("\(home.path)/linked", "npm names ~/linked/_cacache as its cache, which is outside your home folder, so it isn’t offered."),
        ("\(home.path)/missing", "npm names ~/missing/_cacache as its cache, but there’s no folder there, so it isn’t offered."),
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
        #expect(discovery.notes.filter { $0.ruleID == "pip-cache" } == [CatalogNote(ruleID: "pip-cache", text: "pip names \(shown) as its cache, which holds more than its cache, so it isn’t offered.")], "\(answer)")
    }
}

@Test func aCustomPipCacheIsFoundAndCleaned() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    try makeFolder(home, ".pip-cache/http-v2", bytes: 700)
    let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(home.path)/.pip-cache'")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("python3", python))
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "pip-cache" })
    #expect(candidate.url.path == home.appendingPathComponent(".pip-cache").path && candidate.logicalBytes == 700)
    #expect(candidate.folderSource == "Location from pip" && discovery.notes.isEmpty)
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
    #expect(candidate.folderSource == "Location from pnpm" && discovery.notes.isEmpty)
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "store prune\n")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Developer/pnpm-store/v10/entry").path))
}

/// Homebrew's cleanup runs, then the cache folder brew names is removed, not the usual one.
@Test func aCustomHomebrewCacheIsFoundAndCleaned() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew")
    try makeFolder(home, ".brew-cache/downloads")
    let marker = home.appendingPathComponent("ran")
    let brew = try fakeTool(home, "brew", asked: "--cache", query: "echo '\(home.path)/.brew-cache'", otherwise: "echo \"$@\" > '\(marker.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("brew", brew))
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "homebrew" })
    #expect(candidate.url.path == home.appendingPathComponent(".brew-cache").path)
    #expect(candidate.folderSource == "Location from Homebrew" && discovery.notes.isEmpty)
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "cleanup -s\n")
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".brew-cache").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
}

/// A folder pip or Homebrew names is deleted, so it is offered only when it looks like that tool's cache (#205): never inside
/// a folder for the user's own files, at any depth, and only when it holds an entry the tool's docs describe.
@Test func aFolderPipOrHomebrewNamesIsOfferedOnlyWhenItLooksLikeTheirCache() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    try makeFolder(home, "Library/Caches/Homebrew")
    // Marker names inside user folders don't make them caches.
    try makeFolder(home, "Documents/proj/http-v2")
    try makeFolder(home, "Documents/proj/downloads")
    try makeFolder(home, "Desktop/x/y/wheels")
    try makeFolder(home, "Desktop/x/y/api")
    try makeFolder(home, "code/src")
    let catalog = Catalog(rules: fixtureRules)
    let cases: [(String, String)] = [
        ("Documents/proj", "which is inside your Documents folder"),
        ("Desktop/x/y", "which is inside your Desktop folder"),
        ("code", "which doesn’t look like its cache"),
    ]
    for (folder, why) in cases {
        let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(home.path)/\(folder)'")
        let pip = catalog.discovery(fixture: home, locateTool: onlyTool("python3", python))
        #expect(!pip.candidates.contains { $0.ruleID == "pip-cache" }, "\(folder)")
        #expect(pip.notes.filter { $0.ruleID == "pip-cache" }
                == [CatalogNote(ruleID: "pip-cache", text: "pip names ~/\(folder) as its cache, \(why), so it isn’t offered.")], "\(folder)")
        let brew = try fakeTool(home, "brew", asked: "--cache", query: "echo '\(home.path)/\(folder)'")
        let homebrew = catalog.discovery(fixture: home, locateTool: onlyTool("brew", brew))
        #expect(!homebrew.candidates.contains { $0.ruleID == "homebrew" }, "\(folder)")
        #expect(homebrew.notes.filter { $0.ruleID == "homebrew" }
                == [CatalogNote(ruleID: "homebrew", text: "Homebrew names ~/\(folder) as its cache, \(why), so it isn’t offered.")], "\(folder)")
    }
}

/// npm's `_cacache` is deleted too, so a folder npm names inside the user's own folders is refused whatever it holds (#205).
@Test func anNPMCacheInsideTheUsersOwnFoldersIsNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Documents/proj/_cacache")
    let npm = try fakeNPM(home, answer: "echo '\(home.path)/Documents/proj'")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: onlyTool("npm", npm))
    #expect(!discovery.candidates.contains { $0.ruleID == "npm-cache" })
    #expect(discovery.notes == [CatalogNote(ruleID: "npm-cache",
                                            text: "npm names ~/Documents/proj/_cacache as its cache, which is inside your Documents folder, so it isn’t offered.")])
}

/// Each tool's real cache layout is still offered: any one entry its docs describe is enough (#205).
@Test func realPipAndHomebrewCacheLayoutsAreStillOffered() throws {
    let catalog = Catalog(rules: fixtureRules)
    for (tool, asked, ruleID, marker) in [("python3", "-m pip cache dir", "pip-cache", "http-v2"), ("python3", "-m pip cache dir", "pip-cache", "http"),
                                          ("python3", "-m pip cache dir", "pip-cache", "wheels"), ("brew", "--cache", "homebrew", "downloads"),
                                          ("brew", "--cache", "homebrew", "api")] {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeFolder(home, "Developer/caches/\(ruleID)/\(marker)")
        let fake = try fakeTool(home, tool, asked: asked, query: "echo '\(home.path)/Developer/caches/\(ruleID)'")
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool(tool, fake))
        #expect(discovery.candidates.filter { $0.ruleID == ruleID }.map(\.url.path) == [home.appendingPathComponent("Developer/caches/\(ruleID)").path], "\(ruleID) \(marker)")
    }
}

/// Prune-only tools keep their folder, so the cache-look rule doesn't apply to them (#205).
@Test func aPnpmStoreWithoutMarkersIsStillOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "code/store")
    let pnpm = try fakeTool(home, "pnpm", asked: "store path", query: "echo '\(home.path)/code/store'")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: onlyTool("pnpm", pnpm))
    #expect(discovery.candidates.filter { $0.ruleID == "pnpm-store" }.map(\.url.path) == [home.appendingPathComponent("code/store").path])
}

/// `pnpm store path` names a versioned folder inside the usual store (`~/Library/pnpm/store/v10`): that is the usual store,
/// so there's no note and the whole store is the item (#206).
@Test func aDefaultPnpmInstallIsTheUsualStore() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/pnpm/store/v10")
    let pnpm = try fakeTool(home, "pnpm", asked: "store path", query: "echo '\(home.path)/Library/pnpm/store/v10'")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: onlyTool("pnpm", pnpm))
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "pnpm-store" })
    #expect(candidate.url.path == home.appendingPathComponent("Library/pnpm/store").path)
    #expect(candidate.folderSource == "Location from pnpm")
    #expect(!discovery.notes.contains { $0.ruleID == "pnpm-store" })
}

// MARK: - #201: a cache location set in the tool's config file, read without running anything

private func writeConfig(_ home: URL, _ relative: String, _ text: String) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: file, atomically: true, encoding: .utf8)
}

/// Without npm in a known location, `cache=` in ~/.npmrc names the folder; nothing is run.
@Test func anNPMCacheSetInNpmrcIsOfferedWhenNPMIsntFound() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".npm/_cacache")
    try makeFolder(home, ".npm-custom/_cacache", bytes: 900)
    try writeConfig(home, ".npmrc", "; my settings\nregistry=https://registry.npmjs.org/\ncache = ~/.npm-custom\n")
    let catalog = Catalog(rules: fixtureRules)
    let discovery = catalog.discovery(fixture: home)
    let candidate = try #require(discovery.candidates.first { $0.ruleID == "npm-cache" })
    #expect(discovery.candidates.filter { $0.ruleID == "npm-cache" }.count == 1)
    #expect(candidate.url.path == home.appendingPathComponent(".npm-custom/_cacache").path && candidate.logicalBytes == 900)
    #expect(candidate.folderSource == "Set in ~/.npmrc")
    #expect(!discovery.notes.contains { $0.ruleID == "npm-cache" })
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm-custom/_cacache").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".npm/_cacache/entry").path))
}

/// A malicious or mistaken `cache=` is held to #205's write-scope checks: it is refused, and the usual folder isn't offered instead.
@Test func anNPMCacheSetToTheUsersOwnFoldersIsRefused() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".npm/_cacache")
    try makeFolder(home, "Documents/_cacache")
    try makeFolder(home, "Desktop/work/_cacache")
    let catalog = Catalog(rules: fixtureRules)
    let cases: [(String, String)] = [
        ("cache=~/Documents", "~/.npmrc sets ~/Documents/_cacache as npm’s cache, which is inside your Documents folder, so it isn’t offered."),
        ("cache=\(home.path)/Desktop/work", "~/.npmrc sets ~/Desktop/work/_cacache as npm’s cache, which is inside your Desktop folder, so it isn’t offered."),
        ("cache=~/nowhere", "~/.npmrc sets ~/nowhere/_cacache as npm’s cache, but there’s no folder there, so it isn’t offered."),
        ("cache=${NPM_CACHE}", "~/.npmrc sets npm’s cache in a way CacheDrop can’t follow, so it isn’t offered."),
        ("cache=relative/dir", "~/.npmrc sets npm’s cache in a way CacheDrop can’t follow, so it isn’t offered."),
    ]
    for (line, note) in cases {
        try writeConfig(home, ".npmrc", line + "\n")
        let discovery = catalog.discovery(fixture: home)
        #expect(!discovery.candidates.contains { $0.ruleID == "npm-cache" }, "\(line)")
        #expect(discovery.notes.filter { $0.ruleID == "npm-cache" } == [CatalogNote(ruleID: "npm-cache", text: note)], "\(line)")
    }
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents/_cacache/entry").path))
}

/// pip reads ~/Library/Application Support/pip when that folder exists, else ~/.config/pip (pip's `appdirs.user_config_dir`).
@Test func aPipCacheSetInPipConfIsOfferedWhenPipIsntFound() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    try makeFolder(home, ".pip-xdg/http-v2", bytes: 300)
    try makeFolder(home, ".pip-mac/wheels", bytes: 500)
    let catalog = Catalog(rules: fixtureRules)
    try writeConfig(home, ".config/pip/pip.conf", "[install]\ncache-dir = ~/elsewhere\n[global]\ntimeout = 60\ncache-dir = ~/.pip-xdg\n")
    let xdg = catalog.discovery(fixture: home)
    let fromXDG = try #require(xdg.candidates.first { $0.ruleID == "pip-cache" })
    #expect(fromXDG.url.path == home.appendingPathComponent(".pip-xdg").path && fromXDG.folderSource == "Set in ~/.config/pip/pip.conf")
    #expect(!xdg.notes.contains { $0.ruleID == "pip-cache" })

    try writeConfig(home, "Library/Application Support/pip/pip.conf", "[global]\ncache_dir: \(home.path)/.pip-mac\n")
    let mac = catalog.discovery(fixture: home)
    #expect(mac.candidates.filter { $0.ruleID == "pip-cache" }.map(\.url.path) == [home.appendingPathComponent(".pip-mac").path])
    #expect(mac.candidates.first { $0.ruleID == "pip-cache" }?.folderSource == "Set in ~/Library/Application Support/pip/pip.conf")
}

/// A pip.conf `cache-dir` must look like pip's cache and must not be inside the user's own folders (#205).
@Test func aPipCacheSetToSomethingThatIsntItsCacheIsRefused() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    try makeFolder(home, "Documents/proj/http-v2")
    try makeFolder(home, "code/src")
    let catalog = Catalog(rules: fixtureRules)
    let cases: [(String, String)] = [
        ("~/Documents/proj", "~/.config/pip/pip.conf sets ~/Documents/proj as pip’s cache, which is inside your Documents folder, so it isn’t offered."),
        ("~/code", "~/.config/pip/pip.conf sets ~/code as pip’s cache, which doesn’t look like its cache, so it isn’t offered."),
        ("~", "~/.config/pip/pip.conf sets \(home.path) as pip’s cache, which holds more than its cache, so it isn’t offered."),
    ]
    for (value, note) in cases {
        try writeConfig(home, ".config/pip/pip.conf", "[global]\ncache-dir = \(value)\n")
        let discovery = catalog.discovery(fixture: home)
        #expect(!discovery.candidates.contains { $0.ruleID == "pip-cache" }, "\(value)")
        #expect(discovery.notes.filter { $0.ruleID == "pip-cache" } == [CatalogNote(ruleID: "pip-cache", text: note)], "\(value)")
    }
}

/// A config that doesn't set the cache leaves the usual folder, which is where the tool keeps it unless it was set otherwise.
@Test func aConfigWithoutACacheSettingKeepsTheUsualFolder() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".npm/_cacache")
    try writeConfig(home, ".npmrc", "registry=https://registry.npmjs.org/\n# cache=~/Documents\n")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home)
    #expect(discovery.candidates.filter { $0.ruleID == "npm-cache" }.map(\.url.path) == [home.appendingPathComponent(".npm/_cacache").path])
    #expect(discovery.notes == [CatalogNote(ruleID: "npm-cache", text: "CacheDrop couldn’t find npm, so its default cache folder is shown.")])
}

/// The write-scope checks run again just before acting: a configured pip cache that no longer looks like one is kept.
@Test func theCheckBeforeActingRefusesAConfiguredFolderThatNoLongerLooksLikeACache() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".pip-cache/http-v2")
    try writeConfig(home, ".config/pip/pip.conf", "[global]\ncache-dir = ~/.pip-cache\n")
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home).first { $0.ruleID == "pip-cache" })
    try FileManager.default.removeItem(at: home.appendingPathComponent(".pip-cache/http-v2"))
    try makeFolder(home, ".pip-cache/notes")
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning()).check(candidate) == .notACache("It doesn’t look like pip’s cache, so it is kept."))
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .skipped)
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".pip-cache/notes/entry").path))
}

/// What an interrupted clean of a folder a tool names left behind is looked for next to that folder too, not only next to
/// the usual one (#202). The folder itself is renamed aside first, so it may be missing, and the half-deleted rest may no
/// longer hold the tool's cache markers: the leftover's name is CacheDrop's own, and the write-scope checks still apply.
@Test func leftoversNextToAFolderAToolNamesAreFoundAndCleaned() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    let leftover = ".cachedrop-deleting-pip-cache-\(UUID().uuidString)"
    try makeFolder(home, "Developer/caches/\(leftover)", bytes: 400)
    let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(home.path)/Developer/caches/pip'")
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discovery(fixture: home, locateTool: onlyTool("python3", python)).candidates.filter { $0.ruleID == "pip-cache" }
    let candidate = try #require(found.first)
    #expect(found.map(\.url.path) == [home.appendingPathComponent("Developer/caches/\(leftover)").path])
    #expect(candidate.isLeftover && candidate.action == .delete && candidate.logicalBytes == 400)
    #expect(try await execute(candidate, catalog: catalog, home: home).state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Developer/caches/\(leftover)").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/pip/entry").path))

    // Homebrew's cache is renamed aside after `brew cleanup -s` too; its rest is offered as a plain delete.
    try makeFolder(home, "Library/Caches/Homebrew")
    let brewLeftover = ".cachedrop-deleting-homebrew-\(UUID().uuidString)"
    try makeFolder(home, ".brew-parent/\(brewLeftover)")
    try makeFolder(home, ".brew-parent/cache/downloads")
    let brew = try fakeTool(home, "brew", asked: "--cache", query: "echo '\(home.path)/.brew-parent/cache'")
    let homebrew = catalog.discovery(fixture: home, locateTool: onlyTool("brew", brew)).candidates.filter { $0.ruleID == "homebrew" }
    #expect(Set(homebrew.map(\.url.path)) == [home.appendingPathComponent(".brew-parent/cache").path, home.appendingPathComponent(".brew-parent/\(brewLeftover)").path])
    #expect(homebrew.first { $0.isLeftover }?.action == .delete)
}

/// Leftovers next to a named folder pass the same write-scope checks as the folder (#202, #205): none inside the user's own
/// folders, none outside home, none next to a folder that holds more than the tool's cache.
@Test func leftoversNextToANamedFolderOutsideTheWriteScopeAreNeverOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let outside = home.deletingLastPathComponent().appendingPathComponent(".cachedrop-deleting-pip-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outside) }
    let documents = "Documents/proj/.cachedrop-deleting-pip-cache-\(UUID().uuidString)"
    try makeFolder(home, documents)
    let library = "Library/.cachedrop-deleting-pip-cache-\(UUID().uuidString)"
    try makeFolder(home, library)
    try makeFolder(home, "Library/Caches/x")
    let catalog = Catalog(rules: fixtureRules)
    for named in ["\(home.path)/Documents/proj/pip", home.path, "\(home.path)/Library/Caches"] {
        let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(named)'")
        let discovery = catalog.discovery(fixture: home, locateTool: onlyTool("python3", python))
        #expect(!discovery.candidates.contains { $0.ruleID == "pip-cache" }, "\(named)")
    }
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(documents).path))
}

/// A leftover is checked again just before acting with the same write-scope checks, but not for the tool's markers: a
/// half-deleted cache may have lost them (#202).
@Test func theCheckBeforeActingDoesNotAskALeftoverForCacheMarkers() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let leftover = "Library/Caches/.cachedrop-deleting-pip-cache-\(UUID().uuidString)"
    try makeFolder(home, leftover)
    try makeFolder(home, "Library/Caches/pip")
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home).first { $0.isLeftover && $0.ruleID == "pip-cache" })
    let refusal = CandidateCheck(catalog: catalog, running: FixtureNothingRunning()).check(candidate)
    #expect(refusal == nil, "\(String(describing: refusal))")
}

/// A leftover next to a named folder that fails the write-scope checks is refused just before acting too, not only left out
/// of the scan (#262), and so is one that is a file: discovery offers file leftovers as well as folders. The candidate is
/// built where the scan would never offer it: a leftover moved after the scan is already refused as missing or changed,
/// since the check reads its scanned path without following links, so this branch only guards a candidate that is wrong.
@Test func theCheckBeforeActingRefusesALeftoverFolderOrFileInsideAUserFolder() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = "Documents/proj/.cachedrop-deleting-pip-cache-\(UUID().uuidString)"
    try makeFolder(home, folder)
    let file = home.appendingPathComponent("Documents/proj/.cachedrop-deleting-pip-cache-\(UUID().uuidString)")
    try Data(repeating: 1, count: 100).write(to: file)
    let catalog = Catalog(rules: fixtureRules)
    let rule = try #require(catalog.rule("pip-cache"))
    for url in [home.appendingPathComponent(folder), file] {
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        let candidate = catalog.candidate(rule, url, info, logical: 100, allocated: nil, complete: true, lastUsed: nil, action: .delete).found(under: home)
        #expect(candidate.isLeftover)
        #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning()).check(candidate) == .notACache("It is inside your Documents folder, so it is kept."), "\(url.lastPathComponent)")
        #expect(try await execute(candidate, catalog: catalog, home: home).state == .skipped)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

/// A folder pip or Homebrew named must still hold that tool's cache markers when it is cleaned, not only when it was found
/// (#217): one whose markers vanished between the scan and the clean is refused, and Homebrew's cleanup never runs.
@Test func aNamedFolderWhoseMarkersVanishBetweenScanAndCleanIsRefused() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, ".pip-cache/http-v2")
    try makeFolder(home, ".brew-cache/downloads")
    let ran = home.appendingPathComponent("ran")
    let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(home.path)/.pip-cache'")
    let brew = try fakeTool(home, "brew", asked: "--cache", query: "echo '\(home.path)/.brew-cache'", otherwise: "echo \"$@\" > '\(ran.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let pip = try #require(catalog.discovery(fixture: home, locateTool: onlyTool("python3", python)).candidates.first { $0.ruleID == "pip-cache" })
    let homebrew = try #require(catalog.discovery(fixture: home, locateTool: onlyTool("brew", brew)).candidates.first { $0.ruleID == "homebrew" })
    #expect(pip.folderSource == "Location from pip" && homebrew.folderSource == "Location from Homebrew")
    for (folder, marker) in [(".pip-cache", "http-v2"), (".brew-cache", "downloads")] {
        try FileManager.default.removeItem(at: home.appendingPathComponent("\(folder)/\(marker)"))
        try makeFolder(home, "\(folder)/notes")
    }
    let check = CandidateCheck(catalog: catalog, running: FixtureNothingRunning())
    #expect(check.check(pip) == .notACache("It doesn’t look like pip’s cache, so it is kept."))
    #expect(check.check(homebrew) == .notACache("It doesn’t look like Homebrew’s cache, so it is kept."))
    #expect(try await execute(pip, catalog: catalog, home: home).state == .skipped)
    #expect(try await execute(homebrew, catalog: catalog, home: home).state == .skipped)
    #expect(!FileManager.default.fileExists(atPath: ran.path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".pip-cache/notes/entry").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".brew-cache/notes/entry").path))
}

/// A named folder moved into one of the user's own folders since the scan, and reached at its old path through a link,
/// is refused at clean time too (#217).
@Test func aNamedFolderNowReachedInsideAUserFolderIsRefusedAtCleanTime() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "work/pip/http-v2")
    try makeFolder(home, "Documents")
    let python = try fakeTool(home, "python3", asked: "-m pip cache dir", query: "echo '\(home.path)/work/pip'")
    let catalog = Catalog(rules: fixtureRules)
    let pip = try #require(catalog.discovery(fixture: home, locateTool: onlyTool("python3", python)).candidates.first { $0.ruleID == "pip-cache" })
    try FileManager.default.moveItem(at: home.appendingPathComponent("work"), to: home.appendingPathComponent("Documents/work"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("work"), withDestinationURL: home.appendingPathComponent("Documents/work"))
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning()).check(pip) != nil)
    #expect(try await execute(pip, catalog: catalog, home: home).state == .skipped)
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents/work/pip/http-v2/entry").path))
}
