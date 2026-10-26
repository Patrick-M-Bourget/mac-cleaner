import Foundation

/// An estimated size that keeps unknown distinct from zero (SPEC section 1).
public enum SizeEstimate: Equatable, Sendable {
    case measured(Int64)
    /// Part of it couldn't be read or sizing stopped early; the real size is larger.
    case atLeast(Int64)
    /// Nothing could be measured.
    case unknown

    /// A candidate's estimate, from allocated size where available. An incomplete size of 0 is unknown.
    public init(_ candidate: Candidate) {
        let bytes = candidate.allocatedBytes ?? candidate.logicalBytes
        self = candidate.sizeComplete ? .measured(bytes) : bytes > 0 ? .atLeast(bytes) : .unknown
    }
    /// The sum of estimates. Any unknown or lower-bound part makes the sum a lower bound.
    public init(sum parts: [SizeEstimate]) {
        var bytes: Int64 = 0, complete = true
        for part in parts {
            switch part {
            case .measured(let value): bytes += value
            case .atLeast(let value): bytes += value; complete = false
            case .unknown: complete = false
            }
        }
        self = complete ? .measured(bytes) : bytes > 0 ? .atLeast(bytes) : .unknown
    }
}

/// Overview's view of the catalog: one row per category that has candidates, in catalog order.
public struct CatalogOverview: Sendable {
    public struct Row: Sendable, Identifiable {
        public var id: String { category.rawValue }
        public let category: CatalogCategory
        /// The category's rules that found something on this Mac, in catalog order.
        public let rules: [CleanupRule]
        public let estimate: SizeEstimate
    }
    public let rows: [Row]
    /// "Recommended for review: up to X": every current candidate whose action releases space (SPEC section 6).
    public let recommended: SizeEstimate
    /// Candidates that go to Trash. That space stays used until the Trash is emptied, so it is never in `recommended`.
    public let proposedForTrash: SizeEstimate

    public init(catalog: Catalog, candidates: [Candidate]) {
        var order: [CatalogCategory] = []
        for rule in catalog.rules where !order.contains(rule.category) && candidates.contains(where: { $0.ruleID == rule.id }) {
            order.append(rule.category)
        }
        recommended = SizeEstimate(sum: candidates.filter { $0.action != .trash }.map(SizeEstimate.init))
        proposedForTrash = SizeEstimate(sum: candidates.filter { $0.action == .trash }.map(SizeEstimate.init))
        rows = order.map { category in
            let rules = catalog.rules.filter { rule in rule.category == category && candidates.contains { $0.ruleID == rule.id } }
            let ids = Set(rules.map(\.id))
            let estimate = SizeEstimate(sum: candidates.filter { ids.contains($0.ruleID) }.map(SizeEstimate.init))
            return Row(category: category, rules: rules, estimate: estimate)
        }
    }
}
