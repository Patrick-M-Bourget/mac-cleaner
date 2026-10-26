import Foundation

/// AI coding tools (#140). Cursor's and Windsurf's caches are VS Code-style (`AppDataCaches.vsCode`); Copilot keeps its
/// data in VS Code's folders, so it has no rule of its own. Here: old transcripts and logs of Claude Code and Codex.
public enum AITools {
    /// Transcripts and logs not opened, changed or added for this many days are offered, to Trash.
    public static let transcriptDays = UserFiles.unusedDays

    /// Claude Code keeps each session's transcript as `<session>.jsonl` (and its subagents' under `<session>/subagents`)
    /// in ~/.claude/projects/<project> (Claude Code docs, "Data usage" and the `cleanupPeriodDays` setting). Auto memory
    /// lives beside them in `<project>/memory`, so that name is protected; settings and credentials sit outside the location.
    static let claudeCodeTranscripts = CleanupRule(
        id: "claude-code-transcripts", category: .logs, title: "Old Claude Code transcripts",
        detail: "Conversations with Claude Code not opened in 90 days.",
        consequence: "Moved to Trash. Those sessions can no longer be resumed; settings, credentials and project memory are kept.",
        regen: .log, action: .trash, locations: [".claude/projects"], owner: nil, protectedNames: ["memory"],
        contents: ContentsMatch(extensions: ["jsonl"], unusedDays: transcriptDays))

    /// Codex (command line and desktop app share ~/.codex, its CODEX_HOME) writes each session as
    /// `sessions/YYYY/MM/DD/rollout-….jsonl`, moves archived ones to `archived_sessions`, and logs to `log/codex-tui.log`
    /// (Codex docs, "Config" and "Logging"). `config.toml`, `auth.json` and `history.jsonl` sit outside these locations.
    static let codexTranscripts = CleanupRule(
        id: "codex-transcripts", category: .logs, title: "Old Codex transcripts and logs",
        detail: "Codex sessions and logs not opened in 90 days.",
        consequence: "Moved to Trash. Those sessions can no longer be resumed; settings and sign-in are kept.",
        regen: .log, action: .trash, locations: [".codex/sessions", ".codex/archived_sessions", ".codex/log"], owner: nil,
        contents: ContentsMatch(extensions: ["jsonl", "log"], unusedDays: transcriptDays))

    /// Where agents keep workspaces of their own: the Codex app's worktrees in ~/.codex/worktrees (Codex docs, "Worktrees"),
    /// Codex's checkouts in ~/Library/Caches/Codex, and Claude Code's per-user scratch folder, `/private/tmp/claude-<uid>`,
    /// where it builds and keeps scratch checkouts. Guidance only: work there may exist nowhere else.
    static let agentWorkspaces = CleanupRule(
        id: "agent-workspaces", category: .managed, title: "AI agent workspaces",
        detail: "Checkouts and build scratch AI coding agents keep in their own folders. Review them before removing any; work there may not be pushed.",
        consequence: "Guidance only. Still shows the size and where they are, and never changes them.",
        regen: .userFile, action: .guidance,
        locations: [".codex/worktrees", "Library/Caches/Codex", "/private/tmp/claude-\(getuid())"], owner: nil,
        guidance: Guidance(sizing: .agentWorkspaces, place: .folder, placeName: "in Finder"))

    public static let rules: [CleanupRule] = [claudeCodeTranscripts, codexTranscripts, agentWorkspaces]
}
