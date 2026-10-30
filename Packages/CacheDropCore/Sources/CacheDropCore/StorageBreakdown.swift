import Foundation

/// What a storage meter draws inside the disk's used space (#164): only what CacheDrop found, never a whole-disk breakdown.
/// The 3 largest categories get their own segment, the rest fold into one "Other reclaimable", and the Trash gets its own.
/// While a cleanup runs, what it moved to the Trash gets one more, "Goes to the Trash", just before the Trash (#343, #355).
public struct StorageBreakdown: Sendable, Equatable {
    public enum Part: Sendable, Hashable {
        case category(CatalogCategory)
        /// The categories past the largest 3, largest first.
        case other([CatalogCategory])
        /// What a cleanup moved to the Trash: it frees nothing until the Trash is emptied (#343).
        case goingToTrash
        case trash
    }
    public struct Segment: Sendable, Equatable, Identifiable {
        public let part: Part
        /// What was found, as Overview shows it: unscaled, for the tooltip.
        public let estimate: SizeEstimate
        /// The width to draw, in bytes of the used space.
        public let bytes: Int64
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
    let isScaled: Bool
    /// The sidebar's one "Reclaimable" segment: every category, without the Trash or what a cleanup sent there.
    public var reclaimableBytes: Int64 { segments.filter { !$0.part.isTrash }.reduce(0) { $0 + $1.bytes } }

    /// Overview's categories.
    public init(used: Int64, total: Int64, overview: CatalogOverview, trash: TrashContents) {
        self.init(used: used, total: total, categories: overview.rows.map { ($0.category, $0.estimate) }, trash: trash)
    }

    /// `categories` in catalog order, which breaks ties between equal sizes. `toTrash` is how much of each a cleanup sent
    /// to the Trash: it leaves its category's segment for "Goes to the Trash" (#343).
    public init(used: Int64, total: Int64, categories: [(category: CatalogCategory, estimate: SizeEstimate)], trash: TrashContents,
                toTrash: [CatalogCategory: Int64]? = nil) {
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
        var parts: [(part: Part, estimate: SizeEstimate, bytes: Int64)] =
            staying.prefix(Self.leadingCategoryCount).map { (.category($0.category), $0.estimate, $0.bytes) }
        let rest = staying.dropFirst(Self.leadingCategoryCount)
        if !rest.isEmpty {
            parts.append((.other(rest.map(\.category)), SizeEstimate(sum: rest.map(\.estimate)), rest.reduce(0) { $0 + $1.bytes }))
        }
        let sentBytes = categories.reduce(0) { $0 + toTheTrash($1) }
        if sentBytes > 0 { parts.append((.goingToTrash, .measured(sentBytes), sentBytes)) }
        if case .holds(let bytes) = trash, bytes > 0 { parts.append((.trash, .measured(bytes), bytes)) }
        guard total > 0, used > 0, used <= total else { segments = []; isScaled = false; return }
        let found = parts.reduce(0) { $0 + $1.bytes }
        let scaled = found > used, scale = Double(used) / Double(max(found, 1))
        isScaled = scaled
        let fit = { (bytes: Int64) in scaled ? Int64((Double(bytes) * scale).rounded(.down)) : bytes }
        segments = parts.map { Segment(part: $0.part, estimate: $0.estimate, bytes: fit($0.bytes)) }
    }
}

private extension SizeEstimate {
    /// The same kind of estimate, `bytes` smaller: what stays in a category once a cleanup sends `bytes` to the Trash.
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
    /// The Trash, or what a cleanup sent there: space that stays used until the Trash is emptied.
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
