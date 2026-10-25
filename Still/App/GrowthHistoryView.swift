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
    private var selectedObservationID: UUID?
    private var liveComparison: GrowthComparison?
    private var latestRecorded: GrowthSnapshot?
    private var displayRequest = UUID()
    var historicalBusy = false
    var selectedScopeID: String?
    var detailsExpanded = false
    var observationsExpanded = false
    var dimension = GrowthDimension.folder
    var outcomeNotice: String?
    var accessNotice: String?
    var needsLocationAccess = false
    var selectNextLocation = false
    var loading = false
    var archiveUnavailable = false
    var resolvedURL: URL?
    var isResolving = false
    var authorityChecking = false
    private var authorityRequest = UUID()
    private var resolvedSnapshotID: UUID?
    var locations: [GrowthSnapshot] {
        var seen = Set<String>()
        return snapshots.reversed().filter { seen.insert($0.fingerprint.scopeID).inserted }
    }
    func locationLabel(_ snapshot: GrowthSnapshot) -> String {
        let duplicates = locations.filter { $0.scopeLabel == snapshot.scopeLabel }.count > 1
        return duplicates ? snapshot.scopeLabel + " · " + String(snapshot.fingerprint.scopeID.prefix(8)) : snapshot.scopeLabel
    }
    var locationObservations: [GrowthSnapshot] { snapshots.reversed().filter { $0.fingerprint.scopeID == selectedScopeID } }
    var scanTitle: String { needsLocationAccess ? "Locate folder…" : comparison?.current == nil ? "Scan to establish a baseline" : "Scan again to compare" }
    var historicalUnavailable: Bool { requestedObservation != nil && !historicalBusy && historicalComparison?.current?.id != requestedObservation }
    var isHistorical: Bool { requestedObservation != nil }
    var comparison: GrowthComparison? { isHistorical ? historicalComparison : liveComparison }
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
        let request = UUID(); displayRequest = request
        if let requestedObservation {
            historicalBusy = true
            defer { if displayRequest == request { historicalBusy = false } }
            do {
                let value = try await store().comparison(id: requestedObservation)
                guard displayRequest == request, self.requestedObservation == requestedObservation, !Task.isCancelled else { return }
                historicalComparison = value; historicalError = nil
                await refreshAuthority()
            } catch {
                guard displayRequest == request, self.requestedObservation == requestedObservation, !Task.isCancelled else { return }
                historicalComparison = nil; historicalError = "The recorded comparison could not be read. No other observation was selected."
            }
            return
        }
        loading = true
        defer { if displayRequest == request { loading = false } }
        do {
            let value = try open(); await value.load()
            guard displayRequest == request, !Task.isCancelled else { return }
            guard value.error == nil else { archiveUnavailable = true; liveComparison = nil; return }
            openingError = nil; archiveUnavailable = false
            if let selectedObservationID {
                let result = try await store().comparison(id: selectedObservationID)
                guard displayRequest == request, !Task.isCancelled else { return }
                liveComparison = result
            } else if let selectedScopeID, let latest = locations.first(where: { $0.fingerprint.scopeID == selectedScopeID }) {
                let result = try await store().comparison(id: latest.id)
                guard displayRequest == request, !Task.isCancelled else { return }
                liveComparison = result; selectedObservationID = latest.id
            } else if selectedScopeID == nil, let latest = locations.first {
                let result = try await store().comparison(id: latest.id)
                guard displayRequest == request, !Task.isCancelled else { return }
                selectedScopeID = latest.fingerprint.scopeID; selectedObservationID = latest.id; liveComparison = result
            } else { liveComparison = value.comparison?.current == nil ? value.comparison : nil }
            await refreshAuthority()
        } catch {
            guard displayRequest == request, !Task.isCancelled else { return }
            archiveUnavailable = true; liveComparison = nil
            openingError = "Comparison history is unavailable. No growth can be inferred from missing observations."
        }
    }
    func requestHistorical(_ id: UUID) {
        displayRequest = UUID(); requestedObservation = id; historicalComparison = nil; historicalError = nil; historicalBusy = true
        resolvedURL = nil; accessNotice = nil; needsLocationAccess = false
    }
    func endHistoricalRequest() { displayRequest = UUID(); requestedObservation = nil; historicalComparison = nil; historicalError = nil; historicalBusy = false }
    func moveHistoricalToCurrent() {
        guard let current = historicalComparison?.current else { return }
        let retained = historicalComparison
        endHistoricalRequest(); selectedScopeID = current.fingerprint.scopeID; selectedObservationID = current.id; liveComparison = retained
    }
    func retainedBaseline(for scan: ScanResult) -> UUID? {
        guard let current = latestRecorded, current.observedAt == scan.observedAt,
              current.scopeLabel == scan.scope.lastPathComponent, snapshots.contains(where: { $0.id == current.id }) else { return nil }
        return current.id
    }
    func begin(_ scope: URL, exclusionFingerprint: String = "none") async -> GrowthScanToken? {
        guard Self.enabled else { return nil }
        outcomeNotice = nil
        do { return await (try open()).begin(scope, exclusionFingerprint: exclusionFingerprint) }
        catch { openingError = "Scope or volume identity could not be verified. This scan cannot establish a comparison baseline."; return nil }
    }
    func complete(_ scan: ScanResult, token: GrowthScanToken?) async {
        await session?.complete(scan, token: token)
        latestRecorded = session?.comparison?.current.flatMap { current in current.observedAt == scan.observedAt && snapshots.contains(where: { $0.id == current.id }) ? current : nil }
        if !scan.isComplete || scan.hasUnmeasuredContents {
            outcomeNotice = "This scan could not establish a complete measured baseline. Retained observations are shown below."
        } else { outcomeNotice = nil }
        guard !isHistorical else { return }
        if let current = latestRecorded, selectNextLocation || selectedScopeID == nil || selectedScopeID == current.fingerprint.scopeID {
            selectedScopeID = current.fingerprint.scopeID; selectedObservationID = current.id; selectNextLocation = false
        }
        // Re-read the selected exact comparison even for partial results: either endpoint may have expired.
        // A failed save must remain visible; load() would clear the session's recording error.
        let request = UUID(); displayRequest = request
        do {
            var value: GrowthComparison?
            if let selectedObservationID { value = try await store().comparison(id: selectedObservationID) }
            guard displayRequest == request, !Task.isCancelled else { return }
            liveComparison = value ?? session?.comparison; archiveUnavailable = false
            await refreshAuthority()
        } catch { archiveUnavailable = true; openingError = "Comparison history is unavailable. Current scan results remain usable."; liveComparison = nil }
    }
    func invalidateCoverage() async throws { guard Self.enabled else { return }; try await open().invalidateCoverage() }
    func clearCompletedHistory() async throws {
        displayRequest = UUID(); try await open().clearCompletedHistory(); selectedObservationID = nil; liveComparison = session?.comparison; resolvedURL = nil
    }
    func resetHistory() async throws {
        displayRequest = UUID(); try await open().resetHistory(); selectedScopeID = nil; selectedObservationID = nil; liveComparison = session?.comparison; resolvedURL = nil
    }
    func failed() {
        guard Self.enabled else { return }
        outcomeNotice = "Scan failed. No new baseline was recorded; retained observations are shown below."
        Task { await self.load() }
    }
    func cancelled() {
        session?.cancelled(); outcomeNotice = "Scan stopped. No new baseline was recorded; retained observations are shown below."
        Task { await self.load() }
    }
    func select(_ id: UUID) async {
        guard let snapshot = snapshots.first(where: { $0.id == id }) else { return }
        let request = UUID(); displayRequest = request
        do {
            let result = try await store().comparison(id: id)
            guard displayRequest == request, !Task.isCancelled else { return }
            selectedScopeID = snapshot.fingerprint.scopeID; selectedObservationID = id; liveComparison = result; loading = false
            accessNotice = nil; needsLocationAccess = false; archiveUnavailable = false
            await refreshAuthority()
        } catch {
            guard displayRequest == request, !Task.isCancelled else { return }
            archiveUnavailable = true; openingError = "The selected comparison is unavailable. Retry reloads records only."
        }
    }
    func selectLocation(_ id: String) async { if let latest = locations.first(where: { $0.fingerprint.scopeID == id }) { await select(latest.id) } }
    func matches(_ url: URL, snapshot: GrowthSnapshot) async -> Bool {
        do { return try await GrowthScanRecorder(store: store()).matchesLocation(url, snapshot: snapshot) }
        catch { return false }
    }
    func leaseForSelection() async -> ScopeAccessLease? {
        guard let snapshot = comparison?.current else { return nil }
        let locations = AppLifecycleController.shared.locations
        for scope in locations.included {
            guard let lease = locations.resolve(scope) else { continue }
            if await matches(lease.url, snapshot: snapshot), comparison?.current?.id == snapshot.id { return lease }
            lease.close()
        }
        return nil
    }
    func refreshAuthority() async {
        let snapshotID = comparison?.current?.id
        let request = UUID(); authorityRequest = request; authorityChecking = true
        defer { if authorityRequest == request { authorityChecking = false } }
        if resolvedSnapshotID != snapshotID { resolvedURL = nil; resolvedSnapshotID = snapshotID }
        if let lease = await leaseForSelection() {
            defer { lease.close() }
            guard authorityRequest == request, comparison?.current?.id == snapshotID else { return }
            resolvedURL = lease.url
        } else if authorityRequest == request { resolvedURL = nil }
    }
}

