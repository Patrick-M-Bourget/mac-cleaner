import SwiftUI
import Observation
import StillCore

@MainActor @Observable final class ScanActivityHistory {
    static let shared = ScanActivityHistory()
    var records: [ScanActivity]?
    var loadError: String?
    var recordingWarning: String?
    var isLoading = false
    private var loadRequest = UUID()
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
        let request = UUID(); loadRequest = request; isLoading = true
        defer { if loadRequest == request { isLoading = false } }
        do {
            let value = try await HistoryLoadCoordinator.load(lifecycle: AppLifecycleController.shared) { mayMaintain in
                try await self.store().activities(maintain: maintain && mayMaintain)
            }
            guard loadRequest == request, !Task.isCancelled else { return }
            records = value; loadError = nil
        } catch {
            guard loadRequest == request, !Task.isCancelled else { return }
            records = nil; loadError = "Scan history is unavailable. Recorded scan activity could not be read."
        }
    }
}

struct ScanActivitySummary: View {
    let activity: ScanActivity
    @Binding var expanded: Bool
    var showGrowth: ((UUID) -> Void)? = nil
    var exampleIdentifier = ""
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                Label(title, systemImage: "viewfinder").font(StillDesign.TypeStyle.section)
                Text(activity.completedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text("Requested locations: \(activity.locations.count)").font(.caption).foregroundStyle(.secondary)
                Text(locationSummary).lineLimit(2).truncationMode(.middle)
                    .help(activity.locations.map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", "))
                DisclosureGroup("Scan details", isExpanded: $expanded) {
                    ForEach(activity.locations) { location in
                        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                            Text(location.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).help(location.path)
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
                        }.padding(.leading, StillDesign.Space.xl).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, StillDesign.Space.xl)
                    .accessibilityIdentifier("scanActivityDetails:" + activity.id.uuidString)
                Text("Recorded observations, not reclaimable or released space.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier(exampleIdentifier)
            }
        }
    }
    private var locationSummary: String {
        let labels = activity.locations.prefix(2).map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", ")
        return activity.locations.count > 2 ? labels + " and \(activity.locations.count - 2) more" : labels
    }
    private var title: String {
        switch activity.outcome { case .complete: "Completed scan"; case .partial: "Partial scan"; case .stopped: "Stopped scan"; case .failed: "Failed scan" }
    }
    private func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "excludedScope": "Excluded scopes"
        case "exclusionUnavailable": "Exclusion checks unavailable"
        case "directoryChanged": "Directory changed during scanning"
        case "timeLimit": "Scan time limit reached"
        case "entryLimit": "Entry limit reached"
        case "issueLimit": "Coverage issue limit reached"
        case "depthLimit": "Folder depth limit reached"
        case "readFailed": "Unreadable locations"
        case "metadataUnavailable": "Metadata unavailable"
        case "differentVolume": "Other volumes not inspected"
        case "accessDenied": "Access denied"
        case "accessRevoked": "Access changed during scanning"
        case "locationUnavailable": "Location unavailable"
        case "customExcludedBoundary": "Custom-excluded boundaries"
        case "unmeasuredContents": "Unmeasured package or other entries"
        default: "Coverage issues"
        }
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
            ScanHistoryRecordingFeedback(message: warning)
        }
    }
}

struct ScanHistoryRecordingFeedback: View {
    let message: String
    var body: some View { StatusRow(text: message, symbol: "exclamationmark.triangle", role: .caution) }
}
struct HistoryStoreFailure: View {
    let message, retryTitle: String
    var enabled = true
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            StatusRow(text: message, symbol: "exclamationmark.triangle", role: .caution)
            Button(retryTitle, action: retry).disabled(!enabled)
        }
    }
}
struct HistoryActivityUnavailableState: View {
    var body: some View {
        EmptyState(title: "History unavailable", detail: "Some recorded activity could not be read. Trying again reloads records only; it does not scan or clean files.", symbol: "exclamationmark.triangle")
    }
}
struct HistoryActivityEmptyState: View {
    let filter: HistoryActivityFilter
    var goOverview: () -> Void
    var viewPlan: () -> Void
    private var title: String {
        switch filter { case .all: "No retained history."; case .scans: "No recorded scans."; case .cleanups: "No recorded cleanup runs." }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            EmptyState(title: title, detail: "History retains up to 90 days within its record budgets. Older or cleared records may no longer appear. Nothing is selected or retried here.", symbol: "clock")
            HStack {
                if filter != .cleanups { Button("Go to Overview", action: goOverview) }
                if filter != .scans { Button("View cleanup plan", action: viewPlan) }
            }
        }
    }
}
struct HistoryRetentionNote: View {
    var body: some View {
        Text("Scan activity and enabled growth aggregates share a 250 MB archive budget and 90-day retention; at most 30 growth baselines are retained, without a 30-scan limit. Completed cleanup records have a separate 250 MB payload budget and 90-day retention. Protected recovery facts are exempt. Trash contents remain until you empty Trash in Finder.").font(.caption).foregroundStyle(.secondary)
    }
}

