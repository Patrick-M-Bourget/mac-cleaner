import Foundation

/// The storage map's layout (Decision 147, #685): one folder's children as a squarified treemap in a rectangle. Pure
/// geometry for Explore storage's Map view to draw; it never reads the disk.
///
/// Children are laid out largest first, equal sizes in Finder's name order (`ListSort`), each with the area its size on
/// disk earns ("At least" sizes by their known part). Zero-byte children take no area. Blocks too small to show even a
/// truncated name and size merge into one "N smaller items" block laid out last; merging changes the layout, so it
/// repeats until no other block is too small. Sizes are never distorted: a block still too small to label (a lone small
/// one, or a small merged one) keeps its true size and is listed in `tooSmallToLabel`, which the view names in one line
/// under the map.
public struct StorageMapLayout<ID: Hashable & Sendable>: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let id: ID
        public let name: String
        /// Size on disk; for an "At least" size, its known part.
        public let bytes: Int64
        public let isAtLeast: Bool
        public init(id: ID, name: String, bytes: Int64, isAtLeast: Bool = false) {
            self.id = id; self.name = name; self.bytes = bytes; self.isAtLeast = isAtLeast
        }
    }

    /// In the bounds' coordinates, origin at the top left.
    public struct Rect: Sendable, Equatable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    }

    public enum Content: Sendable, Equatable {
        case item(Item)
        /// "N smaller items": their count, total, whether any is "At least", and their ids.
        case smaller(count: Int, bytes: Int64, isAtLeast: Bool, ids: [ID])
    }

    public enum BlockID: Hashable, Sendable { case item(ID), smaller }

    public struct Block: Sendable, Equatable {
        public let content: Content
        public let frame: Rect
        /// Whether a name and size fit; an unlabeled block is named under the map instead.
        public let isLabeled: Bool
        public var id: BlockID { if case .item(let item) = content { .item(item.id) } else { .smaller } }
        public var isMerged: Bool { id == .smaller }
    }

    /// Drawing order: largest first, the merged block last.
    public let blocks: [Block]

    /// Blocks drawn at their true size but too small to label, in drawing order.
    public var tooSmallToLabel: [Block] { blocks.filter { !$0.isLabeled } }

    public init(items: [Item], width: Double, height: Double, minimumLabelWidth: Double, minimumLabelHeight: Double) {
        guard width > 0, height > 0 else { blocks = []; return }
        let fits = { (rect: Rect) in rect.width >= minimumLabelWidth && rect.height >= minimumLabelHeight }
        var kept = ListSort().ordered(items.filter { $0.bytes > 0 }, name: \.name, bytes: \.bytes).map(Content.item)
        var tiny: [Item] = []
        while true {
            var contents = kept
            if !tiny.isEmpty {
                contents.append(.smaller(count: tiny.count, bytes: tiny.reduce(0) { $0 + $1.bytes },
                                         isAtLeast: tiny.contains(where: \.isAtLeast), ids: tiny.map(\.id)))
            }
            let frames = Self.squarify(contents.map(Self.bytes), width: width, height: height)
            let laidOut = zip(contents, frames).map { Block(content: $0, frame: $1, isLabeled: fits($1)) }
            let more = laidOut.compactMap { block -> Item? in
                if case .item(let item) = block.content, !block.isLabeled { item } else { nil }
            }
            // Each pass moves at least one item into the merged block, so this ends.
            if more.isEmpty || (more.count == 1 && tiny.isEmpty) { blocks = laidOut; return }
            tiny += more
            let merged = Set(more.map(\.id))
            kept.removeAll { if case .item(let item) = $0 { merged.contains(item.id) } else { false } }
        }
    }

    private static func bytes(_ content: Content) -> Int64 {
        switch content {
        case .item(let item): item.bytes
        case .smaller(_, let bytes, _, _): bytes
        }
    }

    /// Bruls, Huizing and van Wijk's squarified treemap: rows along the shorter side, each grown while its worst aspect
    /// ratio improves. `sizes` must be positive; frames come back in the same order.
    static func squarify(_ sizes: [Int64], width: Double, height: Double) -> [Rect] {
        let total = sizes.reduce(0.0) { $0 + Double($1) }
        guard total > 0 else { return [] }
        let scale = width * height / total
        var areas = sizes.map { Double($0) * scale }[...]
        var frames: [Rect] = []
        var x = 0.0, y = 0.0, w = width, h = height
        func worst(_ row: ArraySlice<Double>, side: Double) -> Double {
            let sum = row.reduce(0, +), largest = row.max() ?? 0, smallest = row.min() ?? 0
            return max(side * side * largest / (sum * sum), sum * sum / (side * side * smallest))
        }
        while !areas.isEmpty {
            let side = min(w, h)
            var count = 1
            while count < areas.count,
                  worst(areas.prefix(count + 1), side: side) <= worst(areas.prefix(count), side: side) { count += 1 }
            let row = areas.prefix(count)
            areas = areas.dropFirst(count)
            let sum = row.reduce(0, +)
            let last = areas.isEmpty
            if w >= h {
                // A column on the left; the last row takes what's left, so rounding never leaves a gap.
                let columnWidth = last ? w : sum / h
                var top = y
                for (n, area) in row.enumerated() {
                    let rowHeight = n == row.count - 1 ? y + h - top : area / columnWidth
                    frames.append(Rect(x: x, y: top, width: columnWidth, height: rowHeight)); top += rowHeight
                }
                x += columnWidth; w -= columnWidth
            } else {
                let rowHeight = last ? h : sum / w
                var left = x
                for (n, area) in row.enumerated() {
                    let columnWidth = n == row.count - 1 ? x + w - left : area / rowHeight
                    frames.append(Rect(x: left, y: y, width: columnWidth, height: rowHeight)); left += columnWidth
                }
                y += rowHeight; h -= rowHeight
            }
        }
        return frames
    }
}
