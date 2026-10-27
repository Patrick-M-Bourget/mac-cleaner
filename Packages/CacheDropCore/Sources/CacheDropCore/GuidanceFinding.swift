import Foundation

/// One guidance category found on this Mac. It is never a candidate and never in a plan.
public struct GuidanceFinding: Sendable, Identifiable, Equatable {
    public var id: String { ruleID }
    public let ruleID: String
    public let size: GuidanceSize
    /// The first existing location, which a `.folder` place opens.
    public let folder: URL?
    /// Agent workspaces' git status (#140); nil for every other rule.
    public var workspaces: AgentWorkspaces? = nil
    /// The audio plug-ins by product (#174); nil for every other rule.
    public var plugIns: PlugInInventory? = nil
    /// The library packages found (#180, #178); nil for every other rule.
    public var libraries: [FoundLibrary]? = nil
    /// Volumes the library search abandoned because a read didn't return in time (#244); empty for every other rule.
    public var notSearched: [String] = []
    /// The libraries' summary line, naming any volume not searched.
    public var librariesSummary: String? { libraries.map { FoundLibrary.summary($0, notSearched: notSearched) } }
}
