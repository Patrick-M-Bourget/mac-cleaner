import Foundation

/// Reads agent workspaces' git status through `BoundedTool`, with read-only commands only.
enum WorkspaceGit {
    /// Git itself, never `/usr/bin/git`: on a Mac without developer tools that stub offers to install them.
    static let executables = ["/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
                              "/opt/homebrew/bin/git", "/usr/local/bin/git"]
    static func installed() -> URL? {
        executables.lazy.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    /// Levels searched for checkouts inside a location (a Claude Code scratchpad sits a few levels down).
    static let depth = 6
    /// At most this many checkouts per scan.
    static let limit = 200
    static let timeout: TimeInterval = 5
    /// No prompts, no index refresh or other optional lock, and no fetching of objects a partial clone lacks (#147).
    static let environment = BoundedTool.defaultEnvironment.merging(["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_LAZY_FETCH": "1"]) { $1 }
    /// Before every command (#147): no optional locks, and none of the repository's commands that can be turned off:
    /// no fsmonitor hook, and no hooks at all.
    static func baseArguments(_ checkout: URL) -> [String] {
        ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", checkout.path]
    }
    /// Submodules are never entered (git would run in each with its config): only a submodule moved to another commit
    /// counts, not changes inside it. Untracked files count as uncommitted work. No rename detection.
    static let statusArguments = ["status", "--porcelain", "--ignore-submodules=dirty", "--untracked-files=normal", "--no-renames"]

    /// The checkouts in `roots`: each folder holding a `.git` entry (a working tree or a linked worktree), never looked inside.
    static func checkouts(in roots: [URL]) -> [URL] {
        var found: [URL] = []
        for root in roots where found.count < limit {
            FileTree.walk(root) { entry in
                guard Int32(entry.pointee.fts_info) == FTS_D else { return .continue }
                let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                if GitCheckout.isRoot(url) { found.append(url); return found.count < limit ? .skip : .stop }
                return entry.pointee.fts_level < depth ? .continue : .skip
            }
        }
        return found
    }

    /// Whether the checkout has uncommitted changes and unpushed commits; nil when git can't tell in time.
    static func status(of checkout: URL, git: URL) -> (uncommitted: Bool, unpushed: Bool)? {
        let base = baseArguments(checkout)
        guard let changes = try? BoundedTool.capture(executable: git, arguments: base + statusArguments, timeout: timeout, outputLimit: 1_024,
                                                     environment: environment), changes.status == 0 else { return nil }
        func count(_ arguments: [String]) -> Int? {
            (try? BoundedTool.run(executable: git, arguments: base + arguments, timeout: timeout, environment: environment))
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        // Without an upstream, commits that are on no remote at all are not pushed anywhere. With no commit yet, none are.
        func unborn() -> Bool {
            (try? BoundedTool.capture(executable: git, arguments: base + ["rev-parse", "--verify", "-q", "HEAD"], timeout: timeout,
                                      environment: environment)).map { $0.status != 0 } ?? false
        }
        guard let ahead = count(["rev-list", "--count", "@{u}..HEAD"]) ?? count(["rev-list", "--count", "HEAD", "--not", "--remotes"])
                ?? (unborn() ? 0 : nil) else { return nil }
        return (!changes.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ahead > 0)
    }

    /// The workspaces in `roots`; nil when there are none.
    static func workspaces(in roots: [URL], git: URL? = installed()) -> AgentWorkspaces? {
        let checkouts = checkouts(in: roots)
        guard !checkouts.isEmpty else { return nil }
        let statuses = checkouts.map { checkout in git.flatMap { status(of: checkout, git: $0) } }
        return AgentWorkspaces(count: checkouts.count, uncommitted: statuses.filter { $0?.uncommitted == true }.count,
                               unpushed: statuses.filter { $0?.unpushed == true }.count, unchecked: statuses.filter { $0 == nil }.count)
    }
}
