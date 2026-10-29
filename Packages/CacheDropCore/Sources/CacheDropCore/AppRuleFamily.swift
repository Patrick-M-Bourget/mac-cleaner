import Foundation

/// The rules tied to one app or plug-in product (#289): a removed app's leftovers, an app's uninstall and a plug-in product's.
/// Their items are chosen on the Applications page (Decision 51) and wait for that app to close; the checks ask the rule's
/// family, never its ID.
public enum AppRuleFamily: Sendable, Hashable {
    case removedAppLeftovers, appUninstall, plugInUninstall

    /// Every family's rules, in the catalog's order.
    public static let rules: [CleanupRule] = RemovedAppLeftovers.rules + uninstallRules
    /// The rules an app's or a plug-in product's items are uninstalled by (#176, #177).
    public static let uninstallRules: [CleanupRule] = AppUninstall.rules + PlugInUninstall.rules
    /// The family of the rule with this ID, for an id alone (a chosen id after a run, a History record); nil for any other rule.
    public static func of(ruleID: String) -> AppRuleFamily? { rules.first { $0.id == ruleID }?.family }
    /// The rules whose item is the app or plug-in product itself, which History names (#177, #176).
    static let namingRuleIDs: Set<String> = [AppUninstall.appRule.id, PlugInUninstall.formatsRule.id]

    /// Whether its items are an installed app's or plug-in product's, uninstalled with it.
    public var isUninstall: Bool { self != .removedAppLeftovers }
    /// Who must be closed before an item is acted on: every app of a removed app's maker (#173), or the app or product being
    /// uninstalled (#177, Decision 29); nil when the item lost its tie, which refuses.
    func owner(of candidate: Candidate) -> RuleOwner? {
        isUninstall ? candidate.uninstall?.owner : candidate.leftover?.owner
    }
}

extension CleanupRule {
    /// Its items are ticked one by one, never with their category, rule or app (#173: possibly related leftovers; #176: a
    /// plug-in product's shared items): an app family's item-by-item rule.
    public var selectedOneByOne: Bool { family != nil && itemByItem }

    /// What clicking one of its item rows does (#356).
    public enum ItemRowClick: Sendable, Equatable {
        /// Ticks or unticks the item; Reveal in Finder is a secondary action beside it.
        case tick
        /// Shows the item in Finder; its checkbox ticks it.
        case reveal
    }
    /// An item ticked one by one is chosen in the app, so clicking its row ticks it (#356); every other item's row is a Finder link.
    public var itemRowClick: ItemRowClick { selectedOneByOne ? .tick : .reveal }
    /// Whether clicking the rule's own row shows all its items in Finder. Never for items ticked one by one (#356): each is
    /// chosen and revealed on its own, and the rule's row only shows what is ticked (Decision 49).
    public var ruleRowReveals: Bool { !selectedOneByOne }
}
