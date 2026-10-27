import Foundation

/// The two selections a session keeps (#141): the Cleanup plan's chosen items, and Smart clean's. Neither ever changes
/// the other, and a finished run clears only the one it came from.
public struct CleanupSelections: Sendable, Equatable {
    /// Which selection a review or run came from.
    public enum Source: Sendable, Equatable {
        case plan, smartClean, applications
        /// The page that shows and cleans an item: leftovers of removed apps on Applications (Decision 51), the rest in the plan.
        public static func page(of candidate: Candidate) -> Source { page(ofID: candidate.id) }
        /// The same from a chosen id alone, which starts with its rule's ID, so it holds after a run, when nothing is found yet.
        static func page(ofID id: String) -> Source {
            RemovedAppLeftovers.ruleIDs.contains(String(id.prefix { $0 != "|" })) ? .applications : .plan
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

    /// Clears one page's choices: the plan's or the Applications page's, which share one set, or Smart clean's unticks.
    /// The other pages' are kept (#270), told apart by each chosen id's rule, so nothing needs to be found.
    public mutating func clear(_ page: Source) {
        switch page {
        case .plan, .applications: plan = plan.filter { Source.page(ofID: $0) != page }
        case .smartClean: smartCleanUnticked = []
        }
    }

    /// A run finished: its own selection starts over (Smart clean with everything ticked again); the others are kept.
    public mutating func finishRun(from source: Source) { clear(source) }
}
