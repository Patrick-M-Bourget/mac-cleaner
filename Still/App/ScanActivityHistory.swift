import SwiftUI
import Observation
import StillCore

@MainActor @Observable final class ScanActivityHistory {
    static let shared = ScanActivityHistory()
    var records: [ScanActivity]?
    var loadError: String?
    var recordingWarning: String?
    private var archive: GrowthHistoryStore?
    func store() throws -> GrowthHistoryStore {
        if let archive { return archive }
        let value = GrowthHistoryStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Growth", isDirectory: true))
        archive = value; return value
    }
    func begin() async -> UUID? {
        do { return try await store().recordingEpoch() }
        catch { recordingWarning = "This scan could not be saved to History. Current results and choices remain available."; return nil }
    }
    func record(_ activity: ScanActivity, epoch: UUID?) async {
        guard let epoch else { return }
        do {
            let saved = try await store().recordActivity(activity, expectedEpoch: epoch)
            if saved { recordingWarning = nil; await load(maintain: false) }
        } catch { recordingWarning = "This scan could not be saved to History. Current results and choices remain available." }
    }
    func load(maintain: Bool = true) async {
        do { records = try await HistoryLoadCoordinator.load(lifecycle: AppLifecycleController.shared) { mayMaintain in
                try await self.store().activities(maintain: maintain && mayMaintain)
            }; loadError = nil }
        catch { records = nil; loadError = "Scan history is unavailable. Recorded scan activity could not be read." }
    }
}

struct ScanActivitySummary: View {
    let activity: ScanActivity
    @Binding var expanded: Bool
    var showGrowth: ((UUID) -> Void)? = nil
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                Label(title, systemImage: "viewfinder").font(StillDesign.TypeStyle.section)
                Text(activity.completedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text("Requested locations: \(activity.locations.count)").font(.caption).foregroundStyle(.secondary)
                Text(activity.locations.map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", "))
                DisclosureGroup("Scan details", isExpanded: $expanded) {
                    ForEach(activity.locations) { location in
                        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                            Text(location.path).textSelection(.enabled)
                            Text(location.outcome.map { $0 == .complete ? "Observed included coverage" : $0.rawValue.capitalized + " · Coverage incomplete" } ?? "Not attempted").font(.callout)
                            if let time = location.observedAt { Text("Observed " + time.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                            if let count = location.entryCount { Text("Observed entries: \(count)").font(.caption) }
                            else { Text("No measurements available").font(.caption).foregroundStyle(.secondary) }
                            Text("Complete scope logical size: " + bytes(location.logicalBytes)).font(.callout)
                            Text("Complete scope allocated size: " + bytes(location.allocatedBytes)).font(.callout)
                            if location.logicalBytes == nil, let known = location.knownLogicalBytes { Text("Known observed logical subtotal: " + bytes(known) + " · Remaining bytes unknown").font(.caption) }
                            ForEach(location.reasons.keys.sorted(), id: \.self) { reason in
                                Text(reasonLabel(reason) + ": " + String(location.reasons[reason] ?? 0)).font(.caption).foregroundStyle(.secondary)
                            }
                            if location.outcome == .complete, let baseline = location.baselineID, let showGrowth {
                                Button("See what grew") { showGrowth(baseline) }
                            }
                        }.padding(.leading, StillDesign.Space.xl)
                    }
                }.padding(.leading, StillDesign.Space.xl)
                Text("Recorded observations, not reclaimable or released space.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var title: String {
        switch activity.outcome { case .complete: "Completed scan"; case .partial: "Partial scan"; case .stopped: "Stopped scan"; case .failed: "Failed scan" }
    }
    private func reasonLabel(_ reason: String) -> String {
        switch reason { case "customExcludedBoundary": "Custom-excluded boundaries"; case "unmeasuredContents": "Unmeasured package or other entries"; default: reason }
    }
    private func bytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown" }
}

struct HistoryActivityFilterControl: View {
    @Binding var selection: HistoryActivityFilter
    var body: some View {
        Picker("Activity", selection: $selection) {
            ForEach(HistoryActivityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("History activity filter")
    }
}

/// Process-only operation context. Only its finalized aggregate summary reaches the archive.
@MainActor final class ActiveScanActivity {
    let id = UUID()
    let startedAt = Date()
    let roots: [URL]
    let epoch: UUID?
    private var locations: [String: ScanActivityLocation] = [:]
    init(roots: [URL], epoch: UUID?) { self.roots = roots; self.epoch = epoch }
    func observe(_ scan: ScanResult, baselineID: UUID? = nil) {
        let failedReasons: Set<String> = ["accessDenied", "accessRevoked", "locationUnavailable", "readFailed", "exclusionUnavailable"]
        if scan.observations.isEmpty, scan.issues.contains(where: { $0.url.standardizedFileURL == scan.scope.standardizedFileURL && failedReasons.contains($0.reason.rawValue) }) {
            locations[scan.scope.standardizedFileURL.path] = ScanActivityLocation(path: scan.scope.standardizedFileURL.path, observedAt: scan.observedAt, outcome: .failed, reasons: Dictionary(scan.issues.map { ($0.reason.rawValue, 1) }, uniquingKeysWith: +))
        } else { locations[scan.scope.standardizedFileURL.path] = ScanActivityLocation(scan: scan, baselineID: baselineID) }
    }
    func failed(_ root: URL) { locations[root.standardizedFileURL.path] = ScanActivityLocation(path: root.standardizedFileURL.path, observedAt: Date(), outcome: .failed, reasons: ["readFailed": 1]) }
    func stopped(_ root: URL?, progress: ScanProgress?) {
        guard let root, locations[root.standardizedFileURL.path] == nil else { return }
        locations[root.standardizedFileURL.path] = ScanActivityLocation(path: root.standardizedFileURL.path, observedAt: Date(), outcome: .stopped, entryCount: progress?.visitedEntries, knownLogicalBytes: progress?.knownLogicalSubtotal)
    }
    func summary(stopped: Bool = false) -> ScanActivity {
        let values = roots.map { locations[$0.standardizedFileURL.path] ?? ScanActivityLocation(path: $0.standardizedFileURL.path) }
        let outcome: ScanActivityOutcome
        if stopped { outcome = .stopped }
        else if values.allSatisfy({ $0.outcome == .complete }) { outcome = .complete }
        else if values.allSatisfy({ $0.outcome == .failed || $0.outcome == nil }) { outcome = .failed }
        else { outcome = .partial }
        return ScanActivity(id: id, startedAt: startedAt, completedAt: Date(), outcome: outcome, locations: values)
    }
}

struct ScanHistoryRecordingNotice: View {
    @Bindable private var history = ScanActivityHistory.shared
    var body: some View {
        if let warning = history.recordingWarning {
            StatusRow(text: warning, symbol: "exclamationmark.triangle", role: .caution)
        }
    }
}
