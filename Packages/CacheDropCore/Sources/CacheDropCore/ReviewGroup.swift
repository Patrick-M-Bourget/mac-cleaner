import Foundation

/// The review's groups: one per consequence, each with one line per catalog category, in catalog order.
public struct ReviewGroup: Sendable, Identifiable {
    public struct Line: Sendable, Identifiable {
        public var id: String { category.rawValue }
        public let category: CatalogCategory
        /// The category's rules with chosen items in this group, in catalog order.
        public let rules: [CleanupRule]
        public let candidates: [Candidate]
        public let estimate: SizeEstimate
        /// Part of it is copies that share disk blocks, so less may come back (SPEC section 6).
        public var isUpperBound: Bool { rules.contains(where: \.estimateIsUpperBound) }
        public func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    }
    public var id: Int { consequence.rawValue }
    public let consequence: ConsequenceGroup
    public let lines: [Line]
    public var candidates: [Candidate] { lines.flatMap(\.candidates) }

    public static func groups(catalog: Catalog, candidates: [Candidate]) -> [ReviewGroup] {
        let found = catalog.rules.filter { rule in candidates.contains { $0.ruleID == rule.id } }
        return ConsequenceGroup.allCases.compactMap { group in
            let rules = found.filter { ConsequenceGroup($0.action) == group }
            var order: [CatalogCategory] = []
            for rule in rules where !order.contains(rule.category) { order.append(rule.category) }
            let lines = order.map { category in
                let inLine = rules.filter { $0.category == category }, ids = Set(inLine.map(\.id))
                let chosen = candidates.filter { ids.contains($0.ruleID) }
                return Line(category: category, rules: inLine, candidates: chosen, estimate: SizeEstimate(sum: chosen.map(SizeEstimate.init)))
            }
            return lines.isEmpty ? nil : ReviewGroup(consequence: group, lines: lines)
        }
    }
}
