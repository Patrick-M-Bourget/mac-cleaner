import Testing
@testable import CacheDropCore

private typealias Layout = StorageMapLayout<String>

private func item(_ name: String, _ bytes: Int64, atLeast: Bool = false) -> Layout.Item {
    Layout.Item(id: name, name: name, bytes: bytes, isAtLeast: atLeast)
}

/// A generous label size, so nothing merges unless a test wants it to.
private func layout(_ items: [Layout.Item], width: Double = 600, height: Double = 400, label: (Double, Double) = (1, 1)) -> Layout {
    Layout(items: items, width: width, height: height, minimumLabelWidth: label.0, minimumLabelHeight: label.1)
}

private func names(_ layout: Layout) -> [String] {
    layout.blocks.map { block in
        switch block.content {
        case .item(let item): item.name
        case .smaller(let count, _, _, _): "\(count) smaller"
        }
    }
}

private func overlaps(_ a: Layout.Rect, _ b: Layout.Rect) -> Bool {
    let epsilon = 1e-6
    return a.x + epsilon < b.x + b.width && b.x + epsilon < a.x + a.width && a.y + epsilon < b.y + b.height && b.y + epsilon < a.y + a.height
}

/// Decision 147: every block's area is its share of the folder, and the blocks tile the bounds exactly, without overlap.
@Test func blocksTileTheBoundsInProportionToSize() {
    let items = [item("a", 600), item("b", 600), item("c", 400), item("d", 300), item("e", 200), item("f", 200), item("g", 100)]
    let map = layout(items, width: 600, height: 400)
    #expect(map.blocks.count == 7)
    let total = 600.0 * 400
    for block in map.blocks {
        guard case .item(let item) = block.content else { Issue.record("Nothing should merge"); continue }
        #expect(abs(block.frame.width * block.frame.height - total * Double(item.bytes) / 2400) < 0.01, "\(item.name)")
        #expect(block.frame.x >= -1e-6 && block.frame.y >= -1e-6)
        #expect(block.frame.x + block.frame.width <= 600 + 1e-6 && block.frame.y + block.frame.height <= 400 + 1e-6)
    }
    let covered = map.blocks.reduce(0) { $0 + $1.frame.width * $1.frame.height }
    #expect(abs(covered - total) < 0.01)
    for (n, a) in map.blocks.enumerated() { for b in map.blocks.dropFirst(n + 1) { #expect(!overlaps(a.frame, b.frame)) } }
}

/// Squarified keeps blocks near square: the classic example (Bruls et al.) lays out with no block worse than 3:1, where
/// slicing in one direction would give 24:1 strips.
@Test func blocksStayNearSquare() {
    let items = [item("a", 6), item("b", 6), item("c", 4), item("d", 3), item("e", 2), item("f", 2), item("g", 1)]
    let map = layout(items, width: 6, height: 4)
    let worst = map.blocks.map { max($0.frame.width / $0.frame.height, $0.frame.height / $0.frame.width) }.max() ?? 0
    #expect(worst <= 3, "Worst aspect ratio \(worst)")
}

/// Largest first; equal sizes go by name as Finder sorts them (`ListSort`), so the same folder always draws the same.
@Test func orderIsLargestFirstThenFinderNameOrder() {
    let items = [item("logic pro", 50), item("Ableton Live 12", 300), item("Zebra", 900), item("Ableton Live 2", 300)]
    #expect(names(layout(items)) == ["Zebra", "Ableton Live 2", "Ableton Live 12", "logic pro"])
    #expect(layout(items) == layout(items.reversed()), "Input order doesn't matter")
}

/// Zero-byte children take no area; an empty or zero folder, or no room, draws nothing; one child fills the bounds.
@Test func zeroSizesEmptyFoldersAndASingleChild() {
    #expect(names(layout([item("big", 10), item("empty", 0)])) == ["big"])
    #expect(layout([]).blocks.isEmpty)
    #expect(layout([item("empty", 0)]).blocks.isEmpty)
    #expect(layout([item("a", 5)], width: 0, height: 400).blocks.isEmpty)
    let single = layout([item("only", 42)], width: 300, height: 200)
    #expect(single.blocks.map(\.frame) == [Layout.Rect(x: 0, y: 0, width: 300, height: 200)])
    #expect(single.blocks.first?.isLabeled == true)
}

/// Decision 147: blocks too small to label merge into one "N smaller items" block, laid out last, carrying their count,
/// total and ids; the rest stay labeled.
@Test func blocksTooSmallToLabelMergeIntoOneBlockLaidOutLast() {
    let items = [item("big", 9_000), item("mid", 3_000)] + (1...6).map { item("tiny\($0)", 10) }
    let map = layout(items, width: 600, height: 400, label: (64, 36))
    #expect(names(map) == ["big", "mid", "6 smaller"])
    guard case .smaller(let count, let bytes, let atLeast, let ids) = map.blocks.last?.content else { Issue.record("No merged block"); return }
    #expect(count == 6 && bytes == 60 && !atLeast)
    #expect(Set(ids) == Set((1...6).map { "tiny\($0)" }))
    let covered = map.blocks.reduce(0) { $0 + $1.frame.width * $1.frame.height }
    #expect(abs(covered - 600 * 400) < 0.01, "The merged block keeps its children's area")
}

/// Merging changes the layout, so it repeats until no other block is too small: nothing small is left unmerged.
@Test func mergingRepeatsUntilNoOtherBlockIsTooSmall() {
    let items = [item("big", 10_000)] + (1...12).map { item("small\($0)", 120 + Int64($0)) }
    let map = layout(items, width: 400, height: 300, label: (64, 36))
    for block in map.blocks where !block.isMerged {
        #expect(block.frame.width >= 64 && block.frame.height >= 36, "\(names(map))")
    }
    #expect(map.blocks.filter(\.isMerged).count <= 1)
}

/// Decision 147: sizes are never distorted. A lone small block with nothing to merge into stays at its true size,
/// unlabeled, and is named in the "Too small to label" line; so is a merged block that is itself too small.
@Test func aBlockStillTooSmallToLabelKeepsItsSizeAndIsListed() {
    let lone = layout([item("Documents", 172_000), item("Developer", 28_400), item("Downloads", 500)], width: 920, height: 356, label: (64, 36))
    #expect(names(lone) == ["Documents", "Developer", "Downloads"], "One small block has nothing to merge into")
    #expect(lone.tooSmallToLabel.map(\.id) == [.item("Downloads")])
    let downloads = lone.blocks.first { $0.id == .item("Downloads") }!
    #expect(abs(downloads.frame.width * downloads.frame.height - 920 * 356 * 500 / 200_900) < 0.01)

    let crowded = layout([item("big", 1_000_000)] + (1...5).map { item("t\($0)", 1) }, width: 400, height: 300, label: (64, 36))
    #expect(crowded.tooSmallToLabel.count == 1)
    #expect(crowded.tooSmallToLabel.first?.isMerged == true, "A merged block too small to label is listed, not dropped")
}

/// "At least" sizes take the area of their known part and keep the flag; a merged block is "at least" if any child is.
@Test func atLeastSizesKeepTheirFlag() {
    let map = layout([item("Documents", 172, atLeast: true), item("Developer", 28)])
    guard case .item(let documents) = map.blocks.first?.content else { Issue.record("Missing"); return }
    #expect(documents.isAtLeast)
    let merged = layout([item("big", 100_000)] + [item("a", 1, atLeast: true), item("b", 1)], width: 400, height: 300, label: (64, 36))
    guard case .smaller(_, _, let atLeast, _) = merged.blocks.last?.content else { Issue.record("No merged block"); return }
    #expect(atLeast)
}
