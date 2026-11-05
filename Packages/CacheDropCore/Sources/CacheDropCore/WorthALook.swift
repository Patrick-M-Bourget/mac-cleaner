import Foundation

/// Smart clean's **Worth a look** (#780, Decision 178): suggestions under its ticked categories that are never ticked for
/// you, since pre-ticks only lose no data and an app's settings are data. Its first member is Files from deleted apps, the
/// row Applications draws, its tick shared with Applications (one selection, Decision 67); possibly related items are still
/// ticked one by one (Decision 49). What's in it counts in Smart clean's Free up X and Clean up only once ticked.
public enum WorthALook {
    public static let title = "Worth a look"
    /// The categories it suggests, in order.
    static let categories: [CatalogCategory] = [.leftovers]
    /// The rules whose items it holds: told apart by rule ID, so a choice reads the same with no catalog at hand.
    static let ruleIDs: Set<String> = Set(RemovedAppLeftovers.rules.map(\.id))

    /// Whether Smart clean suggests `candidate` here.
    public static func offers(_ candidate: Candidate) -> Bool { offers(id: candidate.id) }
    /// The same from a candidate id, which starts with its rule's ID.
    static func offers(id: String) -> Bool { ruleIDs.contains(String(id.prefix { $0 != "|" })) }

    /// Its rows, each a category that found something; none means no group and no header.
    public static func rows(in overview: CatalogOverview) -> [CatalogOverview.Row] {
        categories.compactMap { category in overview.rows.first { $0.category == category && $0.itemCount > 0 } }
    }
}
