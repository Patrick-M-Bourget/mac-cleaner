import CacheDropCore
import SwiftUI

/// The coloured segments a capacity meter draws inside the used space (#164): what CacheDrop found, never a whole-disk
/// breakdown. No legend: each segment has a tooltip, opens its category in the Cleanup plan, and VoiceOver reads them as a list.
struct MeterSegments: View {
    let breakdown: StorageBreakdown
    /// The sidebar's mini meter: one accent segment, "Reclaimable", no breakdown.
    var reclaimableOnly = false
    /// Opens a segment's category, or Other's categories, in the Cleanup plan. The Trash segment never opens anything.
    var open: ((StorageBreakdown.Part) -> Void)? = nil

    private struct Drawn: Identifiable {
        let id: String
        let title: String
        let help: String
        let color: Color
        let bytes: Int64
        /// Of `bytes`, the part drawn in full colour; the rest is dimmed. nil draws all of it in full.
        let highlighted: Int64?
        let part: StorageBreakdown.Part?
    }
    private var drawn: [Drawn] {
        if reclaimableOnly {
            let bytes = breakdown.reclaimableBytes
            guard bytes > 0 else { return [] }
            return [Drawn(id: "reclaimable", title: "Reclaimable", help: "Reclaimable · up to " + CapacityMeter.bytes(bytes),
                          color: CacheDropDesign.meterReclaimable, bytes: bytes, highlighted: nil, part: nil)]
        }
        return breakdown.segments.filter { $0.bytes > 0 }.map { segment in
            Drawn(id: segment.id, title: segment.part.title, help: segment.part.title + " · " + segment.sizeText, color: segment.part.color,
                  bytes: segment.bytes, highlighted: segment.highlightedBytes, part: segment.part)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, total = Double(breakdown.total)
            let usedWidth = width * CGFloat(Double(breakdown.used) / total)
            let segments = drawn
            let gap = segments.isEmpty ? 0 : CacheDropDesign.Size.meterGap
            let widths = segments.map { max(CacheDropDesign.Size.meterSegmentMinimum, width * CGFloat(Double($0.bytes) / total)) }
            let rest = max(0, usedWidth - widths.reduce(0, +) - gap * CGFloat(segments.count))
            ZStack(alignment: .leading) {
                Capsule().fill(CacheDropDesign.capacityTrack)
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        self.segment(segment).frame(width: widths[index])
                    }
                    if rest > 0 { Rectangle().fill(CacheDropDesign.capacityFill).frame(width: rest).accessibilityHidden(true) }
                }.frame(width: max(usedWidth, widths.reduce(0, +)), alignment: .leading).clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(reclaimableOnly ? "sidebarMeterSegments" : "meterSegments")
    }

    @ViewBuilder private func segment(_ segment: Drawn) -> some View {
        let fill = GeometryReader { geometry in
            HStack(spacing: 0) {
                if let highlighted = segment.highlighted {
                    let lit = geometry.size.width * CGFloat(Double(highlighted) / Double(max(segment.bytes, 1)))
                    Rectangle().fill(segment.color).frame(width: lit)
                    Rectangle().fill(segment.color.opacity(CacheDropDesign.Opacity.meterDimmed))
                } else {
                    Rectangle().fill(segment.color)
                }
            }
        }.contentShape(Rectangle()).help(segment.help)
        let label = segment.help.replacingOccurrences(of: " · ", with: ", ")
        if let open, let part = segment.part, part != .trash {
            Button { open(part) } label: { fill }.buttonStyle(.plain)
                .accessibilityLabel(label).accessibilityHint("Opens in the cleanup plan")
                .accessibilityIdentifier("meterSegment-" + segment.id)
        } else {
            fill.accessibilityElement().accessibilityLabel(label).accessibilityIdentifier("meterSegment-" + segment.id)
        }
    }
}

extension StorageBreakdown.Part {
    var title: String {
        switch self {
        case .category(let category): category.overviewTitle
        case .other: "Other reclaimable"
        case .trash: "In Trash"
        }
    }
    /// The category's badge colour; Other and the Trash have quieter meter tokens.
    var color: Color {
        switch self {
        case .category(let category): category.storageCategory.color
        case .other: CacheDropDesign.meterOther
        case .trash: CacheDropDesign.meterTrash
        }
    }
}

extension StorageBreakdown.Part {
    /// The categories a click opens in the Cleanup plan.
    var categories: [CatalogCategory] {
        switch self {
        case .category(let category): [category]
        case .other(let categories): categories
        case .trash: []
        }
    }
}

extension CatalogCleanupModel {
    /// The meter's segments for a capacity reading: Overview's categories, the Trash, and on Smart clean what it would free.
    func breakdown(available: Int64?, total: Int64?, trash: TrashContents?, highlightingSmartClean: Bool = false) -> StorageBreakdown? {
        guard let available, let total = CapacityMeter.validTotal(available: available, total: total), let overview else { return nil }
        return StorageBreakdown(used: total - available, total: total, overview: overview, trash: trash ?? .unknown,
                                highlighting: highlightingSmartClean ? smartCleanCandidates : nil)
    }
}
