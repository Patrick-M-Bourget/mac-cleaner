import Foundation
import Observation
import StillCore
import SwiftUI

@MainActor @Observable final class SessionPlan {
    let execution = CleanupExecutionModel()
    private(set) var draft = PlanDraft()
    private(set) var scans: [URL: ScanResult] = [:]
    private(set) var message: String?
    private(set) var isPreparing = false
    private(set) var isRetryRechecking = false
    private(set) var retryTargetIDs: Set<String>?
    private(set) var retryExcludedURLs: [URL] = []
    private var retryCancellation: ScanCancellation?
    private var retryGeneration = UUID()
    private(set) var approvedBatch: CleanupApproval?
    var mutationVersion: UInt64 { draft.mutationVersion }
    var canReview: Bool { !AppLifecycleController.shared.maintenanceInProgress && !isPreparing && !execution.isRunning && !isRefreshing && refresh.canReview(draft) }
    var categoryState: CategorySelectionState {
        guard let downloads else { return .unchecked }
        return draft.categoryState(in: Array(scans.values), downloads: downloads, restrictingTo: retryTargetIDs)
    }
    var eligibleLogicalBytes: Int64 {
        var seen = Set<String>()
        return rows.filter { seen.insert($0.item.resourceID).inserted }.reduce(0) { $0 + ($1.item.logicalBytes ?? 0) }
    }
    private var expectedExclusionFingerprint = "none"
    func invalidateCoverage() {
        stopRetryRecheck(); retryGeneration = UUID(); isPreparing = false; isRetryRechecking = false
        refresh.invalidateCoverage(draft: &draft); refreshRequests.removeAll(); approvedBatch = nil
        scans.removeAll()
        message = "Exclusion settings changed. Recheck selected locations before choosing files or reviewing cleanup."
    }
    func expectExclusions(_ fingerprint: String) {
        if expectedExclusionFingerprint != fingerprint { invalidateCoverage(); expectedExclusionFingerprint = fingerprint }
    }
    private(set) var refresh = RefreshChoices()
    private var refreshRequests: [URL: RefreshRequest] = [:]
    private let refreshValidator = RefreshValidator()
    var isRefreshing: Bool { !refreshRequests.isEmpty }
    var pendingCount: Int { draft.selected.filter { refresh.requiresRefresh($0.id) }.count }
    var refreshScopes: [URL] { Array(Set(scans.keys).union(draft.selected.map(\.scope))).sorted { $0.path < $1.path } }
    func beginRefresh(_ scope: URL) -> RefreshRequest {
        if isRetryRechecking { stopRetryRecheck(); retryGeneration = UUID(); isPreparing = false; isRetryRechecking = false }
        invalidateReview()
        let request = refresh.begin(scope: scope, draft: &draft)
        refreshRequests[request.scope] = request
        return request
    }
    func cancelRefresh(_ request: RefreshRequest) {
        guard refreshRequests[request.scope]?.id == request.id else { return }
        refresh.cancel(request)
        refreshRequests[request.scope] = nil
        invalidateReview()
    }
    func finishRefresh(_ request: RefreshRequest, scan: ScanResult) async {
        guard scan.exclusionFingerprint == expectedExclusionFingerprint else { cancelRefresh(request); return }
        let outcome = await refreshValidator.validate(request, against: scan)
        guard refreshRequests[request.scope]?.id == request.id else { return }
        refresh.finish(outcome, draft: &draft)
        refreshRequests[request.scope] = nil
        invalidateReview()
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    private var downloads: DownloadsRoot?
    #if DEBUG
    private var requestedFixture: URL?
    #endif
    init() {
        let root = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        downloads = root.flatMap { try? DownloadsRoot(url: $0) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-downloads-root"),
           let path = ProcessInfo.processInfo.environment["STILL_TEST_DOWNLOADS_ROOT"] {
            requestedFixture = URL(fileURLWithPath: path)
        }
        #endif
    }
    struct Row: Identifiable {
        let item: FileObservation
        let scan: ScanResult
        var id: String { item.url.path + "|" + item.resourceID }
    }
    var unavailableSelected: [PlannedTarget] {
        let ids = Set(rows.map { $0.item.url.path + "|" + $0.item.resourceID + "|moveToTrash" })
        return draft.selected.filter { !ids.contains($0.id) }
    }
    var rows: [Row] {
        var seen = Set<String>()
        return scans.values.sorted { $0.observedAt > $1.observedAt }.flatMap { scan in
            scan.observations.compactMap { item in
                let row = Row(item: item, scan: scan)
                return eligible(item, in: scan) && retryTargetIDs?.contains(row.id + "|moveToTrash") != false && seen.insert(row.id).inserted ? row : nil
            }
        }.sorted { $0.item.url.path < $1.item.url.path }
    }
    func observe(_ scan: ScanResult) {
        guard !execution.isRunning, scan.exclusionFingerprint == expectedExclusionFingerprint else { return }
        if isRetryRechecking { stopRetryRecheck(); retryGeneration = UUID(); isPreparing = false; isRetryRechecking = false }
        execution.clear()
        if let newer = scans[scan.scope], newer.observedAt > scan.observedAt { return }
        #if DEBUG
        // Bind only after NSOpenPanel selected the exact fixture; never probe runner data at launch.
        if let requestedFixture, requestedFixture.standardizedFileURL.path == scan.scope.standardizedFileURL.path,
           let fixture = try? DownloadsRoot(url: scan.scope), fixture.url.lastPathComponent.hasPrefix("StillSelectionUI-") {
            let runnerTemp = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.patrickbourget.StillUITests.xctrunner/Data/tmp")
            let canonicalRunnerTemp: String? = runnerTemp.path
            let canonicalAppTemp = (try? DownloadsRoot(url: FileManager.default.temporaryDirectory))?.url.path
            let parent = fixture.url.deletingLastPathComponent().path
            if [canonicalRunnerTemp, canonicalAppTemp, "/private/tmp", "/tmp"].compactMap({ $0 }).contains(parent) { downloads = fixture }
        }
        #endif
        invalidateReview()
        scans[scan.scope] = scan
    }
    func eligible(_ item: FileObservation, in scan: ScanResult) -> Bool {
        guard scan.exclusionFingerprint == expectedExclusionFingerprint, let downloads else { return false }
        return PlanDraft.canConsider(item, in: scan, downloads: downloads)
    }
    func invalidateReview() { draft.invalidateReview(); approvedBatch = nil }
    func review() throws -> CleanupReview {
        guard canReview else { throw PlanSelectionError.ineligible }
        return try draft.review()
    }
    func approve(_ review: CleanupReview) throws {
        guard canReview else { throw PlanSelectionError.ineligible }
        approvedBatch = try draft.approve(review)
    }
    func executeApproved() async {
        guard canReview, let batch = approvedBatch else { return }
        approvedBatch = nil
        draft.clear(); scans.removeAll()
        AppLifecycleController.shared.hasPendingPlan = false
        AppLifecycleController.shared.operationInProgress = true
        await execution.run(batch)
        AppLifecycleController.shared.operationInProgress = false
    }
    func toggleAll() async {
        guard !isPreparing && !isRefreshing && !execution.isRunning else { return }
        if categoryState == .checked { draft.clear(); approvedBatch = nil; AppLifecycleController.shared.hasPendingPlan = false; return }
        guard let downloads else { return }
        invalidateReview()
        let version = mutationVersion, scans = Array(scans.values), current = draft, allowed = retryTargetIDs
        isPreparing = true
        let result = await Task.detached(priority: .userInitiated) {
            var updated = current
            let skipped = updated.selectAll(in: scans, downloads: downloads, restrictingTo: allowed)
            return (updated, skipped)
        }.value
        isPreparing = false
        guard mutationVersion == version else { message = "Findings changed during selection. Review the latest eligible items and try again."; return }
        draft = result.0
        message = result.1 > 0 ? "Some files changed or became unavailable; they were not added." : nil
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func set(_ item: FileObservation, in scan: ScanResult, selected: Bool) {
        guard !isPreparing && !execution.isRunning else { return }
        approvedBatch = nil
        if !selected { draft.remove(item.url.path + "|" + item.resourceID + "|moveToTrash") }
        else {
            guard scan.exclusionFingerprint == expectedExclusionFingerprint, !isRefreshing, let downloads, retryTargetIDs?.contains(item.url.path + "|" + item.resourceID + "|moveToTrash") != false else { return }
            do { try draft.select(item, in: scan, downloads: downloads); message = nil }
            catch { message = "This target is no longer eligible. Recheck its selected Downloads scope." }
        }
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func remove(_ target: PlannedTarget) {
        guard !isPreparing && !execution.isRunning else { return }
        approvedBatch = nil
        draft.remove(target.id)
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func leaveRetryMode() {
        guard !isRetryRechecking && !execution.isRunning else { return }
        retryTargetIDs = nil; retryExcludedURLs = []; message = nil; invalidateReview()
    }
    func stopRetryRecheck() {
        retryCancellation?.cancel()
        message = "Recheck stopped. No retry plan was created; no files were moved."
    }
    func prepareRetry() async {
        guard !isPreparing, !isRefreshing, execution.canRetry, let result = execution.result, let downloads else { return }
        let policy: ExclusionPolicy
        do { policy = try await ExclusionsModel.shared.policyForScan(); expectExclusions(policy.fingerprint) }
        catch { message = "Exclusion settings are unavailable. Recheck is blocked."; return }
        guard !AppLifecycleController.shared.maintenanceInProgress, !execution.isRunning, execution.result?.batchID == result.batchID else { return }
        let records = result.targets, scopes = execution.retryScopes
        let cancellation = ScanCancellation(), token = UUID()
        retryCancellation = cancellation; retryGeneration = token
        isPreparing = true; isRetryRechecking = true; message = nil; invalidateReview()
        defer {
            if retryGeneration == token { isPreparing = false; isRetryRechecking = false; retryCancellation = nil }
        }
        let reports = await Task.detached(priority: .userInitiated) {
            let scanner = FolderScanner()
            var reports: [ScanResult] = []
            for scope in scopes {
                if cancellation.isCancellationRequested { return reports }
                let access = scope.startAccessingSecurityScopedResource()
                do { reports.append(try await scanner.scan(scope, cancellation: cancellation, exclusions: policy)) } catch { }
                if access { scope.stopAccessingSecurityScopedResource() }
            }
            return reports
        }.value
        guard retryGeneration == token, !cancellation.isCancellationRequested, execution.result?.batchID == result.batchID else { return }
        let prepared = await Task.detached(priority: .userInitiated) { RetryPlan.prepare(records: records, scans: reports, downloads: downloads) }.value
        guard retryGeneration == token, !cancellation.isCancellationRequested else { return }
        retryExcludedURLs = prepared.unavailableURLs
        guard prepared.draft.selectedCount > 0 else {
            message = "No unfinished files passed the fresh identity and access checks. Start a new scan from Overview to review changed files."
            return
        }
        draft = prepared.draft; approvedBatch = nil
        scans = Dictionary(reports.map { ($0.scope, $0) }, uniquingKeysWith: { latest, _ in latest })
        refresh = RefreshChoices(); refreshRequests.removeAll()
        retryTargetIDs = Set(draft.selected.map(\.id))
        execution.clear()
        message = "Rechecked \(StillDesign.files(draft.selectedCount)) for a new approval. \(prepared.completedCount) completed and \(prepared.unavailableCount) changed or unavailable targets excluded."
        AppLifecycleController.shared.hasPendingPlan = true
    }
    func endSession() { guard !execution.isRunning else { return }; retryCancellation?.cancel(); retryGeneration = UUID(); retryCancellation = nil; isRetryRechecking = false; isPreparing = false; retryTargetIDs = nil; retryExcludedURLs = []; draft.clear(); scans.removeAll(); refresh = RefreshChoices(); refreshRequests.removeAll(); approvedBatch = nil; AppLifecycleController.shared.hasPendingPlan = false }
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: SessionPlan
    let recheck: (URL) -> Void
    let stopRefresh: () -> Void
    @State private var search = ""
    @State private var review: CleanupReview?
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    @State private var choosingItems = true
    @State private var inspected: FileObservation?
    @State private var visibleRow: String?
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        if selection.execution.isRunning || selection.execution.result != nil || selection.execution.error != nil {
            CleanupExecutionView(model: selection.execution, retryMessage: selection.message).padding(StillDesign.Space.page)
        } else {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            PageHeader(title: "Cleanup plan", subtitle: selection.retryTargetIDs == nil ? "Choose categories, adjust items if needed, then review the changes." : "Only rechecked unfinished files are included. Completed successes and new discoveries stay excluded.")
                .padding(.bottom, StillDesign.Space.sm)
            SelectionSummary(value: ByteCountFormatter.string(fromByteCount: selection.draft.logicalBytes, countStyle: .decimal), detail: "\(StillDesign.files(selection.draft.selectedCount)) selected", identifier: "liveSelectionSummary", consequence: "Space stays occupied until Finder empties Trash. Nothing changes before final confirmation.")
            if selection.isRefreshing || selection.pendingCount > 0 || !selection.refreshScopes.isEmpty {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                HStack {
                    if selection.isRefreshing { ProgressView("Rechecking selected locations…") }
                    else if selection.pendingCount > 0 { StatusRow(text: "Refresh required · Previous observations retained for \(StillDesign.files(selection.pendingCount)).", symbol: "arrow.clockwise", role: .caution) }
                }
                ForEach(selection.refreshScopes, id: \.self) { scope in
                    Button("Recheck location: " + scope.lastPathComponent) { recheck(scope) }.disabled(selection.isRefreshing || selection.isPreparing)
                }
            }
            }
            ForEach(selection.refresh.notices) { notice in
                StatusRow(text: notice.target.url.lastPathComponent + " · " + notice.message, symbol: "info.circle", role: .caution)
            }
            CategorySelectionHeader(category: .downloads, state: selection.categoryState,
                                    title: "Downloads · \(StillDesign.files(selection.rows.count)) eligible",
                                    detail: "Move exact files to Trash. Personal files and installers are included only when selected.",
                                    size: ByteCountFormatter.string(fromByteCount: selection.eligibleLogicalBytes, countStyle: .decimal),
                                    enabled: !selection.isPreparing && !selection.isRefreshing && !selection.rows.isEmpty) {
                Task { await selection.toggleAll() }
            }
            if selection.isPreparing { ProgressView("Checking exact Downloads targets…") }
            if let approved = selection.approvedBatch { Text("Approved batch: \(approved.targets.count) files · No files moved.").foregroundStyle(.secondary) }
            if let approvalError { Text(approvalError).foregroundStyle(.secondary) }
            DisclosureGroup("Choose items", isExpanded: $choosingItems) {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    TextField("Search Downloads items", text: $search)
                    if selection.rows.isEmpty { EmptyState(title: "No eligible files", detail: "Choose and scan Downloads or a folder inside it. Protected or unknown targets remain browse only.", symbol: "folder") }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(selection.rows.filter { search.isEmpty || $0.item.url.path.localizedCaseInsensitiveContains(search) }) { row in
                            InspectableItemRow(name: row.item.url.lastPathComponent, detail: row.item.url.pathComponents.dropFirst(row.scan.scope.pathComponents.count).joined(separator: "/"), size: ByteCountFormatter.string(fromByteCount: row.item.logicalBytes ?? 0, countStyle: .decimal), symbol: "doc", inspected: inspected?.id == row.item.id, inspect: { inspected = row.item }) {
                                Toggle("\(selection.draft.contains(row.item) ? "Selected" : "Select") \(row.item.url.lastPathComponent)", isOn: Binding(get: { selection.draft.contains(row.item) }, set: { selection.set(row.item, in: row.scan, selected: $0) }))
                                    .labelsHidden().disabled(selection.isPreparing || (selection.isRefreshing && !selection.draft.contains(row.item)))
                            }
                            if selection.refresh.requiresRefresh(row.item.url.path + "|" + row.item.resourceID + "|moveToTrash") {
                                StatusRow(text: selection.isRefreshing ? "Rechecking…" : "Refresh required", symbol: "arrow.clockwise", role: .caution).padding(.horizontal, StillDesign.Space.md)
                            }
                            Divider()
                        }
                    }.scrollTargetLayout()
                    if let item = inspected {
                        SummarySurface {
                            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                                Text(item.url.lastPathComponent).font(StillDesign.TypeStyle.section)
                                Text(item.url.path).font(.caption).textSelection(.enabled)
                                Text("Intended action: Move to Trash. Space remains occupied until emptied.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.top, StillDesign.Space.md)
            }.padding(.leading, StillDesign.Space.xl)
            ForEach(selection.unavailableSelected) { target in
                SettingsRow(title: target.url.lastPathComponent, detail: "Selection retained · Recheck this location before review") {
                    Toggle("Selected \(target.url.lastPathComponent)", isOn: Binding(get: { true }, set: { if !$0 { selection.remove(target) } })).disabled(selection.isPreparing)
                }
            }
            if let message = selection.message { Text(message).foregroundStyle(.secondary) }
            ForEach(selection.retryExcludedURLs, id: \.path) { url in
                StatusRow(text: "\(url.lastPathComponent): changed or unavailable. Review it through a new scan from Overview.", symbol: "exclamationmark.circle", role: .caution).help(url.path)
            }
            DisclosureGroup("Size and selection details") {
                Text("Logical size describes the selected files, not guaranteed space freed. Linked files count once in the size total; each selected path is a separate target. Hidden search results keep their selections.").font(.caption).foregroundStyle(.secondary)
            }

        }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
        }
        }.scrollPosition(id: $visibleRow).background(StillDesign.reading)
        if selection.isRetryRechecking {
            ActionStrip(message: "Rechecking unfinished identities. No files are moved.") {
                ProgressView().controlSize(.small)
                Button("Stop recheck") { selection.stopRetryRecheck() }
            }
        } else if selection.execution.isRunning {
            ActionStrip(message: "Stopping never rolls back files already moved to Trash.") {
                Button(selection.execution.stopRequested ? "Stop requested" : "Stop after current file") { selection.execution.cancel() }.disabled(selection.execution.stopRequested)
            }
        } else if selection.execution.canRetry {
            ActionStrip(message: "A retry needs a fresh check and new approval; completed successes stay excluded.") {
                Button("Recheck unfinished files") { Task { await selection.prepareRetry() } }.buttonStyle(.borderedProminent).disabled(selection.isRefreshing || selection.isPreparing)
            }
        } else if selection.execution.result == nil && selection.execution.error == nil {
        ActionStrip(message: selection.isRefreshing ? "Review is paused while findings are rechecked." : selection.pendingCount > 0 ? "Refresh required before reviewing the selected files." : "Nothing changes until you confirm the next step.") {
            if selection.isRefreshing { Button("Stop refresh", action: stopRefresh) }
ReviewCleanupButton(enabled: selection.canReview, focusRequest: reviewFocusRequest) {
                do { review = try selection.review(); approvalError = nil } catch { approvalError = "Recheck the selected targets before reviewing." }
            }.fixedSize()
        }
        }
        }
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            CleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                do { try selection.approve(snapshot); review = nil; Task { await selection.executeApproved() } }
                catch { approvalError = "The plan changed. Review the latest exact targets before approving."; review = nil }
            }
        }
        .onChange(of: selection.mutationVersion) { _, _ in if review != nil { review = nil } }
    }
}

