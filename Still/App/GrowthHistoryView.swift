import SwiftUI
import Observation
import StillCore

@MainActor @Observable final class GrowthHistoryModel {
    static let shared = GrowthHistoryModel()
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--future-milestones") }
    private var session: GrowthHistorySession?
    private var archive: GrowthHistoryStore?
    private var openingError: String?
    private var requestedObservation: UUID?
    private var historicalComparison: GrowthComparison?
    private var historicalError: String?
    var historicalBusy = false
    var historicalUnavailable: Bool { requestedObservation != nil && !historicalBusy && historicalComparison?.current?.id != requestedObservation }
    var isHistorical: Bool { requestedObservation != nil }
    var comparison: GrowthComparison? { isHistorical ? historicalComparison : session?.comparison }
    var snapshots: [GrowthSnapshot] { session?.snapshots ?? [] }
    var error: String? { isHistorical ? historicalError : openingError ?? session?.error }
    private func store() throws -> GrowthHistoryStore {
        if let archive { return archive }
        let value = GrowthHistoryStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Growth", isDirectory: true))
        archive = value; return value
    }
    private func open() throws -> GrowthHistorySession {
        if let session { return session }
        let value = GrowthHistorySession(store: try store())
        session = value; openingError = nil; return value
    }
    func load() async {
        guard Self.enabled else { return }
        if let requestedObservation {
            historicalBusy = true
            defer { if self.requestedObservation == requestedObservation { historicalBusy = false } }
            do {
                let value = try await store().comparison(id: requestedObservation)
                guard self.requestedObservation == requestedObservation, !Task.isCancelled else { return }
                historicalComparison = value; historicalError = nil
            } catch {
                guard self.requestedObservation == requestedObservation, !Task.isCancelled else { return }
                historicalComparison = nil; historicalError = "The recorded comparison could not be read. No other observation was selected."
            }
            return
        }
        do { await (try open()).load() }
        catch { openingError = "Comparison history is unavailable. No growth can be inferred from missing observations." }
    }
    func requestHistorical(_ id: UUID) {
        requestedObservation = id; historicalComparison = nil; historicalError = nil; historicalBusy = true
    }
    func endHistoricalRequest() { requestedObservation = nil; historicalComparison = nil; historicalError = nil; historicalBusy = false }
    func retainedBaseline(for scan: ScanResult) -> UUID? {
        guard let current = session?.comparison?.current, current.observedAt == scan.observedAt,
              current.scopeLabel == scan.scope.lastPathComponent,
              snapshots.contains(where: { $0.id == current.id }) else { return nil }
        return current.id
    }
    func begin(_ scope: URL, exclusionFingerprint: String = "none") async -> GrowthScanToken? {
        guard Self.enabled else { return nil }
        do { return await (try open()).begin(scope, exclusionFingerprint: exclusionFingerprint) }
        catch { openingError = "Scope or volume identity could not be verified. This scan cannot establish a comparison baseline."; return nil }
    }
    func complete(_ scan: ScanResult, token: GrowthScanToken?) async { await session?.complete(scan, token: token) }
    func invalidateCoverage() async throws {
        guard Self.enabled else { return }
        try await open().invalidateCoverage()
    }
    func clearCompletedHistory() async throws { try await open().clearCompletedHistory() }
    func resetHistory() async throws { try await open().resetHistory() }
    func cancelled() { session?.cancelled() }
    func select(_ id: UUID) async { await session?.select(id) }
}

