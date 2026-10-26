import SwiftUI
import Observation
import StillCore

/// What grew: compares the last two completed catalog scans of the known locations (SPEC, RESET Decision 12 revisited in #119).
/// Each catalog scan records a baseline; nothing scans in the background.
@MainActor @Observable final class GrowthHistoryModel {
    static let shared = GrowthHistoryModel()
    private var archive: GrowthHistoryStore?
    private var request = UUID()
    /// The latest catalog comparison; nil before the first catalog scan was recorded.
    private(set) var comparison: GrowthComparison?
    private(set) var error: String?
    private(set) var loading = false
    var dimension = GrowthDimension.category
    var coverageExpanded = false

    private func store() throws -> GrowthHistoryStore {
        if let archive { return archive }
        let value = GrowthHistoryStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Growth", isDirectory: true))
        archive = value; return value
    }

    func load() async {
        let current = UUID(); request = current; loading = true
        defer { if request == current { loading = false } }
        do {
            let store = try store()
            let latest = try await store.snapshots().last { $0.fingerprint.isCatalog }
            var value: GrowthComparison?
            if let latest { value = try await store.comparison(id: latest.id) }
            guard request == current, !Task.isCancelled else { return }
            comparison = value; error = nil
        } catch {
            guard request == current, !Task.isCancelled else { return }
            comparison = nil; self.error = "What grew history is unavailable. No growth can be inferred from missing scans."
        }
    }

    /// Before a catalog scan: captures the history's epoch and the home folder's identity.
    func beginCatalog(home: URL, exclusionFingerprint: String) async -> GrowthScanToken? {
        do { return try await GrowthScanRecorder(store: store()).beginCatalog(home: home, exclusionFingerprint: exclusionFingerprint) }
        catch { self.error = "The home folder’s identity couldn’t be checked, so this scan isn’t recorded in What grew."; return nil }
    }

    /// After a completed catalog scan: records it per category and location and shows the new comparison.
    func completeCatalog(_ discovery: CatalogDiscovery, catalog: Catalog, fullDiskAccess: FullDiskAccessStatus, token: GrowthScanToken?) async {
        guard let token else { return }
        request = UUID()
        do {
            let result = try await GrowthScanRecorder(store: store()).completeCatalog(discovery, catalog: catalog, fullDiskAccess: fullDiskAccess, token: token)
            if result.state != .unknown { comparison = result }
            error = nil
        } catch { self.error = "This scan couldn’t be saved to What grew. Current results are still usable." }
    }

    func invalidateCoverage() async throws { try await store().invalidateCoverage() }
    func clearCompletedHistory() async throws { request = UUID(); try await store().clearCompletedHistory(); comparison = nil }
    func resetHistory() async throws { request = UUID(); try await store().resetHistory(); comparison = nil }
}

enum GrowthPresentation {
    static func signed(_ bytes: Int64) -> String {
        (bytes > 0 ? "+" : bytes < 0 ? "−" : "") + ByteCountFormatter.string(fromByteCount: bytes == .min ? .max : abs(bytes), countStyle: .decimal)
    }
    /// A category group's title, as in Overview.
    static func categoryTitle(_ raw: String?) -> String { raw.flatMap(CatalogCategory.init(rawValue:))?.overviewTitle ?? "Other" }
    static func storageCategory(_ raw: String?) -> StorageCategory { raw.flatMap(CatalogCategory.init(rawValue:))?.storageCategory ?? .managed }
    static func coverage(_ change: GrowthCoverageChange) -> String {
        switch change.kind {
        case .newlyReadable: change.label + " can now be read, so its size isn’t counted as growth."
        case .newlyUnreadable: change.label + " couldn’t be read this time, so its size isn’t counted."
        case .newlyScanned: change.label + " is scanned for the first time; its size is the new baseline, not growth."
        case .noLongerScanned: change.label + " wasn’t scanned this time, so its size isn’t counted."
        }
    }
    static func baseline(_ state: GrowthComparisonState) -> String {
        switch state {
        case .clearedBaseline: "History was cleared. Scan again later to see what grew."
        case .missingBaseline: "The earlier scan is no longer kept. Scan again later to see what grew."
        case .coverageChanged: "Scan settings changed, such as exclusions, so this scan starts a new baseline. Scan again later to see what grew."
        default: "Scan again later to see what grew."
        }
    }
    static let retention = "History is stored on this Mac: sizes per category and location only, at most \(GrowthRetention().baselines) scans over \(GrowthRetention().days) days, "
        + "and no more than \(ByteCountFormatter.string(fromByteCount: Int64(GrowthRetention().bytes), countStyle: .decimal))."
}

/// A growth row as in the prototype: name, what it is, a bar relative to the largest change, and the signed change.
struct GrowthChangeRow: View {
    let label: String
    var detail: String? = nil
    let delta: Int64
    let maximum: Int64
    var body: some View {
        HStack(alignment: .center, spacing: StillDesign.Space.lg) {
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                Text(label).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(StillDesign.capacityTrack)
                Capsule().fill(delta > 0 ? StillDesign.purple : StillDesign.teal)
                    .frame(width: geometry.size.width * min(1, Double(abs(delta)) / Double(max(1, maximum))))
            }.frame(height: StillDesign.Size.meterCompact).frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(GrowthPresentation.signed(delta)).monospacedDigit().fixedSize()
        }.padding(.vertical, StillDesign.Space.sm).accessibilityElement(children: .combine)
    }
}

