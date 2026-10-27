import Foundation

/// What a storage meter draws inside the disk's used space (#164): only what CacheDrop found, never a whole-disk breakdown.
/// The 3 largest categories get their own segment, the rest fold into one "Other reclaimable", and the Trash gets its own.
public struct StorageBreakdown: Sendable, Equatable {
    public enum Part: Sendable, Hashable {
        case category(CatalogCategory)
        /// The categories past the largest 3, largest first.
        case other([CatalogCategory])
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
    /// The sidebar's one "Reclaimable" segment: every category, without the Trash.
    public var reclaimableBytes: Int64 { segments.filter { $0.part != .trash }.reduce(0) { $0 + $1.bytes } }

    /// Overview's categories, with what `highlighting` (Smart clean's ticked items) would free in each.
    public init(used: Int64, total: Int64, overview: CatalogOverview, trash: TrashContents, highlighting: [Candidate]? = nil) {
        let highlighted = highlighting.map { items in
            Dictionary(overview.rows.map { row in
                let ids = Set(row.rules.map(\.id))
                return (row.category, items.filter { ids.contains($0.ruleID) }.reduce(0) { $0 + $1.estimatedBytes })
            }, uniquingKeysWith: +)
        }
        self.init(used: used, total: total, categories: overview.rows.map { ($0.category, $0.estimate) }, trash: trash, highlighted: highlighted)
    }

    /// `categories` in catalog order, which breaks ties between equal sizes. `highlighted` is how much of each category a
    /// selection would free (Smart clean); nil draws every segment in full.
    public init(used: Int64, total: Int64, categories: [(category: CatalogCategory, estimate: SizeEstimate)], trash: TrashContents,
                highlighted: [CatalogCategory: Int64]? = nil) {
        self.used = used
        self.total = total
        let sized = categories.enumerated().compactMap { index, entry in entry.estimate.drawnBytes.map { (index, entry.category, entry.estimate, $0) } }
            .sorted { $0.3 != $1.3 ? $0.3 > $1.3 : $0.0 < $1.0 }
        let marked = { (categories: [CatalogCategory]) in highlighted.map { selection in categories.reduce(0) { $0 + max(0, selection[$1] ?? 0) } } }
        var parts: [(part: Part, estimate: SizeEstimate, bytes: Int64, highlighted: Int64?)] =
            sized.prefix(Self.leadingCategoryCount).map { (.category($0.1), $0.2, $0.3, marked([$0.1])) }
        let rest = sized.dropFirst(Self.leadingCategoryCount)
        if !rest.isEmpty {
            parts.append((.other(rest.map(\.1)), SizeEstimate(sum: rest.map(\.2)), rest.reduce(0) { $0 + $1.3 }, marked(rest.map(\.1))))
        }
        // Smart clean never touches the Trash.
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
    /// The bytes a meter may draw; nil for an unknown or 0-byte size, which is never drawn.
    var drawnBytes: Int64? {
        switch self {
        case .measured(let bytes), .about(let bytes), .atLeast(let bytes): bytes > 0 ? bytes : nil
        case .unknown: nil
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