/// Shared observed-size presentation, also used by inert Gallery examples.
struct GrowthComparisonSummary: View {
    let current: GrowthSnapshot?
    let from: Date?
    let delta: Int64?
    init(comparison: GrowthComparison) { current = comparison.current; from = comparison.from; delta = comparison.logicalDelta }
    init(snapshot: GrowthSnapshot, from: Date? = nil, delta: Int64? = nil) { current = snapshot; self.from = from; self.delta = delta }
    var body: some View {
        if let current {
            SummarySurface {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    Text("Scope: " + current.scopeLabel).font(StillDesign.TypeStyle.section)
                        .fixedSize(horizontal: false, vertical: true)
                    if let delta {
                        Text(GrowthPresentation.signed(delta) + " net logical change")
                            .font(StillDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier("growthNetChange")
                    } else { Text("Baseline established").font(StillDesign.TypeStyle.value) }
                    if let start = from {
                        Text(start.formatted(date: .abbreviated, time: .standard) + " → " + current.observedAt.formatted(date: .abbreviated, time: .standard))
                    } else { Text("Observed " + current.observedAt.formatted(date: .abbreviated, time: .standard)) }
                    Text("Complete logical-size inventory · Not reclaimable space").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum GrowthPresentation {
    static func signed(_ bytes: Int64) -> String {
        (bytes > 0 ? "+" : bytes < 0 ? "−" : "") + ByteCountFormatter.string(fromByteCount: bytes == .min ? .max : abs(bytes), countStyle: .decimal)
    }
    static func message(_ state: GrowthComparisonState) -> String {
        switch state {
        case .firstBaseline: "One retained baseline · Scan this location again to compare."
        case .clearedBaseline: "History was cleared · Two retained compatible observations are needed to compare."
        case .missingBaseline: "Two retained compatible observations are needed. An earlier observation is unavailable."
        case .coverageChanged: "Coverage changed · Root, volume, access, scan/exclusion rules or classification differ. This complete observation establishes a new baseline; scan again to compare."
        case .unknown: "Growth unknown · This observation is incomplete, unmeasured or unavailable."
        case .compared: "Compatible completed observations · Increases and decreases are net logical-size changes."
        }
    }
}

struct GrowthChangeBreakdown: View {
    let comparison: GrowthComparison
    @Binding var dimension: GrowthDimension
    private var groups: [GrowthChange] { comparison.groups.filter { $0.dimension == dimension && $0.logicalDelta != 0 }.sorted { abs($0.logicalDelta) == abs($1.logicalDelta) ? $0.id < $1.id : abs($0.logicalDelta) > abs($1.logicalDelta) } }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            Picker("Growth breakdown", selection: $dimension) {
                Text("Folders").tag(GrowthDimension.folder)
                Text("File types").tag(GrowthDimension.category)
            }.pickerStyle(.menu).fixedSize().accessibilityLabel("Growth breakdown")
            if groups.isEmpty {
                StatusRow(text: "No aggregate size change observed in this view. Individual files may still have changed.", symbol: "equal.circle")
            } else {
                ForEach([true, false], id: \.self) { increases in
                    let rows = groups.filter { ($0.logicalDelta > 0) == increases }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            Text(increases ? "Increases" : "Decreases").font(StillDesign.TypeStyle.section)
                            ForEach(rows) { group in
                                GrowthChangeRow(label: group.label, delta: group.logicalDelta,
                                    maximum: groups.map { abs($0.logicalDelta) }.max() ?? 1)
                            }
                        }
                    }
                }
            }
            Text("Folders and file types describe the same bytes from different views; do not add them together.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct GrowthChangeRow: View {
    let label: String
    let delta: Int64
    let maximum: Int64
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: StillDesign.Space.md)
                Text(GrowthPresentation.signed(delta)).monospacedDigit().fixedSize()
            }
            GeometryReader { geometry in
                Capsule().fill(StillDesign.summary)
                Capsule().fill(delta > 0 ? StillDesign.purple : StillDesign.teal)
                    .frame(width: geometry.size.width * min(1, Double(abs(delta)) / Double(max(1, maximum))))
            }.frame(height: 5).accessibilityHidden(true)
        }.accessibilityElement(children: .combine)
    }
}

