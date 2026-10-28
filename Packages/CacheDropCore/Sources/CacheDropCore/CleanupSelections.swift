import Foundation

/// The selections a session keeps (#141): the items ticked on the Cleanup plan and the Applications page, and Smart
/// clean's. Neither ever changes the other, and a finished run clears only the page it came from.
public struct CleanupSelections: Sendable, Equatable {
    /// Which selection a review or run came from.
    public enum Source: Sendable, Equatable, CaseIterable {
        case plan, smartClean, applications
        /// The page that shows and cleans an item: leftovers of removed apps on Applications (Decision 51), the rest in the plan.
        public static func page(of candidate: Candidate) -> Source { page(ofID: candidate.id) }
        /// The same from a chosen id alone, which starts with its rule's ID, so it holds after a run, when nothing is found yet.
        static func page(ofID id: String) -> Source { page(ofRule: String(id.prefix { $0 != "|" })) }
        /// The page that shows a category row: the one its rules are on.
        public static func page(of row: CatalogOverview.Row) -> Source { row.rules.first.map { page(ofRule: $0.id) } ?? .plan }
        private static func page(ofRule ruleID: String) -> Source { AppRuleFamily.of(ruleID: ruleID) == nil ? .plan : .applications }
    }

    /// The ticked candidate ids of both the Cleanup plan and the Applications page, in one set; each page shows and reviews
    /// only its own, told apart by each id's rule (`chosen(on:from:)`). Nothing is preselected (Decision 28).
    public var ticked: Set<String> = []
    /// Recommended items unticked on Smart clean; every other recommended item is ticked.
    public private(set) var smartCleanUnticked: Set<String> = []

    /// Each page's revision moves on only when that page's choices really change (#307, #333), so its open review sheet
    /// knows they did, and a scan that keeps them, or changes only another page's, never closes it.
    public func revision(of page: Source) -> UInt64 { revisions[page] ?? 0 }
    private var revisions: [Source: UInt64] = [:]
    /// The choices each page's revision was last moved for: its ticked items among those found, or Smart clean's items.
    private var revisedFor: [Source: Set<String>] = [:]

    public init() {}

    /// Notes the pages' choices after an edit, a run or a scan: the ticked items among `found`, and `smartClean`, the items
    /// Smart clean would take. Each page's revision moves only when its own differ from the ones it last moved for.
    public mutating func noteChoices(among found: [Candidate], smartClean: [Candidate]) {
        let ids = ticked.intersection(found.map(\.id))
        for page in Source.allCases {
            let now = page == .smartClean ? Set(smartClean.map(\.id)) : ids.filter { Source.page(ofID: $0) == page }
            guard now != revisedFor[page, default: []] else { continue }
            revisedFor[page] = now; revisions[page, default: 0] &+= 1
        }
    }

    /// A scan ended: drops the chosen items no longer among `found` and notes the choices left. Returns whether any were dropped.
    @discardableResult public mutating func keepOnly(_ found: [Candidate], smartClean: [Candidate]) -> Bool {
        let ids = Set(found.map(\.id))
        let dropped = !ticked.isSubset(of: ids)
        if dropped { ticked.formIntersection(ids) }
        noteChoices(among: found, smartClean: smartClean)
        return dropped
    }

    /// What every review would do changed without any choice changing (the dry run was turned on or off, or a run
    /// finished): moves all three pages' revisions anyway.
    public mutating func revise() { for page in Source.allCases { revisions[page, default: 0] &+= 1 } }

    public func isInSmartClean(_ candidate: Candidate) -> Bool { !smartCleanUnticked.contains(candidate.id) }

    public mutating func setSmartClean(_ items: [Candidate], included: Bool) {
        let ids = items.map(\.id)
        if included { smartCleanUnticked.subtract(ids) } else { smartCleanUnticked.formUnion(ids) }
    }

    /// What Smart clean's Clean up takes: the recommended plan with `check` run now (`RecommendedPlan`), minus what was unticked.
    /// An item the page `listed` that `check` now refuses stays in, so the review says it will be skipped and why (#310);
    /// the run's own check refuses it again.
    public func smartClean(catalog: Catalog, found: [Candidate], listed: [Candidate] = [], check: (Candidate) -> CheckRefusal?) -> [Candidate] {
        let shown = Set(listed.map(\.id))
        let passing = Set(RecommendedPlan(catalog: catalog, candidates: found, check: check).candidates.map(\.id))
        let refused = Set(RecommendedPlan(catalog: catalog, candidates: found.filter { shown.contains($0.id) }) { _ in nil }.candidates.map(\.id)).subtracting(passing)
        return found.filter { (passing.contains($0.id) || refused.contains($0.id)) && isInSmartClean($0) }
    }

    /// The chosen items among `found` that `page` shows (the plan or Applications).
    public func chosen(on page: Source, from found: [Candidate]) -> [Candidate] {
        found.filter { ticked.contains($0.id) && Source.page(of: $0) == page }
    }

    /// Whether either page has chosen items among `found`: what quitting would lose (#270).
    public func hasChoices(among found: [Candidate]) -> Bool { found.contains { ticked.contains($0.id) } }

    /// Clears one page's choices: the plan's or the Applications page's, which share one set, or Smart clean's unticks.
    /// The other pages' are kept (#270), told apart by each chosen id's rule, so nothing needs to be found.
    public mutating func clear(_ page: Source) {
        switch page {
        case .plan, .applications: ticked = ticked.filter { Source.page(ofID: $0) != page }
        case .smartClean: smartCleanUnticked = []
        }
    }

    /// A run finished: its own selection starts over (Smart clean with everything ticked again); the others are kept.
    public mutating func finishRun(from source: Source) { clear(source) }
}
