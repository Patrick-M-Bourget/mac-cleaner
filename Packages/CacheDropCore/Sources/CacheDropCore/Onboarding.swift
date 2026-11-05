import Foundation

/// Onboarding's first scan (#783, #784; Decision 174): the categories its badges show, which have finished, what was found so
/// far, and what Ready shows.
public enum Onboarding {
    /// The categories Welcome shows as badges, in two rows of five.
    public static let categories: [CatalogCategory] = [.developer, .browser, .system, .downloads, .audio,
                                                       .photoVideo, .models, .updaters, .logs, .leftovers]

    /// The badges lit while the catalog scan runs. Discovery reads rules in catalog order, so a category has finished once
    /// the last of its rules has (`lastFinishedRuleID`); one with no rule discovery reads lights when discovery ends. Files
    /// from deleted apps are read after discovery, so they light last.
    public static func finished(in catalog: Catalog, phase: CatalogScanPhase, lastFinishedRuleID: String?) -> Set<CatalogCategory> {
        switch phase {
        case .starting: return []
        case .removedAppLeftovers: return Set(categories).subtracting([.leftovers])
        case .appsAndPlugIns, .openApps, .storageTrends, .appManagedStorage: return Set(categories)
        case .location:
            guard let lastFinishedRuleID, let done = catalog.rules.firstIndex(where: { $0.id == lastFinishedRuleID }) else { return [] }
            return Set(categories.filter { category in
                guard category != .leftovers else { return false }
                let last = catalog.rules.lastIndex { $0.category == category && $0.action != .guidance }
                return last.map { $0 <= done } ?? false
            })
        }
    }

    /// Found X so far: Overview's recommended figure for the locations read so far, what they found that releases space.
    public static func found(_ overview: CatalogOverview?) -> Int64 { max(0, overview?.recommended.sortBytes ?? 0) }

    /// What Ready shows: the figure and the three largest categories of what it counts.
    public struct Ready {
        public let found: Int64
        public let top: [CatalogOverview.Row]
    }
    /// Ready follows Smart clean (`smartClean`, its ticked items): Found X you can clean is its Free up figure, what those items
    /// release, or, when none releases space, what they move to the Trash (as Results reports such a run, Decision 132).
    /// Nil, Nothing to clean up, only when Smart clean has nothing to clean.
    public static func ready(smartClean: [Candidate], catalog: Catalog) -> Ready? {
        guard !smartClean.isEmpty else { return nil }
        let releasing = smartClean.filter(\.releasesSpace)
        let counted = releasing.isEmpty ? smartClean : releasing
        let overview = CatalogOverview(catalog: catalog, candidates: counted)
        return Ready(found: max(0, SizeEstimate(sum: counted.map(SizeEstimate.init)).sortBytes),
                     top: Array(overview.visibleRows.filter { !$0.isEmpty }.prefix(3)))
    }
}
