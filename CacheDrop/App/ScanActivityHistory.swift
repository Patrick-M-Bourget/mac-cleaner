import SwiftUI
import AppKit
import Observation
import CacheDropCore

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
        catch { recordingWarning = "This scan couldn’t be saved to History. Its results and your choices are still here."; return nil }
    }
    func record(_ activity: ScanActivity, epoch: UUID?) async {
        guard let epoch else { return }
        do {
            let saved = try await store().recordActivity(activity, expectedEpoch: epoch)
            if saved { recordingWarning = nil; await load(maintain: false) }
        } catch { recordingWarning = "This scan couldn’t be saved to History. Its results and your choices are still here." }
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
            records = nil; loadError = "CacheDrop couldn’t read its scan history."
        }
    }
}

/// One compact History row: symbol, title, date and size; details appear when the row is opened.
struct HistoryRow<Details: View>: View {
    let symbol: String
    let title: String
    let date: Date
    let size: String
    var sizeNote: String? = nil
    @Binding var expanded: Bool
    var identifier = ""
    @ViewBuilder var details: () -> Details
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: CacheDropDesign.Space.md) {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: CacheDropDesign.Size.rowIcon)
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                        Text(title).font(CacheDropDesign.TypeStyle.rowTitle).lineLimit(1).truncationMode(.middle)
                        Text(date.formatted(date: .abbreviated, time: .shortened)).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: CacheDropDesign.Space.xs) {
                        Text(size).monospacedDigit()
                        if let sizeNote { Text(sizeNote).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                    }
                    Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }.padding(.vertical, CacheDropDesign.Space.md).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier(identifier)
            if expanded {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm, content: details)
                    .padding(.leading, CacheDropDesign.Size.rowIcon + CacheDropDesign.Space.md).padding(.bottom, CacheDropDesign.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ScanActivitySummary: View {
    let activity: ScanActivity
    @Binding var expanded: Bool
    var exampleIdentifier = ""
    var body: some View {
        HistoryRow(symbol: "viewfinder", title: title + " · " + locationSummary, date: activity.completedAt, size: size, sizeNote: "Scanned",
                   expanded: $expanded, identifier: "scanActivity:" + activity.id.uuidString) {
            ForEach(activity.locations) { location in
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                    Text(URL(fileURLWithPath: location.path).lastPathComponent + " · " + PathDisplay.shortLocation(of: location.path))
                        .lineLimit(1).truncationMode(.middle).help(location.path)
                    Text(locationDetail(location)).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    if !location.reasons.isEmpty {
                        Text(location.reasons.keys.sorted().map { reasonLabel($0) + " (\(location.reasons[$0] ?? 0))" }.joined(separator: " · "))
                            .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.accessibilityElement(children: .combine)
            }
            Text("What the scan found, not space you can get back.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier(exampleIdentifier)
        }
    }
    private var size: String {
        guard let size = activity.observedSize else { return "Not measured" }
        return (size.complete ? "" : "At least ") + ByteCountFormatter.string(fromByteCount: size.bytes, countStyle: .decimal)
    }
    private func locationDetail(_ location: ScanActivityLocation) -> String {
        var parts = [location.outcome.map { $0 == .complete ? "Complete" : $0.rawValue.capitalized + " · Not fully read" } ?? "Not attempted"]
        if let count = location.entryCount { parts.append("\(count) entries") }
        // Sizes on disk, as the row's total and Overview show them (Decision 94).
        if let bytes = location.allocatedBytes { parts.append(format(bytes)) }
        else if let known = location.knownAllocatedBytes { parts.append("At least " + format(known)) }
        return parts.joined(separator: " · ")
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
        case "excludedScope": "Protected items"
        case "exclusionUnavailable": "Protected items unreadable"
        case "directoryChanged": "Folders changed during the scan"
        case "timeLimit": "Scan time limit reached"
        case "entryLimit": "Entry limit reached"
        case "issueLimit": "Too many unreadable items"
        case "depthLimit": "Folder depth limit reached"
        case "readFailed": "Unreadable locations"
        case "metadataUnavailable": "Some details couldn’t be read"
        case "differentVolume": "On another volume, not scanned"
        case "accessDenied": "Access denied"
        case "accessRevoked": "Access changed during scanning"
        case "locationUnavailable": "Location unavailable"
        case "customExcludedBoundary": "Inside Protected items"
        case "unmeasuredContents": "Packages not measured"
        default: "Couldn’t read everything"
        }
    }
    private func format(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
}

struct HistoryActivityFilterControl: View {
    @Binding var selection: HistoryActivityFilter
    var body: some View {
        Picker("Activity", selection: $selection) {
            ForEach(HistoryActivityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).labelsHidden().controlSize(.small).fixedSize().accessibilityIdentifier("History activity filter")
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
        locations[root.standardizedFileURL.path] = ScanActivityLocation(path: root.standardizedFileURL.path, observedAt: Date(), outcome: .stopped, entryCount: progress?.visitedEntries, knownLogicalBytes: progress?.knownLogicalSubtotal,
                                                                       knownAllocatedBytes: progress?.knownAllocatedSubtotal)
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
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            StatusRow(text: message, symbol: "exclamationmark.triangle", role: .caution)
            Button(retryTitle, action: retry).disabled(!enabled)
        }
    }
}
struct HistoryActivityUnavailableState: View {
    var body: some View {
        EmptyState(title: "History unavailable", detail: "CacheDrop couldn’t read some of its history. Trying again only reads it again; it doesn’t scan or clean.", symbol: "exclamationmark.triangle")
    }
}
/// History with nothing to show (#321): one empty state whose one action is Go to Overview.
struct HistoryActivityEmptyState: View {
    let filter: HistoryActivityFilter
    var goOverview: () -> Void
    private var title: String {
        switch filter { case .all: "No activity yet"; case .scans: "No scans yet"; case .cleanups: "No cleanups yet" }
    }
    var body: some View {
        EmptyState(title: title, detail: "Scans and cleanups appear here when they finish.", symbol: "clock",
                   action: EmptyStateAction("Go to Overview", perform: goOverview), identifier: "historyEmpty")
    }
}
struct HistoryRetentionNote: View {
    var body: some View {
        Text("History is kept on this Mac for up to 90 days. An interrupted cleanup stays until you review it.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            Text("Synthetic presentation only · Actions are inert; no scan, comparison or record write occurs.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            HistoryActivityFilterControl(selection: .constant(.all))
            ForEach(cases) { item in
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    heading(item.id, item.title)
                    ScanActivitySummary(activity: item.activity, expanded: .constant(true), exampleIdentifier: "historyGalleryEnd-" + item.id)
                }
            }
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                heading("unavailable", "Independent unavailable stores")
                HistoryStoreFailure(message: "CacheDrop couldn’t read its scan history.", retryTitle: "Try scan history again", retry: {})
                HistoryStoreFailure(message: "CacheDrop couldn’t read its cleanup history. Clear and Reset are off until it can.", retryTitle: "Try cleanup history again", retry: {})
                HistoryActivityUnavailableState()
                end("unavailable", "Each action reloads its own records only.")
            }
            ForEach(HistoryActivityFilter.allCases, id: \.self) { filter in
                let id = filter == .all ? "empty-all" : filter == .scans ? "empty-scans" : "empty-cleanups"
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    heading(id, filter.rawValue + " · No retained records")
                    HistoryActivityEmptyState(filter: filter, goOverview: {})
                    if filter == .all { HistoryRetentionNote() }
                    end(id, "Retained records, not a lifetime activity count.")
                }
            }
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                heading("save-failed", "Unrecorded activity feedback")
                ScanHistoryRecordingFeedback(message: "This scan couldn’t be saved to History. Its results and your choices are still here.")
                end("save-failed", "Current findings remain usable.")
            }
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                heading("partial-clear", "Partial maintenance outcome")
                StatusRow(text: "Cleared 1 completed cleanup run. Scan activity and growth baseline clearing could not be confirmed. Recovery facts remain protected.", symbol: "info.circle")
                end("partial-clear", "Clear applies across all History filters.")
            }
        }
    }
    private func heading(_ id: String, _ title: String) -> some View { Text("Synthetic History · " + title).font(CacheDropDesign.TypeStyle.section).accessibilityIdentifier("historyGalleryCase-" + id) }
    private func end(_ id: String, _ text: String) -> some View { Text(text).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("historyGalleryEnd-" + id) }
}
#endif
