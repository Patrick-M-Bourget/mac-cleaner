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
        public var planLayout: PlanLayout { rules.count > 1 ? .ruleRows : itemCount > 1 || rules.contains(where: \.selectedOneByOne) ? .items : .categoryOnly }
        /// Found nothing, or only 0 bytes: Overview lists it as "Empty" (#372). Unknown is never empty.
        public var isEmpty: Bool { estimate == .measured(0) }
    }
    /// The category's checkbox is the only choice (one rule, one item); its items without a rule row (one rule,
    /// several items, or items chosen one by one, which the category's checkbox never chooses, #240); or a row per rule
    /// (two or more rules). Selection underneath is per item either way.
    public enum PlanLayout: Sendable, Equatable { case categoryOnly, items, ruleRows }
    public let rows: [Row]
    /// "Recommended for review: up to X": every current candidate whose action releases space (SPEC section 6).
    public let recommended: SizeEstimate
    /// Candidates that go to Trash. That space stays used until the Trash is emptied, so it is never in `recommended`.
    public let proposedForTrash: SizeEstimate
    /// The categories Overview's scan can fill, in catalog order, for its empty rows (#372). Not App-managed storage, which
    /// has its own row, nor large and old files (picked folders only) or apps and plug-ins (only what you chose to uninstall).
    private let categories: [CatalogCategory]

    public init(catalog: Catalog, candidates: [Candidate]) {
        var order: [CatalogCategory] = []
        for rule in catalog.rules where !order.contains(rule.category) && candidates.contains(where: { $0.ruleID == rule.id }) {
            order.append(rule.category)
        }
        recommended = SizeEstimate(sum: candidates.filter(\.releasesSpace).map(SizeEstimate.init))
        proposedForTrash = SizeEstimate(sum: candidates.filter { !$0.releasesSpace }.map(SizeEstimate.init))
        rows = order.map { category in
            let rules = catalog.rules.filter { rule in rule.category == category && candidates.contains { $0.ruleID == rule.id } }
            let ids = Set(rules.map(\.id))
            let found = candidates.filter { ids.contains($0.ruleID) }
            return Row(category: category, rules: rules, estimate: SizeEstimate(sum: found.map(SizeEstimate.init)), itemCount: found.count)
        }
        var categories: [CatalogCategory] = []
        for rule in catalog.rules where !categories.contains(rule.category) && rule.action != .guidance && !rule.fromPickedFolders
            && rule.family != .appUninstall && rule.family != .plugInUninstall {
            categories.append(rule.category)
        }
        self.categories = categories
    }

    /// How many rows Overview shows before "Show N more".
    public static let leadingRowCount = 5
    /// Overview's rows (#372): every category, largest first, one whose size is unknown (never 0) after every sized one,
    /// then the empty ones, which found nothing or only 0 bytes, in catalog order. Ties keep catalog order.
    public var visibleRows: [Row] {
        let found = rows.enumerated().filter { !$0.element.isEmpty }
            .sorted { left, right in
                let a = left.element.estimate.sortBytes, b = right.element.estimate.sortBytes
                return a != b ? a > b : left.offset < right.offset
            }.map(\.element)
        let empty = categories.compactMap { category -> Row? in
            guard let row = rows.first(where: { $0.category == category }) else { return Row(category: category, rules: [], estimate: .measured(0), itemCount: 0) }
            return row.isEmpty ? row : nil
        }
        return found + empty
    }
}

extension SizeEstimate {
    /// Unknown sorts below every known size, a 0-byte one included (Overview's rows, Applications' Size order, #295).
    public var sortBytes: Int64 {
        switch self {
        case .measured(let bytes), .about(let bytes), .atLeast(let bytes): bytes
        case .unknown: -1
        }
    }
}
