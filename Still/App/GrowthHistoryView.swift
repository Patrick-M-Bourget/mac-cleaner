import SwiftUI
import Observation
import StillCore

@MainActor @Observable final class GrowthHistoryModel {
    static let shared = GrowthHistoryModel()
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--future-milestones") }
    var comparison: GrowthComparison?
    var snapshots: [GrowthSnapshot] = []
    var error: String?
    private var store: GrowthHistoryStore?
    private var recorder: GrowthScanRecorder?
    private var active: UUID?
    private var attempt = UUID()
    private func open() throws -> GrowthHistoryStore {
        if let store { return store }
        let value = GrowthHistoryStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Growth", isDirectory: true))
        store = value; recorder = GrowthScanRecorder(store: value); return value
    }
    func load() async {
        guard Self.enabled else { return }
        do { let value = try open(); if comparison == nil { comparison = try await value.latest() }; snapshots = try await value.snapshots(); error = nil }
        catch { comparison = .unknown; self.error = "Comparison history is unavailable. No growth can be inferred from missing observations." }
    }
    func begin(_ scope: URL) async -> GrowthScanToken? {
        guard Self.enabled else { return nil }
        let request = UUID(); attempt = request
        do { _ = try open(); let token = try await recorder?.begin(scope: scope); guard attempt == request, !Task.isCancelled else { return nil }; active = token?.id; return token }
        catch { comparison = .unknown; self.error = "Scope or volume identity could not be verified. This scan cannot establish a comparison baseline."; return nil }
    }
    func complete(_ scan: ScanResult, token: GrowthScanToken?) async {
        guard let token, active == token.id, let recorder, !Task.isCancelled else { return }
        do { let result = try await recorder.complete(scan, token: token); guard active == token.id, !Task.isCancelled else { return }; active = nil; comparison = result; snapshots = try await open().snapshots(); error = nil }
        catch { comparison = .unknown; self.error = "This observation could not be saved. The previous completed baseline is retained." }
    }
    func clearCompletedHistory() async throws {
        attempt = UUID(); active = nil
        let value = try open()
        try await value.clearCompletedHistory()
        snapshots = []; comparison = try await value.latest(); active = nil
    }
    func resetHistory() async throws {
        attempt = UUID(); active = nil
        let value = try open()
        try await value.resetHistory()
        snapshots = []; comparison = try await value.latest(); error = nil
    }
    func cancelled() {
        attempt = UUID(); active = nil; comparison = .unknown
    }
    func select(_ id: UUID) async {
        do { comparison = try await open().comparison(id: id) }
        catch { comparison = .unknown; self.error = "The selected comparison is unavailable." }
    }
}

struct GrowthHistoryView: View {
    @Bindable var model: GrowthHistoryModel
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "What grew", subtitle: "Compare completed observations of the same scope. Changes do not identify which app or person wrote files.")
            if let error = model.error { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            if let comparison = model.comparison {
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
            if !model.snapshots.isEmpty {
                DisclosureGroup("Completed observations") {
                    ForEach(model.snapshots.reversed()) { snapshot in
                        Button(snapshot.scopeLabel + " · " + snapshot.observedAt.formatted(date: .abbreviated, time: .standard)) { Task { await model.select(snapshot.id) } }
                    }
                }
            }
            DisclosureGroup("Measurement details") {
                Text("Linked files count once, under their first observed path. Alias changes can shift folder or category totals without changing net size. Comparisons describe observed logical size, not exclusive disk allocation or writer activity.").font(.caption).foregroundStyle(.secondary)
            }
            StatusRow(text: "History keeps at most 90 days, 30 completed baselines and 250 MB of aggregates. File contents and per-file records are not stored. Folder names remain sensitive local metadata. Logical change is not reclaimable space.", symbol: "lock")
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
