import AppKit
import CacheDropCore
import SwiftUI

/// One child of the folder on show, as the storage map draws it (Decision 147).
struct StorageMapItem: Identifiable {
    let id: String
    let name: String
    /// Size on disk; for an "At least" size, its known part. Unknown reads "Unknown" and takes no area, as zero does.
    let bytes: Int64?
    var isAtLeast = false
    var isFolder = false
    /// A file in the cleanup plan: the only block that uses the accent.
    var isTicked = false
    var isInspected = false
    /// Search dims what doesn't match; the map stays.
    var isDimmed = false
    /// What a click on its block (or its name in the "Too small to label" line) does: open a folder, inspect a file.
    let action: () -> Void
    var sizeText: String { SizeFormatter.text(bytes, complete: !isAtLeast) }
}

/// Explore storage's Map view (Decision 147, #686): the folder on show as a squarified treemap (`StorageMapLayout`), then
/// one quiet line naming the blocks too small to label. It never ticks anything: files go in the plan from the inspector.
struct StorageMap: View {
    /// What the map shows, for VoiceOver ("Downloads, storage map").
    let title: String
    let items: [StorageMapItem]
    /// "N smaller items" switches to List.
    let showSmaller: () -> Void
    @State private var size = CGSize.zero
    private typealias Layout = StorageMapLayout<String>

    var body: some View {
        let layout = Layout(items: items.map { Layout.Item(id: $0.id, name: $0.name, bytes: $0.bytes ?? 0, isAtLeast: $0.isAtLeast) },
                            width: size.width, height: size.height,
                            minimumLabelWidth: CacheDropDesign.Size.storageMapLabelWidth, minimumLabelHeight: Self.labelHeight)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            blocks(layout, byID: byID).frame(maxHeight: CacheDropDesign.Size.storageMap)
            TooSmallToLabelLine(blocks: layout.tooSmallToLabel.compactMap { label(for: $0, byID: byID) })
        }
    }

    /// A labelled block holds a list row's two lines, the name in body and the size in `note`, `Space.xs` apart, inside its padding.
    static let labelHeight: CGFloat = {
        let line = { (style: NSFont.TextStyle) in NSLayoutManager().defaultLineHeight(for: NSFont.preferredFont(forTextStyle: style)) }
        return line(.body) + CacheDropDesign.Space.xs + line(.callout) + StorageMapBlock.padding * 2
    }()

    private func blocks(_ layout: Layout, byID: [String: StorageMapItem]) -> some View {
        // Every block gives up one gap on its trailing and bottom sides, so the area starts one gap in: blocks sit one gap
        // apart and one gap from each edge.
        Color.clear
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = CGSize(width: $0.width - StorageMapBlock.gap, height: $0.height - StorageMapBlock.gap) }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(layout.blocks.enumerated()), id: \.element.id) { order, block in
                        StorageMapBlock(block: block, item: Self.itemID(block).flatMap { byID[$0] }, showSmaller: showSmaller)
                            // VoiceOver reads the blocks in size order, as they're drawn.
                            .accessibilitySortPriority(Double(layout.blocks.count - order))
                    }
                }.padding([.top, .leading], StorageMapBlock.gap)
            }
            .background(CacheDropDesign.reading, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface))
            .overlay(RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface).stroke(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.regular))
            .clipShape(RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface))
            .accessibilityElement(children: .contain).accessibilityLabel(title + ", storage map").accessibilityIdentifier("explorerMap")
    }

    private func label(for block: Layout.Block, byID: [String: StorageMapItem]) -> TooSmallToLabelLine.Entry? {
        switch block.content {
        case .item(let item):
            guard let shown = byID[item.id] else { return nil }
            return .init(name: shown.name, size: shown.sizeText, action: shown.action)
        case .smaller(let count, let bytes, let isAtLeast, _):
            return .init(name: StorageMapBlock.smallerName(count), size: SizeFormatter.text(bytes, complete: !isAtLeast), action: showSmaller)
        }
    }

    /// Nil for the merged "N smaller items" block.
    private static func itemID(_ block: Layout.Block) -> String? {
        if case .item(let item) = block.content { item.id } else { nil }
    }
}

