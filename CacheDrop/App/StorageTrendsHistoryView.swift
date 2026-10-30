import SwiftUI
import Observation
import CacheDropCore

/// Storage trends (formerly What grew): compares the latest catalog scan of the known locations with the newest one about a day
/// older that isn't a rescan right after a cleanup (SPEC, #119, #126). Each catalog scan is recorded; nothing scans in the background.
@MainActor @Observable final class StorageTrendsHistoryModel {
    static let shared = StorageTrendsHistoryModel()
    private var archive: StorageTrendsHistoryStore?
    private var request = UUID()
    /// The latest catalog comparison; nil before the first catalog scan was recorded.
    private(set) var comparison: StorageTrendsComparison?
    private(set) var error: String?
    private(set) var loading = false
    var dimension = StorageTrendsDimension.category
    var coverageExpanded = false

    private func store() throws -> StorageTrendsHistoryStore {
        if let archive { return archive }
        var baselineAge = StorageTrendsHistoryStore.minimumBaselineAge
        #if DEBUG
        // UI tests can't wait a day between scans; a disposable test run may shorten the baseline age.
        if LocalStateLocation.isDisposableTest, let age = ProcessInfo.processInfo.environment["CACHEDROP_TEST_TRENDS_BASELINE_AGE"].flatMap(TimeInterval.init) { baselineAge = age }
        #endif
        let value = StorageTrendsHistoryStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Growth", isDirectory: true), minimumBaselineAge: baselineAge)
        archive = value; return value
    }

    func load() async {
        let current = UUID(); request = current; loading = true
        defer { if request == current { loading = false } }
        do {
            let store = try store()
            let latest = try await store.snapshots().last { $0.fingerprint.isCatalog }
            var value: StorageTrendsComparison?
            if let latest { value = try await store.comparison(id: latest.id) }
            guard request == current, !Task.isCancelled else { return }
            comparison = value; error = nil
        } catch {
            guard request == current, !Task.isCancelled else { return }
            comparison = nil; self.error = "CacheDrop couldn’t read its saved scans, so it can’t show trends."
        }
    }

    /// Before a catalog scan: captures the history's epoch and the home folder's identity.
    func beginCatalog(home: URL, exclusionFingerprint: String) async -> StorageTrendsScanToken? {
        do { return try await StorageTrendsScanRecorder(store: store()).beginCatalog(home: home, exclusionFingerprint: exclusionFingerprint) }
        catch { self.error = "CacheDrop couldn’t check your home folder, so this scan isn’t saved for Storage trends."; return nil }
    }

    /// After a completed catalog scan: records it per category and location and shows the new comparison.
    /// `afterCleanup` marks the rescan right after a cleanup, which never becomes a baseline.
    func completeCatalog(_ discovery: CatalogDiscovery, catalog: Catalog, fullDiskAccess: FullDiskAccessStatus, token: StorageTrendsScanToken?, afterCleanup: Bool = false) async {
        guard let token else { return }
        request = UUID()
        do {
            let result = try await StorageTrendsScanRecorder(store: store()).completeCatalog(discovery, catalog: catalog, fullDiskAccess: fullDiskAccess, token: token,
                                                                                 afterCleanup: afterCleanup)
            if result.state != .unknown { comparison = result }
            error = nil
        } catch { self.error = "This scan couldn’t be saved for Storage trends. Its results are still shown." }
    }

    func invalidateCoverage() async throws { try await store().invalidateCoverage() }
    func clearCompletedHistory() async throws { request = UUID(); try await store().clearCompletedHistory(); comparison = nil }
    func resetHistory() async throws { request = UUID(); try await store().resetHistory(); comparison = nil }
}