struct GrowthHistoryView: View {
    @Bindable var model: GrowthHistoryModel
    var reviewTitle: String? = nil
    var review: (() -> Void)? = nil
    var scanHistorical: (() -> Void)? = nil
    var actionsEnabled = true
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "What grew", subtitle: "What changed between your manual scans. Changes do not identify who wrote files or what can be cleaned.")
            if !model.isHistorical && !model.locations.isEmpty {
                Picker("Comparison location", selection: Binding(get: { model.selectedScopeID ?? model.locations.first!.fingerprint.scopeID }, set: { id in Task { await model.selectLocation(id) } })) {
                    ForEach(model.locations) { snapshot in Text(model.locationLabel(snapshot)).tag(snapshot.fingerprint.scopeID) }
                }.pickerStyle(.menu).accessibilityLabel("Comparison location")
            }
            ScanHistoryRecordingNotice()
            if AppLifecycleController.shared.inspection.isScanning {
                let inspection = AppLifecycleController.shared.inspection
                ScanProgressSummary(inspectedEntries: inspection.progress?.visitedEntries ?? 0,
                    logicalSubtotal: inspection.progress.map { ByteCountFormatter.string(fromByteCount: $0.knownLogicalSubtotal, countStyle: .decimal) } ?? "Unknown", recentNames: [], phaseMessage: "Scanning " + (inspection.scope?.lastPathComponent ?? "selected location") + "…")
            }
            if let outcome = model.outcomeNotice, !model.isHistorical { StatusRow(text: outcome, symbol: "info.circle") }
            if let notice = model.accessNotice { StatusRow(text: notice, symbol: "folder.badge.questionmark", role: .caution) }
            if let error = model.error, !model.archiveUnavailable && !model.isHistorical { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            if (model.archiveUnavailable && !model.isHistorical) || (model.isHistorical && model.error != nil) {
                HistoryStoreFailure(message: model.error ?? "Comparison history is unavailable.", retryTitle: "Retry comparison history") { Task { await model.load() } }
            } else if model.historicalBusy { ProgressView("Reading recorded comparison…") }
            else if model.historicalUnavailable {
                EmptyState(title: "Comparison unavailable for this recorded observation.", detail: "The exact linked baseline is missing, expired or unreadable. No other observation was substituted, and no scan was started.", symbol: "clock.badge.exclamationmark")
            } else if let comparison = model.comparison {
                if comparison.current == nil {
                    EmptyState(title: "Establish a baseline", detail: comparison.state == .firstBaseline ? "Scan a location now, then scan it again later to compare two completed observations. Nothing scans automatically." : GrowthPresentation.message(comparison.state), symbol: "chart.line.uptrend.xyaxis")
                } else {
                    GrowthComparisonSummary(comparison: comparison)
                    StatusRow(text: GrowthPresentation.message(comparison.state), symbol: comparison.state == .compared ? "chart.line.uptrend.xyaxis" : "info.circle", role: comparison.state == .coverageChanged ? .caution : .neutral)
                    if comparison.state == .compared { GrowthChangeBreakdown(comparison: comparison, dimension: $model.dimension) }
                }
            } else if !model.loading {
                EmptyState(title: "Establish a baseline", detail: "Scan a location now, then scan it again later to compare two completed observations. Nothing scans automatically.", symbol: "chart.line.uptrend.xyaxis")
            }
            if let review, let reviewTitle, model.comparison?.current != nil {
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    Text("Review uses current findings, not historical file-level changes. Nothing is selected automatically.").font(.caption).foregroundStyle(.secondary)
                    Button(reviewTitle, action: review).disabled(!actionsEnabled || model.isResolving || model.authorityChecking || AppLifecycleController.shared.inspection.isScanning)
                }
            }
            if model.isHistorical, let scanHistorical, model.comparison?.current != nil, !model.historicalUnavailable {
                Text("A new manual scan creates a current observation; this recorded comparison is not replaced silently.").font(.caption).foregroundStyle(.secondary)
                Button("Scan this location now", action: scanHistorical).disabled(!actionsEnabled || model.isResolving || model.authorityChecking || AppLifecycleController.shared.inspection.isScanning)
            }
            if !model.isHistorical && !model.locationObservations.isEmpty {
                DisclosureGroup("Completed observations", isExpanded: $model.observationsExpanded) {
                    ForEach(model.locationObservations) { snapshot in
                        Button(snapshot.observedAt.formatted(date: .abbreviated, time: .standard)) { Task { await model.select(snapshot.id) } }
                    }
                }.padding(.leading, StillDesign.Space.xl)
            }
            DisclosureGroup("Measurement details", isExpanded: $model.detailsExpanded) {
                Text("Linked files count once, under their first observed path. Alias changes can shift folder or file-type totals without changing net size. Comparisons describe observed logical size, not exclusive disk allocation or writer activity. No aggregate change does not prove individual files are unchanged.").font(.caption).foregroundStyle(.secondary)
            }.padding(.leading, StillDesign.Space.xl)
            StatusRow(text: "Scan activity and enabled growth aggregates share 90-day retention and a 250 MB archive budget, with at most 30 growth baselines. File contents and scanned child-file catalogues are not stored. Recorded root paths and folder names remain sensitive local metadata. Logical change is not reclaimable space.", symbol: "lock")
        }.task { await model.load() }
    }
}

