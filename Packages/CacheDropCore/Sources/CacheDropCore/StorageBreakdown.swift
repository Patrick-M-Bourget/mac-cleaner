import Foundation

/// What a storage meter draws inside the disk's used space (#164): only what CacheDrop found, never a whole-disk breakdown.
/// The 3 largest categories get their own segment, the rest fold into one "Other reclaimable", and the Trash gets its own.
/// A selection's Trash-bound items get one more, "Goes to the Trash", just before the Trash (#343).
public struct StorageBreakdown: Sendable, Equatable {
    public enum Part: Sendable, Hashable {
        case category(CatalogCategory)
        /// The categories past the largest 3, largest first.
        case other([CatalogCategory])
        /// A selection's items that go to the Trash: they free nothing until it is emptied (#343).
        case goingToTrash
        case trash
    }
    public struct Segment: Sendable, Equatable, Identifiable {
        public let part: Part
        /// What was found, as Overview shows it: unscaled, for the tooltip.
        public let estimate: SizeEstimate
        /// The width to draw, in bytes of the used space.
        public let bytes: Int64
        /// Of `bytes`, what the selection would free; nil when the meter shows no selection.
        public let highlightedBytes: Int64?
        public var id: String {
            switch part {
            case .category(let category): category.rawValue
            case .other: "other"
            case .goingToTrash: "goingToTrash"
            case .trash: "trash"
            }
        }
    }
    /// How many categories get their own segment before "Other reclaimable".
    public static let leadingCategoryCount = 3
    public let used: Int64
    public let total: Int64
    public let segments: [Segment]
    /// The estimates were larger than the used space (copies that share disk blocks) and were scaled to fit.
    public let isScaled: Bool
    /// The sidebar's one "Reclaimable" segment: every category, without the Trash or what a selection sends there.
    public var reclaimableBytes: Int64 { segments.filter { !$0.part.isTrash }.reduce(0) { $0 + $1.bytes } }

    /// Overview's categories, with what `highlighting` (Smart clean's ticked items) would free in each; its Trash-bound
    /// items go to their own segment instead (#343).
    public init(used: Int64, total: Int64, overview: CatalogOverview, trash: TrashContents, highlighting: [Candidate]? = nil) {
        let perCategory = { (items: [Candidate]) in
            Dictionary(overview.rows.map { row in
                let ids = Set(row.rules.map(\.id))
                return (row.category, items.filter { ids.contains($0.ruleID) }.reduce(0) { $0 + $1.estimatedBytes })
            }, uniquingKeysWith: +)
        }
        self.init(used: used, total: total, categories: overview.rows.map { ($0.category, $0.estimate) }, trash: trash,
                  highlighted: highlighting.map { perCategory($0.filter(\.releasesSpace)) },
                  toTrash: highlighting.map { perCategory($0.filter { !$0.releasesSpace }).filter { $0.value > 0 } })
    }

    /// `categories` in catalog order, which breaks ties between equal sizes. `highlighted` is how much of each category a
    /// selection would free (Smart clean); nil draws every segment in full. `toTrash` is how much of each the selection
    /// sends to the Trash: it leaves its category's segment for "Goes to the Trash" (#343).
    public init(used: Int64, total: Int64, categories: [(category: CatalogCategory, estimate: SizeEstimate)], trash: TrashContents,
                highlighted: [CatalogCategory: Int64]? = nil, toTrash: [CatalogCategory: Int64]? = nil) {
        self.used = used
        self.total = total
        // What each category sends to the Trash, never more than it holds; it leaves the category, whose segment is drawn,
        // ranked and named at what stays (#343), so the tooltips never count it twice.
        let toTheTrash = { (entry: (category: CatalogCategory, estimate: SizeEstimate)) in
            min(max(0, toTrash?[entry.category] ?? 0), entry.estimate.drawnBytes ?? 0)
        }
        let staying = categories.enumerated().compactMap { index, entry -> (order: Int, category: CatalogCategory, estimate: SizeEstimate, bytes: Int64)? in
            guard let bytes = entry.estimate.drawnBytes, bytes > toTheTrash(entry) else { return nil }
            return (index, entry.category, entry.estimate.less(toTheTrash(entry)), bytes - toTheTrash(entry))
        }.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.order < $1.order }
        let marked = { (categories: [CatalogCategory]) in highlighted.map { selection in categories.reduce(0) { $0 + max(0, selection[$1] ?? 0) } } }
        var parts: [(part: Part, estimate: SizeEstimate, bytes: Int64, highlighted: Int64?)] =
            staying.prefix(Self.leadingCategoryCount).map { (.category($0.category), $0.estimate, $0.bytes, marked([$0.category])) }
        let rest = staying.dropFirst(Self.leadingCategoryCount)
        if !rest.isEmpty {
            parts.append((.other(rest.map(\.category)), SizeEstimate(sum: rest.map(\.estimate)), rest.reduce(0) { $0 + $1.bytes }, marked(rest.map(\.category))))
        }
        let sentBytes = categories.reduce(0) { $0 + toTheTrash($1) }
        if sentBytes > 0 { parts.append((.goingToTrash, .measured(sentBytes), sentBytes, sentBytes)) }
        // Smart clean never empties the Trash.
        if case .holds(let bytes) = trash, bytes > 0 { parts.append((.trash, .measured(bytes), bytes, highlighted.map { _ in 0 })) }
        guard total > 0, used > 0, used <= total else { segments = []; isScaled = false; return }
        let found = parts.reduce(0) { $0 + $1.bytes }
        let scaled = found > used, scale = Double(used) / Double(max(found, 1))
        isScaled = scaled
        let fit = { (bytes: Int64) in scaled ? Int64((Double(bytes) * scale).rounded(.down)) : bytes }
        segments = parts.map { part in
            let bytes = fit(part.bytes)
            return Segment(part: part.part, estimate: part.estimate, bytes: bytes, highlightedBytes: part.highlighted.map { min(bytes, fit($0)) })
        }
    }
}

private extension SizeEstimate {
    /// The same kind of estimate, `bytes` smaller: what stays in a category once a selection sends `bytes` to the Trash.
    func less(_ bytes: Int64) -> SizeEstimate {
        switch self {
        case .measured(let value): .measured(max(0, value - bytes))
        case .about(let value): .about(max(0, value - bytes))
        case .atLeast(let value): .atLeast(max(0, value - bytes))
        case .unknown: .unknown
        }
    }
    /// The bytes a meter may draw; nil for an unknown or 0-byte size, which is never drawn.
    var drawnBytes: Int64? {
        switch self {
        case .measured(let bytes), .about(let bytes), .atLeast(let bytes): bytes > 0 ? bytes : nil
        case .unknown: nil
        }
    }
}

extension StorageBreakdown.Part {
    /// The Trash, or what a selection sends there: space that stays used until the Trash is emptied.
    public var isTrash: Bool {
        switch self {
        case .trash, .goingToTrash: true
        case .category, .other: false
        }
    }
}

extension StorageBreakdown.Segment {
    /// The tooltip's size, e.g. "up to 12.2 GB": the same estimate as Overview. Found items are an upper bound because
    /// copies can share disk blocks (SPEC section 6); the Trash is measured as it is.
    public var sizeText: String {
        let bytes = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) }
        if part == .trash, case .measured(let value) = estimate { return bytes(value) }
        switch estimate {
        case .measured(let value): return "up to " + bytes(value)
        case .about(let value): return "about " + bytes(value)
        case .atLeast(let value): return "at least " + bytes(value)
        case .unknown: return "size unknown"
        }
    }
}