struct GrowthHistoryView: View {
    @Bindable var model: GrowthHistoryModel
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "What grew", subtitle: "Compare completed observations of the same scope. Changes do not identify which app or person wrote files.")
            if AppLifecycleController.shared.inspection.isScanning {
                let inspection = AppLifecycleController.shared.inspection
                ScanProgressSummary(inspectedEntries: inspection.progress?.visitedEntries ?? 0,
                    logicalSubtotal: "Unknown",
                    recentNames: [], phaseMessage: "Scanning " + (inspection.scope?.lastPathComponent ?? "selected location") + "…")
            }
            if model.comparison?.current == nil && model.error == nil {
                EmptyState(title: "Establish a baseline", detail: "Scan a location now, then scan it again later to compare two completed observations. Nothing scans automatically.", symbol: "chart.line.uptrend.xyaxis")
            }
            if let error = model.error { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            if model.historicalBusy { ProgressView("Reading recorded comparison…") }
            if model.historicalUnavailable {
                EmptyState(title: "Comparison unavailable for this recorded observation.", detail: "The exact linked baseline is missing, expired or unreadable. No other observation was substituted, and no scan was started.", symbol: "clock.badge.exclamationmark")
            }
            if let comparison = model.comparison, !model.historicalUnavailable {
                StatusRow(text: message(comparison.state), symbol: comparison.state == .compared ? "chart.line.uptrend.xyaxis" : "info.circle", role: comparison.state == .coverageChanged || comparison.state == .unknown ? .caution : .neutral)
                if let current = comparison.current {
                    SummarySurface {
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            Text("Scope: " + current.scopeLabel).font(StillDesign.TypeStyle.section)
                            Text("Observed " + current.observedAt.formatted(date: .abbreviated, time: .shortened))
                            Text("Coverage: complete logical-size inventory · folder and category aggregates").font(.caption).foregroundStyle(.secondary)
                            if let start = comparison.from { Text("Interval: " + start.formatted(date: .abbreviated, time: .standard) + " → " + current.observedAt.formatted(date: .abbreviated, time: .standard)).font(.caption) }
                            if let delta = comparison.logicalDelta { Text(signed(delta) + " net logical change").font(StillDesign.TypeStyle.value).accessibilityIdentifier("growthNetChange") }
                        }
                    }
                }
                if comparison.state == .compared {
                    ForEach([GrowthDimension.folder, .category], id: \.rawValue) { dimension in
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            Text(dimension == .folder ? "Folders" : "Categories").font(StillDesign.TypeStyle.section)
                            ForEach(comparison.groups.filter { $0.dimension == dimension }) { group in
                                SettingsRow(title: group.label, detail: "Observed net logical-size change") { Text(signed(group.logicalDelta)).monospacedDigit() }
                                Divider()
                            }
                        }
                    }
                }
            }
            if !model.isHistorical && !model.snapshots.isEmpty {
                DisclosureGroup("Completed observations") {
                    ForEach(model.snapshots.reversed()) { snapshot in
                        Button(snapshot.scopeLabel + " · " + snapshot.observedAt.formatted(date: .abbreviated, time: .standard)) { Task { await model.select(snapshot.id) } }
                    }
                }
            }
            DisclosureGroup("Measurement details") {
                Text("Linked files count once, under their first observed path. Alias changes can shift folder or category totals without changing net size. Comparisons describe observed logical size, not exclusive disk allocation or writer activity.").font(.caption).foregroundStyle(.secondary)
            }
            StatusRow(text: "Scan activity and enabled growth aggregates share 90-day retention and a 250 MB archive budget, with at most 30 growth baselines. File contents and scanned child-file catalogues are not stored. Recorded root paths and folder names remain sensitive local metadata. Logical change is not reclaimable space.", symbol: "lock")
        }.task { await model.load() }
    }
    private func signed(_ bytes: Int64) -> String { (bytes > 0 ? "+" : bytes < 0 ? "−" : "") + ByteCountFormatter.string(fromByteCount: abs(bytes), countStyle: .decimal) }
    private func message(_ state: GrowthComparisonState) -> String {
        switch state {
        case .firstBaseline: "First observation · complete one more compatible scan to see what grew."
        case .clearedBaseline: "History was cleared · complete two compatible observations to compare again."
        case .missingBaseline: "Previous baseline is no longer retained · growth is unknown until another compatible observation."
        case .coverageChanged: "Coverage changed · scope, root, volume, access, scan/exclusion rules or classification differ. This is not ordinary growth."
        case .unknown: "Growth unknown · this observation is incomplete, unmeasured or unavailable. The previous completed baseline is retained."
        case .compared: "Compatible completed observations · additions and removals are net changes across this interval."
        }
    }
}
