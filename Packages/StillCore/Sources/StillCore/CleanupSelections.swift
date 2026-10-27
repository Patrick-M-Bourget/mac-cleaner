import Foundation

/// The two selections a session keeps (#141): the Cleanup plan's chosen items, and Smart clean's. Neither ever changes
/// the other, and a finished run clears only the one it came from.
public struct CleanupSelections: Sendable, Equatable {
    /// Which selection a review or run came from.
    public enum Source: Sendable, Equatable { case plan, smartClean }

    /// The Cleanup plan's chosen candidate ids. Nothing is preselected (Decision 28).
    public var plan: Set<String> = []
    /// Recommended items unticked on Smart clean; every other recommended item is ticked.
    public private(set) var smartCleanUnticked: Set<String> = []

    public init() {}

    public func isInSmartClean(_ candidate: Candidate) -> Bool { !smartCleanUnticked.contains(candidate.id) }

    public mutating func setSmartClean(_ items: [Candidate], included: Bool) {
        let ids = items.map(\.id)
        if included { smartCleanUnticked.subtract(ids) } else { smartCleanUnticked.formUnion(ids) }
    }

    /// What Smart clean's Clean up takes: the recommended plan with `check` run now (`RecommendedPlan`), minus what was unticked.
    public func smartClean(catalog: Catalog, found: [Candidate], check: (Candidate) -> CheckRefusal?) -> [Candidate] {
        RecommendedPlan(catalog: catalog, candidates: found, check: check).candidates.filter(isInSmartClean)
    }

    /// A run finished: its own selection starts over (Smart clean with everything ticked again); the other is kept.
    public mutating func finishRun(from source: Source) {
        switch source {
        case .plan: plan = []
        case .smartClean: smartCleanUnticked = []
        }
    }
}