#if DEBUG
struct GrowthGalleryExamples: View {
    private let date = Date(timeIntervalSince1970: 1_761_523_200)
    private var snapshot: GrowthSnapshot {
        GrowthSnapshot(fingerprint: GrowthFingerprint(scopeID: "synthetic", rootID: "synthetic", volumeID: "synthetic", access: "synthetic", rules: "synthetic", exclusions: "none", classification: "synthetic"), scopeLabel: "Downloads · Synthetic example", observedAt: date, groups: [GrowthAggregate(id: "synthetic", label: "Files in selected folder", logicalBytes: 8_000_000)])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Text("Synthetic growth examples · Inert, no scans or archive access").font(.caption).foregroundStyle(.secondary)
            Text("One retained baseline").font(StillDesign.TypeStyle.section)
            GrowthComparisonSummary(snapshot: snapshot)
            StatusRow(text: GrowthPresentation.message(.firstBaseline), symbol: "info.circle")
            Text("Compatible comparison").font(StillDesign.TypeStyle.section)
            GrowthComparisonSummary(snapshot: snapshot, from: date.addingTimeInterval(-86_400), delta: 2_000_000)
            Text("Increases").font(StillDesign.TypeStyle.section)
            GrowthChangeRow(label: "Documents", delta: 3_000_000, maximum: 3_000_000)
            Text("Decreases").font(StillDesign.TypeStyle.section)
            GrowthChangeRow(label: "Archives and installers", delta: -1_000_000, maximum: 3_000_000)
            Text("Tiny changes remain readable").font(StillDesign.TypeStyle.section)
            GrowthChangeRow(label: "Other files", delta: 3, maximum: 3_000_000)
            Text("Zero net can contain both directions").font(StillDesign.TypeStyle.section)
            GrowthComparisonSummary(snapshot: snapshot, from: date.addingTimeInterval(-86_400), delta: 0)
            GrowthChangeRow(label: "Added folder", delta: 1_000, maximum: 1_000)
            GrowthChangeRow(label: "Removed folder", delta: -1_000, maximum: 1_000)
        }
    }
}
#endif
