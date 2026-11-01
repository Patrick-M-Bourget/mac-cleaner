import Foundation

/// The review's groups: one per consequence, each with one line per catalog category, in catalog order.
public struct ReviewGroup: Sendable, Identifiable {
    public struct Line: Sendable, Identifiable {
        public var id: String { category.rawValue }
        public let category: CatalogCategory
        /// The category's rules with chosen items in this group, in catalog order.
        public let rules: [CleanupRule]
        public let candidates: [Candidate]
        /// What will be cleaned: skipped items are counted on their skipped line instead (#560, Decision 125).
        public let estimate: SizeEstimate
        /// Every item will be skipped, so the line shows no size: its skipped size is on the holder's line (Decision 125).
        public let cleansNothing: Bool
        /// Part of it is copies that share disk blocks, so less may come back (SPEC section 6).
        public var isUpperBound: Bool { rules.contains(where: \.estimateIsUpperBound) }
        public func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    }
    public var id: Int { consequence.rawValue }
    public let consequence: ConsequenceGroup
    public let lines: [Line]
    public var candidates: [Candidate] { lines.flatMap(\.candidates) }
    /// Every item in the group will be skipped, so its header shows no size either.
    public var cleansNothing: Bool { lines.allSatisfy(\.cleansNothing) }

    /// `skipped`: the ids of items the review says will be skipped, left out of each line's size but not its files.
    public static func groups(catalog: Catalog, candidates: [Candidate], skipped: Set<String> = []) -> [ReviewGroup] {
        let found = catalog.rules.filter { rule in candidates.contains { $0.ruleID == rule.id } }
        return ConsequenceGroup.allCases.compactMap { group in
            let rules = found.filter { ConsequenceGroup($0.action) == group }
            var order: [CatalogCategory] = []
            for rule in rules where !order.contains(rule.category) { order.append(rule.category) }
            let lines = order.map { category in
                let inLine = rules.filter { $0.category == category }, ids = Set(inLine.map(\.id))
                let chosen = candidates.filter { ids.contains($0.ruleID) }
                let cleaned = chosen.filter { !skipped.contains($0.id) }
                return Line(category: category, rules: inLine, candidates: chosen, estimate: SizeEstimate(sum: cleaned.map(SizeEstimate.init)),
                            cleansNothing: cleaned.isEmpty)
            }
            return lines.isEmpty ? nil : ReviewGroup(consequence: group, lines: lines)
        }
    }
}
