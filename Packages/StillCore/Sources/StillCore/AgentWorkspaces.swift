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