private struct CleanupConfirmationView: View {
    let review: CleanupReview
    let cancel: () -> Void
    let approve: () -> Void
    @State private var expanded = false
    private var logicalBytes: Int64 {
        var seen = Set<String>()
        return review.targets.filter { seen.insert($0.resourceID).inserted }.reduce(0) { $0 + $1.logicalBytes }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            PageHeader(title: "Review Move to Trash")
            SummarySurface { Label("\(StillDesign.files(review.targets.count)) · \(ByteCountFormatter.string(fromByteCount: logicalBytes, countStyle: .decimal)) logical size", systemImage: "trash") }
            Text("Space remains occupied until Finder empties Trash. Files may have separate Trash locations; folder structure and automatic restoration are not guaranteed.").foregroundStyle(.secondary)
            Text("Downloads scope · No folders or new discoveries will be included.").font(.callout)
            Text("Confirming moves only this exact batch to Trash. There is no permanent-delete fallback.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    Text("Selected scan locations").font(.headline)
                    ForEach(Array(Set(review.targets.map { $0.scope.path })).sorted(), id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    DisclosureGroup("Exact files (\(review.targets.count))", isExpanded: $expanded) {
                        LazyVStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            ForEach(review.targets) { target in
                                Text(target.url.pathComponents.dropFirst(target.downloadsRoot.url.pathComponents.count).joined(separator: "/"))
                                    .font(.callout).textSelection(.enabled)
                            }
                        }.padding(.top, StillDesign.Space.sm)
                    }
                }
                // Native macOS disclosure arrows extend before their label; keep that control inside the scroll clip.
                .padding(.leading, StillDesign.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); Button("Move to Trash", action: approve).buttonStyle(.borderedProminent) }
        }.padding(StillDesign.Space.xl).frame(width: 640, height: 520).background(StillDesign.reading)
    }
}


