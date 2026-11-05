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

    /// Found X so far, and Found X you can clean: Overview's recommended figure, what the scan found that releases space.
    public static func found(_ overview: CatalogOverview?) -> Int64 { max(0, overview?.recommended.sortBytes ?? 0) }

    /// What Ready shows: the total and the three largest categories. Nil when nothing can be cleaned (Nothing to clean up).
    public struct Ready {
        public let found: Int64
        public let top: [CatalogOverview.Row]
    }
    public static func ready(_ overview: CatalogOverview?) -> Ready? {
        guard let overview, found(overview) > 0 else { return nil }
        return Ready(found: found(overview), top: Array(overview.visibleRows.filter { !$0.isEmpty }.prefix(3)))
    }
}
