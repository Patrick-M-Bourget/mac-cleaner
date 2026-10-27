import Foundation

/// The two selections a session keeps (#141): the Cleanup plan's chosen items, and Smart clean's. Neither ever changes
/// the other, and a finished run clears only the one it came from.
public struct CleanupSelections: Sendable, Equatable {
    /// Which selection a review or run came from.
    public enum Source: Sendable, Equatable {
        case plan, smartClean, applications
        /// The page that shows and cleans an item: leftovers of removed apps on Applications (Decision 51), the rest in the plan.
        public static func page(of candidate: Candidate) -> Source {
            RemovedAppLeftovers.ruleIDs.contains(candidate.ruleID) ? .applications : .plan
        }
    }

    /// The chosen candidate ids of the Cleanup plan and the Applications page; each page shows and reviews only its own
    /// (`chosen(on:from:)`). Nothing is preselected (Decision 28).
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

    /// The chosen items among `found` that `page` shows (the plan or Applications).
    public func chosen(on page: Source, from found: [Candidate]) -> [Candidate] {
        found.filter { plan.contains($0.id) && Source.page(of: $0) == page }
    }

    /// A run finished: its own selection starts over (Smart clean with everything ticked again); the others are kept.
    /// `found` tells the plan's items from the Applications page's, which share one set.
    public mutating func finishRun(from source: Source, found: [Candidate] = []) {
        let applications = Set(found.filter { Source.page(of: $0) == .applications }.map(\.id))
        switch source {
        case .plan: plan.formIntersection(applications)
        case .applications: plan.subtract(applications)
        case .smartClean: smartCleanUnticked = []
        }
    }
}