enum StorageTrendsPresentation {
    static func signed(_ bytes: Int64) -> String {
        (bytes > 0 ? "+" : bytes < 0 ? "−" : "") + SizeFormatter.text(bytes == .min ? .max : abs(bytes))
    }
    /// A category group's title, as in Overview.
    static func categoryTitle(_ category: CatalogCategory?) -> String { category?.overviewTitle ?? "Other" }
    /// The title mid-sentence: only its first letter lowered, so "Downloaded iCloud files" keeps its "iCloud".
    static func inSentence(_ category: CatalogCategory?) -> String { let title = categoryTitle(category); return title.prefix(1).lowercased() + title.dropFirst() }
    static func storageCategory(_ category: CatalogCategory?) -> StorageCategory { category?.storageCategory ?? .managed }
    static func coverage(_ change: StorageTrendsCoverageChange) -> String {
        switch change.kind {
        case .newlyReadable: change.label + " can now be read, so its size isn’t counted as growth."
        case .newlyUnreadable: change.label + " couldn’t be read this time, so its size isn’t counted."
        case .newlyScanned: change.label + " is scanned for the first time, so its size isn’t counted as growth."
        case .noLongerScanned: change.label + " wasn’t scanned this time, so its size isn’t counted."
        case .checkedDifferently: change.label + " is checked differently now, so its size isn’t counted."
        }
    }
    static func baseline(_ state: StorageTrendsComparisonState) -> String {
        switch state {
        case .clearedBaseline: "History was cleared. " + checkBack
        case .missingBaseline: "The earlier scan is no longer kept. " + checkBack
        case .coverageChanged: "What CacheDrop scans changed, such as Protected items, so trends start again from this scan. " + checkBack
        default: checkBack
        }
    }
    static let checkBack = "Check back tomorrow to see trends."
    static let retention = "History is stored on this Mac: sizes per category and location only, at most \(StorageTrendsRetention().baselines) scans over \(StorageTrendsRetention().days) days, "
        + "and no more than \(SizeFormatter.text(Int64(StorageTrendsRetention().bytes)))."
}

/// A growth row as in the prototype: name, what it is, a bar relative to the largest change, and the signed change.
struct StorageTrendsChangeRow: View {
    let label: String
    var detail: String? = nil
    let delta: Int64
    let maximum: Int64
    var body: some View {
        HStack(alignment: .center, spacing: CacheDropDesign.Space.lg) {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text(label).font(CacheDropDesign.TypeStyle.rowTitle).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(CacheDropDesign.capacityTrack)
                Capsule().fill(delta > 0 ? CacheDropDesign.purple : CacheDropDesign.teal)
                    .frame(width: geometry.size.width * min(1, Double(abs(delta)) / Double(max(1, maximum))))
            }.frame(height: CacheDropDesign.Size.meterCompact).frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(StorageTrendsPresentation.signed(delta)).monospacedDigit().fixedSize()
        }.padding(.vertical, CacheDropDesign.Space.sm).accessibilityElement(children: .combine)
    }
}

