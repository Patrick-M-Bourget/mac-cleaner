import Foundation
import Testing
@testable import StillCore

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
