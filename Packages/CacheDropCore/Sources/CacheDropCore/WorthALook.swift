import Foundation

/// Smart clean's **Worth a look** (#780, Decision 178): the files from deleted apps `RecommendedPlan` doesn't take (possibly
/// related ones, or any tie it doesn't recommend), listed unticked under Smart clean's ticked categories. The ones it takes
/// stay ticked in Files from deleted apps' own row, so nothing is shown twice. Ticks are shared with Applications (one
/// selection, Decision 67); possibly related items are ticked one by one (Decision 49). What's in it counts in Smart clean's
/// Free up X and Clean up only once ticked.
public enum WorthALook {
    public static let title = "Worth a look"
    /// The rules whose items it may hold: told apart by rule ID, so a choice reads the same with no catalog at hand.
    static let ruleIDs: Set<String> = Set(RemovedAppLeftovers.rules.map(\.id))

    /// The items among `found` it holds: files from deleted apps the recommended `plan` neither takes nor holds.
    public static func candidates(in found: [Candidate], plan: RecommendedPlan) -> [Candidate] {
        let planned = Set((plan.candidates + plan.held).map(\.id))
        return found.filter { offers(id: $0.id, notIn: planned) }
    }
    /// The same rule from ids alone: a file from a deleted app that isn't among the plan's `planned` ids.
    static func offers(id: String, notIn planned: Set<String>) -> Bool {
        !planned.contains(id) && ruleIDs.contains(String(id.prefix { $0 != "|" }))
    }

    /// Its rows, one per category its `candidates` fill; none means no group and no header.
    public static func rows(_ candidates: [Candidate], catalog: Catalog) -> [CatalogOverview.Row] {
        CatalogOverview(catalog: catalog, candidates: candidates).rows.filter { $0.itemCount > 0 }
    }
}
