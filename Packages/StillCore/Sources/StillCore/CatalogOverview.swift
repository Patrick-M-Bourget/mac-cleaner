import Foundation

/// An estimated size that keeps unknown distinct from zero (SPEC section 1).
public enum SizeEstimate: Equatable, Sendable {
    case measured(Int64)
    /// Part of it couldn't be read or sizing stopped early; the real size is larger.
    case atLeast(Int64)
    /// Estimated rather than measured, such as an Ollama model's unshared blobs: "About X".
    case about(Int64)
    /// Nothing could be measured.
    case unknown

    /// A candidate's estimate, from allocated size where available. An incomplete size of 0 is unknown.
    public init(_ candidate: Candidate) {
        let bytes = candidate.estimatedBytes
        self = !candidate.sizeComplete ? (bytes > 0 ? .atLeast(bytes) : .unknown) : candidate.sizeIsEstimate ? .about(bytes) : .measured(bytes)
    }
    /// The sum of estimates. Any unknown or lower-bound part makes the sum a lower bound; otherwise any
    /// estimated part makes it an estimate.
    public init(sum parts: [SizeEstimate]) {
        var bytes: Int64 = 0, complete = true, estimated = false
        for part in parts {
            switch part {
            case .measured(let value): bytes += value
            case .about(let value): bytes += value; estimated = true
            case .atLeast(let value): bytes += value; complete = false
            case .unknown: complete = false
            }
        }
        self = !complete ? (bytes > 0 ? .atLeast(bytes) : .unknown) : estimated ? .about(bytes) : .measured(bytes)
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
        /// How many items the category's rules found.
        public let itemCount: Int
        /// What the cleanup plan shows under the category, decided per scan from what was found.
        public var planLayout: PlanLayout { rules.count > 1 ? .ruleRows : itemCount > 1 ? .items : .categoryOnly }
    }
    /// The category's checkbox is the only choice (one rule, one item); its items without a rule row (one rule,
    /// several items); or a row per rule (two or more rules). Selection underneath is per item either way.
    public enum PlanLayout: Sendable, Equatable { case categoryOnly, items, ruleRows }
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
            let found = candidates.filter { ids.contains($0.ruleID) }
            return Row(category: category, rules: rules, estimate: SizeEstimate(sum: found.map(SizeEstimate.init)), itemCount: found.count)
        }
    }

    /// How many rows Overview shows before "Show N more".
    public static let leadingRowCount = 5
    /// Overview's rows, largest first: a category that measured 0 bytes is hidden, and one whose size is unknown
    /// stays (unknown is never 0) after every sized one. Ties keep catalog order.
    public var visibleRows: [Row] {
        rows.enumerated().filter { $0.element.estimate != .measured(0) }
            .sorted { left, right in
                let a = left.element.estimate.sortBytes, b = right.element.estimate.sortBytes
                return a != b ? a > b : left.offset < right.offset
            }.map(\.element)
    }
}

private extension SizeEstimate {
    /// Unknown sorts below every known size, a 0-byte one included.
    var sortBytes: Int64 {
        switch self {
        case .measured(let bytes), .about(let bytes), .atLeast(let bytes): bytes
        case .unknown: -1
        }
    }
}
