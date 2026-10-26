import Foundation

/// Git checkouts AI coding agents keep in their own folders (#140): how many, and how many hold work that exists
/// nowhere else. Always guidance only; Still never offers them, even clean ones.
public struct AgentWorkspaces: Sendable, Equatable {
    public let count: Int
    /// Workspaces with changes not committed.
    public let uncommitted: Int
    /// Workspaces with commits not on any remote: ahead of their upstream, or not pushed anywhere.
    public let unpushed: Int
    /// Workspaces git couldn't report on in time.
    public let unchecked: Int
    public init(count: Int, uncommitted: Int, unpushed: Int, unchecked: Int) {
        self.count = count; self.uncommitted = uncommitted; self.unpushed = unpushed; self.unchecked = unchecked
    }

    /// "4 workspaces · 1 has uncommitted changes · 2 have unpushed commits". Counts of 0 are left out.
    public var summary: String {
        func phrase(_ n: Int, _ one: String, _ many: String) -> String? { n == 0 ? nil : "\(n) " + (n == 1 ? one : many) }
        var parts = [count == 1 ? "1 workspace" : "\(count) workspaces"]
        parts += [phrase(uncommitted, "has uncommitted changes", "have uncommitted changes"),
                  phrase(unpushed, "has unpushed commits", "have unpushed commits"),
                  phrase(unchecked, "couldn’t be checked", "couldn’t be checked")].compactMap { $0 }
        if parts.count == 1 { parts.append("all committed and pushed") }
        return parts.joined(separator: " · ")
    }
}

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
    /// No prompts, and no index refresh or other optional lock: git only reads.
    static let environment = BoundedTool.defaultEnvironment.merging(["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"]) { $1 }

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
        let base = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", checkout.path]
        guard let changes = try? BoundedTool.capture(executable: git, arguments: base + ["status", "--porcelain"], timeout: timeout, outputLimit: 1_024,
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
