import Foundation

/// One guidance category found on this Mac. It is never a candidate and never in a plan.
public struct GuidanceFinding: Sendable, Identifiable, Equatable {
    public var id: String { ruleID }
    public let ruleID: String
    public let size: GuidanceSize
    /// The first existing location, which a `.folder` place opens.
    public let folder: URL?
}
