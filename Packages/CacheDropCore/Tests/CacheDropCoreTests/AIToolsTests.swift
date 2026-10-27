import Foundation
import Testing
@testable import CacheDropCore

/// A temp home folder; tests never read the real home, `~/.claude`, `~/.codex` or any agent's caches.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillAITools-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

private struct Running: RunningAppChecking {
    var bundleIDs: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { !bundleIDs.isDisjoint(with: owner.bundleIDs) }
}

private func found(_ catalog: Catalog, _ home: URL, now: Date = Date()) -> [String: String] {
    let prefix = home.path + "/"
    return Dictionary(catalog.discover(fixture: home, now: now).map { (String($0.url.path.dropFirst(prefix.count)), $0.ruleID) },
                      uniquingKeysWith: { a, _ in a })
}

// MARK: Cursor and Windsurf

@Test func cursorAndWindsurfOfferOnlyTheirCacheFoldersAndAreRefusedWhileOpen() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for (app, rule) in [("Cursor", "cursor-cache"), ("Windsurf", "windsurf-cache")] {
        let root = "Library/Application Support/\(app)/"
        for folder in ["Cache", "CachedData", "CachedExtensionVSIXs"] { try write(home, root + folder + "/data", bytes: 2_048) }
        for kept in ["User/settings.json", "User/globalStorage/state.vscdb", "extensions/x/package.json", "Backups/1/file"] { try write(home, root + kept) }
        let catalog = Catalog(rules: fixtureRules)
        #expect(found(catalog, home).filter { $0.value == rule }.keys.sorted() == ["Cache", "CachedData", "CachedExtensionVSIXs"].map { root + $0 })
    }
    let catalog = Catalog(rules: fixtureRules)
    let cursor = try #require(catalog.discover(fixture: home).first { $0.ruleID == "cursor-cache" })
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.todesktop.230313mzl4w4u92"])).check(cursor) == .ownerRunning("Cursor"))
    let windsurf = try #require(catalog.discover(fixture: home).first { $0.ruleID == "windsurf-cache" })
    #expect(CandidateCheck(catalog: catalog, running: Running(bundleIDs: ["com.exafunction.windsurf"])).check(windsurf) == .ownerRunning("Windsurf"))
    #expect(CandidateCheck(catalog: catalog, running: Running()).check(windsurf) == nil)
}

// MARK: Transcripts and logs

/// A file last opened, changed and created `days` ago.
private func aged(_ home: URL, _ relative: String, days: Double, now: Date) throws {
    try write(home, relative)
    let url = home.appendingPathComponent(relative), date = now.addingTimeInterval(-days * 86_400)
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
}

@Test func onlyTranscriptsAndLogsOlderThan90DaysGoToTrashNeverSettingsCredentialsOrMemory() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    let offered = [
        ".claude/projects/-Users-me-app/1b2c.jsonl": "claude-code-transcripts",
        ".claude/projects/-Users-me-app/1b2c/subagents/agent-1.jsonl": "claude-code-transcripts",
        ".codex/sessions/2026/01/02/rollout-2026-01-02T10-00-00-abc.jsonl": "codex-transcripts",
        ".codex/archived_sessions/rollout-2025-12-01T10-00-00-def.jsonl": "codex-transcripts",
        ".codex/log/codex-tui.log": "codex-transcripts",
    ]
    for path in offered.keys { try aged(home, path, days: 120, now: now) }
    // Old, but settings, credentials, project memory and prompt history are never offered.
    for kept in [".claude/settings.json", ".claude/.credentials.json", ".claude/CLAUDE.md", ".claude/projects/-Users-me-app/memory/MEMORY.md",
                 ".claude/projects/-Users-me-app/memory/notes.jsonl", ".codex/config.toml", ".codex/auth.json", ".codex/history.jsonl", ".codex/AGENTS.md"] {
        try aged(home, kept, days: 400, now: now)
    }
    // Newer than 90 days: kept.
    try aged(home, ".claude/projects/-Users-me-app/recent.jsonl", days: 30, now: now)
    try aged(home, ".codex/sessions/2026/09/30/rollout-recent.jsonl", days: 30, now: now)
    let catalog = Catalog(rules: fixtureRules)
    #expect(found(catalog, home, now: now) == offered)
    for id in ["claude-code-transcripts", "codex-transcripts"] {
        let rule = try #require(catalog.rule(id))
        #expect(rule.action == .trash && rule.category == .logs && rule.regen == .log)
    }
}

// MARK: Agent workspaces

/// Runs git on a fixture repository only, with no user or system config.
@discardableResult
private func git(_ arguments: [String], in folder: URL) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-c", "user.name=Still Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"] + arguments
    process.currentDirectoryURL = folder
    process.environment = ["PATH": "/usr/bin:/bin", "HOME": folder.path, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                           "DEVELOPER_DIR": ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? ""].filter { !$0.value.isEmpty }
    process.standardOutput = pipe; process.standardError = pipe
    try process.run(); process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    if process.terminationStatus != 0 { Issue.record("git \(arguments.joined(separator: " ")) failed: \(output)") }
    return output
}
private func clone(_ origin: URL, to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
    try git(["clone", "-q", origin.path, folder.path], in: folder.deletingLastPathComponent())
}