/// One block: a neutral fill (track for folders, surface for files, selected for ticked files), its name and size when they fit.
private struct StorageMapBlock: View {
    let block: StorageMapLayout<String>.Block
    /// Nil for the merged "N smaller items" block.
    let item: StorageMapItem?
    let showSmaller: () -> Void

    static let gap = CacheDropDesign.Space.xs
    static let padding = CacheDropDesign.Space.sm
    static func smallerName(_ count: Int) -> String { count == 1 ? "1 smaller item" : "\(count) smaller items" }

    private var name: String {
        if let item { return item.name }
        if case .smaller(let count, _, _, _) = block.content { return Self.smallerName(count) }
        return ""
    }
    private var sizeText: String {
        if let item { return item.sizeText }
        if case .smaller(_, let bytes, let isAtLeast, _) = block.content { return SizeFormatter.text(bytes, complete: !isAtLeast) }
        return ""
    }
    private var fill: Color {
        guard let item else { return CacheDropDesign.reading }
        if item.isFolder { return CacheDropDesign.capacityTrack }
        return item.isTicked ? CacheDropDesign.selection : CacheDropDesign.summary
    }
    private var tooltip: String { item == nil ? "Show them in the list" : name + " · " + sizeText + " on disk" }
    private var accessibilityName: String { name + ", " + sizeText + " on disk" }
    private var identifier: String { item == nil ? "explorerMapSmaller" : "explorerMapBlock-" + name }
    private var isInspected: Bool { item?.isInspected ?? false }
    /// Search dims what doesn't match as a rescan dims the list's rows.
    private var opacity: Double { item?.isDimmed == true ? CacheDropDesign.Opacity.waiting : 1 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row) }

    var body: some View {
        let frame = block.frame
        let width: CGFloat = max(0, CGFloat(frame.width) - Self.gap), height: CGFloat = max(0, CGFloat(frame.height) - Self.gap)
        Button(action: item?.action ?? showSmaller) { label }
            .buttonStyle(.plain)
            .frame(width: width, height: height)
            .offset(x: CGFloat(frame.x), y: CGFloat(frame.y))
            .opacity(opacity)
            .help(tooltip)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(isInspected ? .isSelected : [])
            .accessibilityIdentifier(identifier)
    }

    private var label: some View {
        ZStack(alignment: .topLeading) {
            shape.fill(fill)
            // The inspected block takes the list's inspected tint.
            if isInspected { shape.fill(CacheDropDesign.focus.opacity(CacheDropDesign.Opacity.inspectedItem)) }
            if item == nil { shape.strokeBorder(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.regular) }
            if block.isLabeled {
                // A list row's two lines: the name in body, the size in note (InspectableItemRow).
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                    HStack(spacing: CacheDropDesign.Space.xs) {
                        if item?.isFolder == true { Image(cacheDropSymbol: "folder").foregroundStyle(.secondary) }
                        Text(name).foregroundStyle(item == nil ? .secondary : .primary).lineLimit(1).truncationMode(.tail)
                    }
                    Text(sizeText).font(CacheDropDesign.TypeStyle.note).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }.padding(Self.padding)
            }
            if item?.isTicked == true {
                Image(systemName: "checkmark").foregroundStyle(CacheDropDesign.focus)
                    .padding(Self.padding).frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
        .contentShape(shape)
    }
}