struct GrowthHistoryView: View {
    @Bindable var model: GrowthHistoryModel
    let catalog: CatalogCleanupModel
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            if let error = model.error, model.comparison == nil {
                PageHeader(title: "What grew")
                HistoryStoreFailure(message: error, retryTitle: "Try again") { Task { await model.load() } }
            } else if let comparison = model.comparison, let current = comparison.current {
                if comparison.state == .compared, let from = comparison.from {
                    compared(comparison, from: from, to: current.observedAt)
                } else {
                    PageHeader(title: "What grew", subtitle: "Changes in your known locations between two completed scans.")
                    EmptyState(title: "Baseline recorded", detail: "Recorded " + current.observedAt.formatted(date: .abbreviated, time: .shortened) + ". " + GrowthPresentation.baseline(comparison.state),
                               symbol: "chart.line.uptrend.xyaxis").accessibilityIdentifier("growthBaselineRecorded")
                }
            } else if !model.loading {
                PageHeader(title: "What grew", subtitle: "Changes in your known locations between two completed scans.")
                EmptyState(title: catalog.isScanning ? "Scanning known locations…" : "No scan recorded yet",
                           detail: "The first completed scan records a baseline. The next one shows what grew. Nothing scans in the background.", symbol: "chart.line.uptrend.xyaxis")
            }
            if let error = model.error, model.comparison != nil { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            StatusRow(text: GrowthPresentation.retention, symbol: "lock")
        }.task { await model.load() }
    }

    @ViewBuilder private func compared(_ comparison: GrowthComparison, from: Date, to: Date) -> some View {
        let days = max(1, Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0)
        HStack(alignment: .top) {
            PageHeader(title: "What grew", subtitle: "Changes in your known locations since " + from.formatted(date: .long, time: .omitted) + ".")
            Spacer(minLength: StillDesign.Space.md)
            Text(days == 1 ? "Past day" : "Past \(days) days").font(.caption).foregroundStyle(.secondary)
        }
        HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.sm) {
            Text(GrowthPresentation.signed(comparison.logicalDelta ?? 0)).font(StillDesign.TypeStyle.page).monospacedDigit().accessibilityIdentifier("growthNetChange")
            Text("net growth").foregroundStyle(.secondary)
        }
        Picker("Show growth by", selection: $model.dimension) {
            Text("Categories").tag(GrowthDimension.category)
            Text("Locations").tag(GrowthDimension.location)
        }.pickerStyle(.segmented).fixedSize().accessibilityIdentifier("growthDimension")
        let rows = comparison.groups.filter { $0.dimension == model.dimension && $0.logicalDelta != 0 }
            .sorted { abs($0.logicalDelta) == abs($1.logicalDelta) ? $0.id < $1.id : abs($0.logicalDelta) > abs($1.logicalDelta) }
        if rows.isEmpty {
            StatusRow(text: "No size changes between these scans.", symbol: "equal.circle")
        } else {
            let maximum = rows.map { abs($0.logicalDelta) }.max() ?? 1
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { change in
                    GrowthChangeRow(label: label(change), detail: detail(change, in: comparison), delta: change.logicalDelta, maximum: maximum)
                    Divider()
                }
            }
        }
        if let top = comparison.groups.filter({ $0.dimension == .category && $0.logicalDelta > 0 }).max(by: { $0.logicalDelta < $1.logicalDelta }) {
            SummarySurface {
                HStack(alignment: .top, spacing: StillDesign.Space.md) {
                    CategoryBadge(category: GrowthPresentation.storageCategory(top.category))
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text("Most growth is in " + GrowthPresentation.categoryTitle(top.category).lowercased() + ".").font(.body.weight(.medium))
                        Text("Review options shows what can be cleaned there now.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !comparison.coverageChanges.isEmpty {
            DisclosureGroup("Coverage changed for \(comparison.coverageChanges.count) \(comparison.coverageChanges.count == 1 ? "location" : "locations") · Not counted as growth", isExpanded: $model.coverageExpanded) {
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    ForEach(comparison.coverageChanges) { change in
                        StatusRow(text: GrowthPresentation.coverage(change), symbol: "eye.slash", role: .caution)
                    }
                }.padding(.top, StillDesign.Space.sm)
            }.accessibilityIdentifier("growthCoverageChanges")
        }
    }

    private func label(_ change: GrowthChange) -> String {
        change.dimension == .category ? GrowthPresentation.categoryTitle(change.category) : change.label
    }
    /// A category's changed rules (as Overview names them), or the rule a location belongs to.
    private func detail(_ change: GrowthChange, in comparison: GrowthComparison) -> String? {
        let catalog = catalog.catalog
        if change.dimension == .location { return change.ruleID.flatMap { catalog.rule($0)?.title } }
        let titles = comparison.groups.filter { $0.dimension == .location && $0.category == change.category && $0.logicalDelta != 0 }
            .sorted { abs($0.logicalDelta) > abs($1.logicalDelta) }.compactMap { $0.ruleID.flatMap { catalog.rule($0)?.title } }
        var unique: [String] = []
        for title in titles where !unique.contains(title) { unique.append(title) }
        return unique.isEmpty ? nil : unique.prefix(3).joined(separator: ", ") + (unique.count > 3 ? " and \(unique.count - 3) more" : "")
    }
}

#if DEBUG
struct GrowthGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            Text("Synthetic growth examples · Inert, no scans or archive access").font(.caption).foregroundStyle(.secondary)
            GrowthChangeRow(label: "Downloaded iCloud files", detail: "iCloud Drive local copies", delta: 14_200_000_000, maximum: 14_200_000_000)
            GrowthChangeRow(label: "Developer caches and build files", detail: "Xcode build data", delta: 6_700_000_000, maximum: 14_200_000_000)
            GrowthChangeRow(label: "Browser caches", detail: "Chrome cache", delta: -1_000_000_000, maximum: 14_200_000_000)
            StatusRow(text: "~/Library/Safari can now be read, so its size isn’t counted as growth.", symbol: "eye.slash", role: .caution)
        }
    }
}
#endif