#if DEBUG
private struct HistoryGalleryCase: Identifiable {
    let id, title: String
    let activity: ScanActivity
}
struct HistoryActivityGalleryExamples: View {
    private let date = Date(timeIntervalSince1970: 1_792_000_000)
    private func activity(_ outcome: ScanActivityOutcome, _ locations: [ScanActivityLocation]) -> ScanActivity {
        ScanActivity(startedAt: date.addingTimeInterval(-12), completedAt: date, outcome: outcome, locations: locations)
    }
    private var cases: [HistoryGalleryCase] { [
        .init(id: "complete", title: "Complete observation", activity: activity(.complete, [.init(path: "/Example/Complete Downloads", observedAt: date, outcome: .complete, entryCount: 6, logicalBytes: 4_100_000, allocatedBytes: 4_200_000, knownLogicalBytes: 4_100_000, baselineID: UUID())])),
        .init(id: "partial", title: "Partial coverage", activity: activity(.partial, [.init(path: "/Example/Partial coverage", observedAt: date, outcome: .partial, entryCount: 9, knownLogicalBytes: 512, reasons: ["directoryChanged": 1, "metadataUnavailable": 2])])),
        .init(id: "stopped", title: "Stopped with an unattempted location", activity: activity(.stopped, [.init(path: "/Example/Stopped location", observedAt: date, outcome: .stopped, entryCount: 3, knownLogicalBytes: 32), .init(path: "/Example/Not attempted")])),
        .init(id: "failed", title: "Failed without measurements", activity: activity(.failed, [.init(path: "/Example/Unavailable", observedAt: date, outcome: .failed, reasons: ["accessDenied": 1])])),
        .init(id: "multi", title: "Same-named recorded roots", activity: activity(.complete, [.init(path: "/Example/Work/Documents", observedAt: date, outcome: .complete, entryCount: 2, logicalBytes: 12, allocatedBytes: 4096, knownLogicalBytes: 12), .init(path: "/Example/Personal/Documents", observedAt: date, outcome: .complete, entryCount: 4, logicalBytes: 22, allocatedBytes: 4096, knownLogicalBytes: 22)])),
        .init(id: "unknown", title: "Unmeasured and excluded contents", activity: activity(.complete, [.init(path: "/Example/Packages and excluded locations/" + (1...9).map { "Long recorded folder component " + String($0) + " with readable historical identity" }.joined(separator: "/"), observedAt: date, outcome: .complete, entryCount: 5, knownLogicalBytes: 32, reasons: ["unmeasuredContents": 1, "customExcludedBoundary": 2])]))
    ] }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Text("Synthetic presentation only · Actions are inert; no scan, comparison or record write occurs.").font(.caption).foregroundStyle(.secondary)
            HistoryActivityFilterControl(selection: .constant(.all))
            ForEach(cases) { item in
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    heading(item.id, item.title)
                    ScanActivitySummary(activity: item.activity, expanded: .constant(true), showGrowth: { _ in }, exampleIdentifier: "historyGalleryEnd-" + item.id)
                }
            }
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                heading("unavailable", "Independent unavailable stores")
                HistoryStoreFailure(message: "Scan history is unavailable. Recorded scan activity could not be read.", retryTitle: "Try scan history again", retry: {})
                HistoryStoreFailure(message: "Cleanup history is unavailable. The local journal cannot be read. Clear and reset are unavailable; keep its recovery records.", retryTitle: "Try cleanup history again", retry: {})
                HistoryActivityUnavailableState()
                end("unavailable", "Each action reloads its own records only.")
            }
            ForEach(HistoryActivityFilter.allCases, id: \.self) { filter in
                let id = filter == .all ? "empty-all" : filter == .scans ? "empty-scans" : "empty-cleanups"
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    heading(id, filter.rawValue + " · No retained records")
                    HistoryActivityEmptyState(filter: filter, goOverview: {}, viewPlan: {})
                    if filter == .all { HistoryRetentionNote() }
                    end(id, "Retained records, not a lifetime activity count.")
                }
            }
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                heading("save-failed", "Unrecorded activity feedback")
                ScanHistoryRecordingFeedback(message: "This scan could not be saved to History. Current results and choices remain available.")
                end("save-failed", "Current findings remain usable.")
            }
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                heading("partial-clear", "Partial maintenance outcome")
                StatusRow(text: "Cleared 1 completed cleanup run. Scan activity and growth baseline clearing could not be confirmed. Recovery facts remain protected.", symbol: "info.circle")
                end("partial-clear", "Clear applies across all History filters.")
            }
        }
    }
    private func heading(_ id: String, _ title: String) -> some View { Text("Synthetic History · " + title).font(StillDesign.TypeStyle.section).accessibilityIdentifier("historyGalleryCase-" + id) }
    private func end(_ id: String, _ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("historyGalleryEnd-" + id) }
}
#endif
