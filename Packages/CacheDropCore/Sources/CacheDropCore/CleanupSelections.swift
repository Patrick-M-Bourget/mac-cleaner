import Foundation

/// The one selection a session keeps (#349, superseding #141 and Decision 28): the items ticked on Smart clean, the Cleanup
/// plan and the Applications page, in one set. Each page shows its own part of it, so a tick or untick on one page shows on
/// every page that lists the item. Recommended items (`RecommendedPlan`) start ticked and the rest unticked; an untick
/// survives rescans, and a newly found recommended item arrives ticked.
public struct CleanupSelections: Sendable, Equatable {
    /// Which page a review or run came from.
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

    /// The ticked candidate ids of every page, in one set; the plan and Applications each show and review only their own,
    /// told apart by each id's rule (`chosen(on:from:)`), and Smart clean its recommended ones (`smartClean`).
    public private(set) var ticked: Set<String> = []
    /// Ids the user unticked: a scan never ticks them again, even when recommended.
    private var unticked: Set<String> = []

    /// Each page's revision moves on only when that page's choices really change (#307, #333), so its open review sheet
    /// knows they did, and a scan that keeps them, or changes only another page's, never closes it.
    public func revision(of page: Source) -> UInt64 { revisions[page] ?? 0 }
    private var revisions: [Source: UInt64] = [:]
    /// The choices each page's revision was last moved for: its ticked items among those found, or Smart clean's items.
    private var revisedFor: [Source: Set<String>] = [:]

    public init() {}

    public func isTicked(_ candidate: Candidate) -> Bool { ticked.contains(candidate.id) }

    /// Ticks or unticks items on whichever page the user is on; every page that lists them shows the change.
    public mutating func set<IDs: Sequence<String>>(_ ids: IDs, ticked tick: Bool) {
        let ids = Set(ids)
        if tick { ticked.formUnion(ids); unticked.subtract(ids) } else { ticked.subtract(ids); unticked.formUnion(ids) }
    }
    public mutating func set(_ candidates: [Candidate], ticked tick: Bool) { set(candidates.map(\.id), ticked: tick) }

    /// Notes the pages' choices after an edit, a run or a scan: ticks the `recommended` items found that the user never
    /// unticked, then moves each page's revision only when its own choices differ from the ones it last moved for.
    public mutating func noteChoices(among found: [Candidate], recommended: [Candidate]) {
        ticked.formUnion(Set(recommended.map(\.id)).subtracting(unticked))
        let ids = ticked.intersection(found.map(\.id))
        for page in Source.allCases {
            let now = page == .smartClean ? Set(recommended.map(\.id)).intersection(ticked) : ids.filter { Source.page(ofID: $0) == page }
            guard now != revisedFor[page, default: []] else { continue }
            revisedFor[page] = now; revisions[page, default: 0] &+= 1
        }
    }

    /// A scan ended: drops the ticked items no longer among `found`, ticks the newly recommended ones and notes the
    /// choices. Returns whether any ticked item was dropped.
    @discardableResult public mutating func keepOnly(_ found: [Candidate], recommended: [Candidate]) -> Bool {
        let ids = Set(found.map(\.id))
        let dropped = !ticked.isSubset(of: ids)
        if dropped { ticked.formIntersection(ids) }
        noteChoices(among: found, recommended: recommended)
        return dropped
    }

    /// What every review would do changed without any choice changing (the dry run was turned on or off, or a run
    /// finished): moves all three pages' revisions anyway.
    public mutating func revise() { for page in Source.allCases { revisions[page, default: 0] &+= 1 } }

    /// What Smart clean's Clean up takes: the ticked items of the recommended plan with `check` run now (`RecommendedPlan`).
    /// An item the page `listed` that `check` now refuses stays in, so the review says it will be skipped and why (#310);
    /// the run's own check refuses it again.
    public func smartClean(catalog: Catalog, found: [Candidate], listed: [Candidate] = [], check: (Candidate) -> CheckRefusal?) -> [Candidate] {
        let shown = Set(listed.map(\.id))
        let passing = Set(RecommendedPlan(catalog: catalog, candidates: found, check: check).candidates.map(\.id))
        let refused = Set(RecommendedPlan(catalog: catalog, candidates: found.filter { shown.contains($0.id) }) { _ in nil }.candidates.map(\.id)).subtracting(passing)
        return found.filter { (passing.contains($0.id) || refused.contains($0.id)) && isTicked($0) }
    }

    /// The ticked items among `found` that `page` shows (the plan or Applications).
    public func chosen(on page: Source, from found: [Candidate]) -> [Candidate] {
        found.filter { ticked.contains($0.id) && Source.page(of: $0) == page }
    }

    /// Whether the ticks among `items` differ from the recommended default, ticked exactly when `recommended`: on Overview,
    /// a category's "Selected"; over everything found, what quitting would lose (#270).
    public func differsFromRecommended(_ items: [Candidate], recommended: [Candidate]) -> Bool {
        let ids = Set(items.map(\.id))
        return ticked.intersection(ids) != Set(recommended.map(\.id)).intersection(ids)
    }

    /// Starts one page over at the recommended default: its ticks and unticks go (the next `noteChoices` ticks its
    /// recommended items again), and the other pages' are kept (#270), told apart by each id's rule, so nothing needs to be found.
    public mutating func clear(_ page: Source) {
        ticked = ticked.filter { Source.page(ofID: $0) != page }
        unticked = unticked.filter { Source.page(ofID: $0) != page }
    }

    /// A run finished: the items it took leave every page, ticked or unticked; any it skipped that are still recommended
    /// arrive ticked again at the next scan. Everything else is kept, whichever page the run came from.
    public mutating func finishRun(_ ran: [Candidate]) {
        let ids = Set(ran.map(\.id))
        ticked.subtract(ids); unticked.subtract(ids)
    }
}