struct StorageTrendsHistoryView: View {
    @Bindable var model: StorageTrendsHistoryModel
    let catalog: CatalogCleanupModel
    /// The empty state's Scan now (#321): the same scan as the bar's Scan again.
    var scanNow: () -> Void = {}
    /// The growth card's Review link (#461): where the category that grew most can be cleaned, named in full for VoiceOver.
    var reviewTitle = "Review plan"
    var review: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            if let error = model.error, model.comparison == nil {
                PageHeader(title: "Storage trends")
                HistoryStoreFailure(message: error, retryTitle: "Try again") { Task { await model.load() } }
            } else if let comparison = model.comparison, let current = comparison.current {
                if comparison.state == .compared, let from = comparison.from {
                    // A rescan dims the last comparison until it ends (#308).
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) { compared(comparison, from: from, to: current.observedAt) }
                        .waitingForScan(catalog.isScanning)
                } else {
                    PageHeader(title: "Storage trends", subtitle: "What grew or shrank between two scans.")
                    EmptyState(title: "No trends yet", detail: StorageTrendsPresentation.baseline(comparison.state),
                               symbol: "chart.line.uptrend.xyaxis", identifier: "growthBaselineRecorded")
                }
            } else if model.loading || catalog.isScanning {
                // Nothing known yet: skeleton rows, never a blank page (#308).
                PageHeader(title: "Storage trends", subtitle: "What grew or shrank between two scans.")
                SkeletonRows(.line, identifier: "growthSkeleton")
            } else {
                PageHeader(title: "Storage trends", subtitle: "What grew or shrank between two scans.")
                EmptyState(title: "No scans yet", detail: "Scan now, then check back tomorrow to see trends.",
                           symbol: "chart.line.uptrend.xyaxis", action: EmptyStateAction("Scan now", perform: scanNow), identifier: "growthEmpty")
            }
            if let error = model.error, model.comparison != nil { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            Text(StorageTrendsPresentation.retention).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.task { await model.load() }
    }

    @ViewBuilder private func compared(_ comparison: StorageTrendsComparison, from: Date, to: Date) -> some View {
        let days = max(1, Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0)
        PageHeader(title: "Storage trends", subtitle: "What grew or shrank since " + from.formatted(date: .long, time: .omitted) + ".")
        HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.sm) {
            Text(StorageTrendsPresentation.signed(comparison.logicalDelta ?? 0)).font(CacheDropDesign.TypeStyle.page).monospacedDigit().accessibilityIdentifier("growthNetChange")
            Text("net growth · " + (days == 1 ? "past day" : "past \(days) days")).foregroundStyle(.secondary)
        }
        Picker("Show growth by", selection: $model.dimension) {
            Text("Categories").tag(StorageTrendsDimension.category)
            Text("Locations").tag(StorageTrendsDimension.location)
        }.pickerStyle(.segmented).fixedSize().accessibilityIdentifier("growthDimension")
        let rows = comparison.groups.filter { $0.dimension == model.dimension && $0.logicalDelta != 0 }
            .sorted { abs($0.logicalDelta) == abs($1.logicalDelta) ? $0.id < $1.id : abs($0.logicalDelta) > abs($1.logicalDelta) }
        if rows.isEmpty {
            StatusRow(text: "No size changes between these scans.", symbol: "equal.circle")
        } else {
            let maximum = rows.map { abs($0.logicalDelta) }.max() ?? 1
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { change in
                    StorageTrendsChangeRow(label: label(change), detail: detail(change, in: comparison), delta: change.logicalDelta, maximum: maximum)
                    Divider()
                }
            }
        }
        if let top = comparison.mostGrowth {
            SummarySurface {
                // The action belongs to the card, so it's a link in it, not a bar button (Decision 65 rule 3, #461).
                HStack(alignment: .center, spacing: CacheDropDesign.Space.md) {
                    CategoryBadge(category: StorageTrendsPresentation.storageCategory(top.category))
                    Text("Most growth is in " + StorageTrendsPresentation.inSentence(top.category)).font(CacheDropDesign.TypeStyle.rowTitle)
                    Spacer(minLength: CacheDropDesign.Space.md)
                    Button("Review", action: review).buttonStyle(.link).help(reviewTitle)
                        .accessibilityLabel(reviewTitle).accessibilityIdentifier("growthReviewOptions")
                }
            }
        }
        if !comparison.coverageChanges.isEmpty {
            DisclosureGroup("Not counted as growth: \(comparison.coverageChanges.count) \(comparison.coverageChanges.count == 1 ? "location" : "locations")", isExpanded: $model.coverageExpanded) {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    ForEach(comparison.coverageChanges) { change in
                        StatusRow(text: StorageTrendsPresentation.coverage(change), symbol: "eye.slash", role: .caution)
                    }
                }.padding(.top, CacheDropDesign.Space.sm)
            }.accessibilityIdentifier("growthCoverageChanges")
        }
    }

    private func label(_ change: StorageTrendsChange) -> String {
        change.dimension == .category ? StorageTrendsPresentation.categoryTitle(change.category) : change.label
    }
    /// A category's changed rules (as Overview names them), or the rule a location belongs to.
    private func detail(_ change: StorageTrendsChange, in comparison: StorageTrendsComparison) -> String? {
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
struct StorageTrendsGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
            Text("Synthetic growth examples · Inert, no scans or archive access").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            StorageTrendsChangeRow(label: "Downloaded iCloud files", detail: "iCloud Drive local copies", delta: 14_200_000_000, maximum: 14_200_000_000)
            StorageTrendsChangeRow(label: "Developer caches and build files", detail: "Xcode build data", delta: 6_700_000_000, maximum: 14_200_000_000)
            StorageTrendsChangeRow(label: "Browser caches", detail: "Chrome cache", delta: -1_000_000_000, maximum: 14_200_000_000)
            StatusRow(text: "~/Library/Safari can now be read, so its size isn’t counted as growth.", symbol: "eye.slash", role: .caution)
        }
    }
}
#endif
