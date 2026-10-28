import Foundation

/// Smart clean's one consequence line per category (#319): what happens to what is ticked in it, from what its rules do.
/// The review sheet still explains each consequence in full, grouped by consequence (Decision 25).
public enum SmartCleanConsequence {
    public static let trash = "Goes to the Trash; Put back works"

    /// The line for `category`, whose ticked items `rules` found.
    public static func line(for category: CatalogCategory, rules: [CleanupRule]) -> String {
        let actions = Set(rules.map(\.action))
        if actions == [.trash] { return trash }
        var line = comesBack(category)
        if actions.contains(.tool) { line += "; some tools clean their own" }
        if actions.contains(.trash) { line += "; some goes to the Trash" }
        return line
    }

    /// How a category's deleted data comes back.
    static func comesBack(_ category: CatalogCategory) -> String {
        switch category {
        case .developer: "Comes back on its own when your tools and Xcode need it"
        case .browser: "Comes back on its own as you browse"
        case .updaters: "Comes back on its own when apps check for updates"
        case .logs: "Apps write new logs as they run"
        default: "Comes back on its own when apps need it"
        }
    }
}