/// "Too small to label: **Downloads** · 10.0 GB", each name a link doing what a click on its block does; shown only when
/// a block is drawn at its true size without a label, so nothing is reachable only by hovering (Decision 147).
private struct TooSmallToLabelLine: View {
    struct Entry { let name: String; let size: String; let action: () -> Void }
    let blocks: [Entry]
    var body: some View {
        if !blocks.isEmpty {
            HStack(spacing: 0) {
                Text("Too small to label: ").foregroundStyle(.secondary)
                ForEach(Array(blocks.enumerated()), id: \.offset) { n, entry in
                    if n > 0 { Text(", ").foregroundStyle(.secondary) }
                    // The name keeps the link colour: it does what a click on its block does.
                    Button(entry.name, action: entry.action).buttonStyle(.link).accessibilityIdentifier("explorerMapTooSmall-" + entry.name)
                    Text(" · " + entry.size).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(CacheDropDesign.TypeStyle.caption).lineLimit(1)
            .accessibilityElement(children: .contain).accessibilityIdentifier("explorerMapTooSmall")
        }
    }
}

#if DEBUG
/// The Design gallery's storage map examples (#686): each state of the prototype's Map, synthetic and inert.
struct StorageMapGalleryExamples: View {
    private static let gb: Int64 = 1_000_000_000
    private static func file(_ name: String, _ gb: Double, ticked: Bool = false, inspected: Bool = false, dimmed: Bool = false) -> StorageMapItem {
        StorageMapItem(id: name, name: name, bytes: Int64(gb * Double(Self.gb)), isTicked: ticked, isInspected: inspected, isDimmed: dimmed, action: {})
    }
    private static func folder(_ name: String, _ gb: Double, atLeast: Bool = false, dimmed: Bool = false) -> StorageMapItem {
        StorageMapItem(id: name, name: name, bytes: Int64(gb * Double(Self.gb)), isAtLeast: atLeast, isFolder: true, isDimmed: dimmed, action: {})
    }
    /// The prototype's Downloads: installers and archives, then many small files that merge.
    private static func downloads(ticked: Bool = false, inspected: Bool = false, query: String = "") -> [StorageMapItem] {
        let dim = { (name: String) in !query.isEmpty && !name.localizedCaseInsensitiveContains(query) }
        return [("Xcode_26.xip", 4.2), ("Logic Pro sounds.dmg", 2.6), ("Ableton Live 12.dmg", 1.5), ("Archive 2024.zip", 0.9), ("Old project.zip", 0.6),
                ("Screenshot 2026-10-28.png", 0.04), ("Invoice-1042.pdf", 0.03), ("Boarding pass.pdf", 0.02), ("Setlist.numbers", 0.02),
                ("Meeting notes.txt", 0.01), ("Logo-final.svg", 0.01)]
            .map { file($0.0, $0.1, ticked: ticked && $0.0 == "Logic Pro sounds.dmg", inspected: inspected && $0.0 == "Logic Pro sounds.dmg", dimmed: dim($0.0)) }
    }
    private func example(_ title: String, _ items: [StorageMapItem]) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Text(title).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            // A scroll view proposes no height, so the example takes the map's full one.
            StorageMap(title: "Synthetic", items: items, showSmaller: {}).frame(height: CacheDropDesign.Size.storageMap + CacheDropDesign.Space.xl)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            Text("Inert, no scans").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            example("A plain map", [Self.folder("Music", 96), Self.folder("Developer", 28.4), Self.folder("Downloads", 10), Self.file("Backup.sparsebundle", 18)])
            example("Scanned folders · At least", [Self.folder("Documents", 172, atLeast: true), Self.folder("Developer", 28.4), Self.folder("Downloads", 10)])
            example("Downloads · N smaller items", Self.downloads())
            example("A ticked file", Self.downloads(ticked: true))
            example("The ticked file, inspected", Self.downloads(ticked: true, inspected: true))
            example("Search “zip” dims the rest", Self.downloads(query: "zip"))
            example("Too small to label", [Self.folder("Documents", 172, atLeast: true), Self.folder("Developer", 28.4), Self.folder("Downloads", 0.4)])
        }
    }
}
#endif
