import Foundation

/// What a plan category's checkbox shows and does (#240). Items chosen one by one (possibly related leftovers, #173) are never
/// chosen with it, but they show on it and it clears them. A category of only such items opens its list, where each is chosen.
public struct CategorySelection: Sendable {
    public enum Toggle: Sendable, Equatable {
        case choose(Set<String>)
        case clear(Set<String>)
        /// Nothing may be chosen together and nothing is chosen: the items are listed to choose one by one.
        case showItems
    }
    public let state: CategorySelectionState
    public let toggle: Toggle

    /// `candidates` are the items the category's `rules` found; `selected` the chosen item IDs.
    public init(rules: [CleanupRule], candidates: [Candidate], selected: Set<String>) {
        let oneByOne = Set(rules.filter(\.selectedOneByOne).map(\.id))
        // A held item (#374) is ticked on its own too, never with its category.
        let all = Set(candidates.map(\.id)), together = Set(candidates.filter { !oneByOne.contains($0.ruleID) && $0.hold == nil }.map(\.id))
        let chosen = all.intersection(selected)
        let full = together.isEmpty ? all : together
        state = chosen.isEmpty ? .unchecked : full.isSubset(of: selected) ? .checked : .mixed
        toggle = !together.isSubset(of: selected) ? .choose(together) : !chosen.isEmpty ? .clear(all) : .showItems
    }
}