@Test func agentWorkspacesAreGuidanceWithTheirSizeAndGitStatusNeverCandidates() throws {
    let home = try fixtureHome(), origin = try fixtureHome().appendingPathComponent("origin.git")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: origin.deletingLastPathComponent()) }
    // A shared origin with one pushed commit.
    try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
    try git(["init", "-q", "--bare"], in: origin)
    let seed = origin.deletingLastPathComponent().appendingPathComponent("seed")
    try clone(origin, to: seed)
    try write(seed, "README.md")
    try git(["add", "."], in: seed); try git(["commit", "-qm", "seed"], in: seed); try git(["push", "-q", "origin", "HEAD:main"], in: seed)

    // Clean and pushed.
    let pushed = home.appendingPathComponent(".codex/worktrees/a1b2/app")
    try clone(origin, to: pushed)
    // Uncommitted changes.
    let edited = home.appendingPathComponent(".codex/worktrees/c3d4/app")
    try clone(origin, to: edited)
    try write(edited, "README.md", bytes: 300)
    // A commit not pushed to its upstream.
    let ahead = home.appendingPathComponent("Library/Caches/Codex/checkouts/app")
    try clone(origin, to: ahead)
    try write(ahead, "new.swift"); try git(["add", "."], in: ahead); try git(["commit", "-qm", "local"], in: ahead)
    // No remote at all: not pushed anywhere.
    let local = home.appendingPathComponent("private/tmp/claude-\(getuid())/-Users-me-app/session/scratchpad/build")
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    try git(["init", "-q"], in: local)
    try write(local, "a.txt"); try git(["add", "."], in: local); try git(["commit", "-qm", "local"], in: local)
    // A detached worktree at a pushed commit: no upstream, but nothing unpushed.
    try git(["worktree", "add", "-q", "--detach", home.appendingPathComponent(".codex/worktrees/e5f6/app").path], in: pushed)
    let index = edited.appendingPathComponent(".git/index")
    let indexBefore = try Data(contentsOf: index), indexDate = try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date

    let catalog = Catalog(rules: fixtureRules)
    let finding = try #require(catalog.guidance(fixture: home).first { $0.ruleID == "agent-workspaces" })
    #expect(finding.workspaces == AgentWorkspaces(count: 5, uncommitted: 1, unpushed: 2, unchecked: 0))
    #expect(finding.workspaces?.summary == "5 workspaces · 1 has uncommitted changes · 2 have unpushed commits")
    guard case .estimate(.measured(let bytes)) = finding.size else { Issue.record("not measured: \(finding.size)"); return }
    #expect(bytes > 0)
    #expect(catalog.target(for: finding) == .folder(home.appendingPathComponent(".codex/worktrees")))
    // Read only: git refreshed nothing, and none of it is ever offered, even the clean ones.
    #expect(try Data(contentsOf: index) == indexBefore)
    #expect(try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date == indexDate)
    #expect(catalog.discover(fixture: home).isEmpty)
    #expect(catalog.rule("agent-workspaces")?.action == .guidance)
}

@Test func workspaceSummaryCountsOnlyWhatIsThere() {
    #expect(AgentWorkspaces(count: 1, uncommitted: 0, unpushed: 0, unchecked: 0).summary == "1 workspace · all committed and pushed")
    #expect(AgentWorkspaces(count: 3, uncommitted: 2, unpushed: 1, unchecked: 1).summary
            == "3 workspaces · 2 have uncommitted changes · 1 has unpushed commits · 1 couldn’t be checked")
    #expect(AgentWorkspaces(count: 2, uncommitted: 0, unpushed: 0, unchecked: 2).summary == "2 workspaces · 2 couldn’t be checked")
}

@Test func aWorkspaceWithNoCommitsYetHasOnlyUncommittedChanges() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let fresh = home.appendingPathComponent(".codex/worktrees/a1b2/app")
    try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
    try git(["init", "-q"], in: fresh)
    try write(fresh, "draft.swift")
    let finding = try #require(Catalog(rules: fixtureRules).guidance(fixture: home).first { $0.ruleID == "agent-workspaces" })
    #expect(finding.workspaces == AgentWorkspaces(count: 1, uncommitted: 1, unpushed: 0, unchecked: 0))
}

@Test func workspaceGitRunsWithEveryReadOnlyHardeningFlag() throws {
    let folder = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: folder) }
    // A stand-in git that logs each command line and its environment, and reports a clean, pushed checkout.
    let log = folder.appendingPathComponent("calls.log"), fake = folder.appendingPathComponent("git")
    try Data("""
    #!/bin/sh
    echo "$* | GIT_OPTIONAL_LOCKS=$GIT_OPTIONAL_LOCKS GIT_TERMINAL_PROMPT=$GIT_TERMINAL_PROMPT GIT_NO_LAZY_FETCH=$GIT_NO_LAZY_FETCH" >> '\(log.path)'
    case "$*" in *rev-list*) echo 0 ;; esac
    exit 0
    """.utf8).write(to: fake)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    let checkout = folder.appendingPathComponent("app")
    let result = try #require(WorkspaceGit.status(of: checkout, git: fake))
    #expect(result.uncommitted == false && result.unpushed == false)
    let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    #expect(calls.count == 2)
    for call in calls {
        #expect(call.hasPrefix("--no-optional-locks -c core.fsmonitor=false -c core.hooksPath=/dev/null -C \(checkout.path) "))
        #expect(call.hasSuffix("| GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_NO_LAZY_FETCH=1"))
    }
    // No submodule is entered (each would run git with its own config), untracked files still count, no rename detection.
    #expect(calls[0].contains(" status --porcelain --ignore-submodules=dirty --untracked-files=normal --no-renames |"))
}
