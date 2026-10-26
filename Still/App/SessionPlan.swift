import Foundation
import Observation
import StillCore
import SwiftUI

@MainActor @Observable final class SessionPlan {
    let execution = CleanupExecutionModel()
    let chrome: ChromeCleanupModel = {
        #if DEBUG
        if let fixture = ChromeCleanupFixture.makeModel() { return fixture }
        #endif
        return ChromeCleanupModel()
    }()
    private(set) var workspaceRunning = false
    private(set) var workspaceFinished = false
    private(set) var workspaceStopRequested = false
    private var workspaceCancellation: CleanupCancellation?
    private(set) var workspaceBefore: StartupVolumeCapacity?
    private(set) var workspaceAfter: StartupVolumeCapacity?
    var hasWorkspaceResult: Bool { workspaceFinished || execution.result != nil || execution.error != nil || chrome.result != nil }
    var hasPendingChoices: Bool { draft.selectedCount > 0 || chrome.selectedCount > 0 }
    var workspaceSelectedCount: Int { draft.selectedCount + chrome.selectedCount }
    var workspaceSelectedSize: String {
        if !hasPendingChoices { return "—" }
        if chrome.selectedCount == 0 { return ByteCountFormatter.string(fromByteCount: draft.logicalBytes, countStyle: .decimal) }
        guard let cache = chrome.estimatedBytes else { return "Unknown" }
        let sum = draft.logicalBytes.addingReportingOverflow(cache)
        return sum.overflow ? "Unknown" : ByteCountFormatter.string(fromByteCount: sum.partialValue, countStyle: .decimal)
    }
    var workspaceObservedChange: Int64? {
        guard let before = workspaceBefore, let after = workspaceAfter, let id = before.volumeID,
              id == after.volumeID, before.total == after.total, before.metric == after.metric,
              let first = before.available, let last = after.available else { return nil }
        return last - first
    }
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
    private(set) var unavailableScopes: Set<URL> = []
    var mutationVersion: UInt64 { draft.mutationVersion }
    var canReview: Bool {
        !AppLifecycleController.shared.maintenanceInProgress && !isPreparing && !execution.isRunning && !workspaceRunning && !chrome.isBusy && !chrome.isRunning && !isRefreshing
        && (draft.selectedCount == 0 || refresh.canReview(draft))
        && (chrome.selectedCount == 0 || chrome.canReview) && hasPendingChoices
    }
    /// Downloads is the only currently actionable cleanup category. Count live
    /// reviewable membership, never retained suspended choices or consumed results.
    var actionableSelectedCategoryCount: Int {
        guard canReview else { return 0 }
        let selected = Set(draft.selected.map(\.id))
        return (rows.contains { selected.contains($0.id + "|moveToTrash") && !refresh.requiresRefresh($0.id + "|moveToTrash") } ? 1 : 0) + (chrome.canReview ? 1 : 0)
    }
    var categoryState: CategorySelectionState {
        guard let downloads else { return .unchecked }
        return draft.categoryState(in: Array(scans.values.filter { !unavailableScopes.contains($0.scope.standardizedFileURL) }), downloads: downloads, restrictingTo: retryTargetIDs)
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
    private var isRefreshingBatch = false
    private let refreshValidator = RefreshValidator()
    var isRefreshing: Bool { isRefreshingBatch || !refreshRequests.isEmpty }
    func beginRefreshBatch(_ scopes: [URL]) -> [RefreshRequest] {
        isRefreshingBatch = true
        return scopes.map { beginRefresh($0) }
    }
    func endRefreshBatch(_ unfinished: [RefreshRequest]) {
        for request in unfinished {
            cancelRefresh(request)
            // An overlapping completed scope may have retired this scope's pending targets.
            // A requested but unstarted scope still needs its own complete refresh after Cancel.
            let pending = beginRefresh(request.scope)
            cancelRefresh(pending)
        }
        isRefreshingBatch = false
    }
    var pendingCount: Int { draft.selected.filter { refresh.requiresRefresh($0.id) }.count }
    var refreshScopes: [URL] { Array(Set(scans.keys).union(draft.selected.map(\.scope))).sorted { $0.path < $1.path } }
    func beginRefresh(_ scope: URL) -> RefreshRequest {
        if isRetryRechecking { stopRetryRecheck(); retryGeneration = UUID(); isPreparing = false; isRetryRechecking = false }
        invalidateReview()
        unavailableScopes.insert(scope.standardizedFileURL)
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
        if scan.isComplete { unavailableScopes.remove(scan.scope.standardizedFileURL) }
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
    enum OverviewDownloadsCoverage { case notInspected, incomplete, complete }
    /// Current included Downloads coverage, separate from eligibility and retry-plan membership.
    var overviewDownloadsCoverage: OverviewDownloadsCoverage {
        guard let downloads else { return .notInspected }
        let root = downloads.url.standardizedFileURL.pathComponents
        let locations = AppLifecycleController.shared.locations
        let included = locations.includedDownloads
        let includedPaths = Set(included.map(\.path))
        let reports = scans.values.filter {
            $0.exclusionFingerprint == expectedExclusionFingerprint
                && $0.scope.standardizedFileURL.pathComponents.starts(with: root)
                && includedPaths.contains($0.scope.standardizedFileURL.path)
        }
        // Resolving a missing grant retires its scan, but that is failed coverage,
        // not a never-inspected location. Omitted and freshly re-included scopes
        // remain separate from this explicit recovery state.
        let accessUnavailable = included.contains { locations.statuses[$0.id]?.needsRecovery == true }
        guard !reports.isEmpty else { return accessUnavailable ? .incomplete : .notInspected }
        let observedPaths = Set(reports.map { $0.scope.standardizedFileURL.path })
        return !accessUnavailable && includedPaths.isSubset(of: observedPaths)
            && reports.allSatisfy { $0.totalLogicalBytes != nil && !unavailableScopes.contains($0.scope.standardizedFileURL) }
            ? .complete : .incomplete
    }
    /// Available observed Downloads findings, independent of any targeted retry subset.
    var overviewDownloadRows: [Row] { eligibleRows(restrictingTo: nil) }
    var overviewDownloadsLogicalBytes: Int64? {
        var seen = Set<String>()
        var total: Int64 = 0
        for row in overviewDownloadRows.sorted(by: { $0.scan.observedAt > $1.scan.observedAt }) where seen.insert(row.item.resourceID).inserted {
            guard let size = row.item.logicalBytes else { return nil }
            let sum = total.addingReportingOverflow(size)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
    }
    var rows: [Row] { eligibleRows(restrictingTo: retryTargetIDs) }
    /// Last observed names remain browsable while their current selection authority is suspended.
    /// This is presentation evidence only; set/review still require current eligible scans.
    var displayedRows: [Row] {
        guard let downloads else { return [] }
        let current = rows
        var seen = Set(current.map(\.id))
        let historical = scans.values.sorted { $0.observedAt > $1.observedAt }.flatMap { scan in
            scan.observations.compactMap { item -> Row? in
                let row = Row(item: item, scan: scan)
                guard scan.exclusionFingerprint == expectedExclusionFingerprint,
                      PlanDraft.canConsider(item, in: scan, downloads: downloads),
                      retryTargetIDs?.contains(row.id + "|moveToTrash") != false,
                      seen.insert(row.id).inserted else { return nil }
                return row
            }
        }
        return (current + historical).sorted { $0.item.url.path < $1.item.url.path }
    }
    var displayedLogicalBytes: Int64? {
        var seen = Set<String>(), total: Int64 = 0
        for row in displayedRows where seen.insert(row.item.resourceID).inserted {
            guard let value = row.item.logicalBytes else { return nil }
            let sum = total.addingReportingOverflow(value)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
    }
    var observedDownloadsScopes: [URL] {
        guard let downloads else { return [] }
        return scans.values.filter {
            $0.exclusionFingerprint == expectedExclusionFingerprint
                && $0.scope.standardizedFileURL.pathComponents.starts(with: downloads.url.standardizedFileURL.pathComponents)
        }.map(\.scope).sorted { $0.path < $1.path }
    }
    var unavailableOutsideDisplay: [PlannedTarget] {
        let displayed = Set(displayedRows.map { $0.id + "|moveToTrash" })
        return unavailableSelected.filter { !displayed.contains($0.id) }
    }

    private func eligibleRows(restrictingTo targetIDs: Set<String>?) -> [Row] {
        var seen = Set<String>()
        return scans.values.filter { !unavailableScopes.contains($0.scope.standardizedFileURL) }.sorted { $0.observedAt > $1.observedAt }.flatMap { scan in
            scan.observations.compactMap { item in
                let row = Row(item: item, scan: scan)
                return eligible(item, in: scan) && targetIDs?.contains(row.id + "|moveToTrash") != false && seen.insert(row.id).inserted ? row : nil
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
        unavailableScopes.remove(scan.scope.standardizedFileURL)
        scans[scan.scope] = scan
    }
    func eligible(_ item: FileObservation, in scan: ScanResult) -> Bool {
        guard scans[scan.scope]?.observedAt == scan.observedAt, !unavailableScopes.contains(scan.scope.standardizedFileURL), scan.exclusionFingerprint == expectedExclusionFingerprint, let downloads else { return false }
        return PlanDraft.canConsider(item, in: scan, downloads: downloads)
    }
    /// Explanation uses the same observed eligibility boundary as selection; it grants no authority.
    func inspectionRestriction(_ item: FileObservation, in scan: ScanResult) -> String? {
        if isRefreshing { return "Refresh in progress. Previous observations cannot authorize cleanup." }
        if unavailableScopes.contains(scan.scope.standardizedFileURL) { return "This location requires a fresh check before cleanup." }
        if scans[scan.scope]?.observedAt != scan.observedAt || scan.exclusionFingerprint != expectedExclusionFingerprint {
            return "This observation is no longer current. Recheck the location before choosing files."
        }
        if let issue = scan.issues.first(where: { item.url.pathComponents.starts(with: $0.url.pathComponents) }) {
            return issue.reason.rawValue + ": " + issue.recovery
        }
        switch item.kind {
        case .folder: return "Folders are for navigation and inspection. Whole-folder cleanup is unavailable."
        case .package: return "Protected package. Its contents were not inspected and cannot be selected."
        case .symbolicLink: return "Symbolic link. Its destination was not followed and cannot be selected."
        case .other: return "Unsupported item type. Cleanup is unavailable."
        case .file: break
        }
        if item.cloud.membership == true { return "Cloud-managed item. Cloud cleanup is unavailable; no eviction or synced deletion is offered." }
        if item.previewAvailability == .nonlocal { return "Contents are not local. Cleanup and Quick Look are unavailable; no download is requested." }
        if item.previewAvailability == .unknown || item.cloud.membership == nil { return "Locality or cloud membership is unknown. Cleanup is unavailable until verified by a manual recheck." }
        // Classifying an observed location needs only its lexical boundary, not a
        // usable grant. A missing Downloads grant must not misdescribe another folder.
        let downloadsLocation = downloads?.url ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let root = downloadsLocation?.standardizedFileURL.pathComponents,
           !item.url.standardizedFileURL.pathComponents.starts(with: root) || !scan.scope.standardizedFileURL.pathComponents.starts(with: root) {
            return "Inspection only. Exact-file Trash review is available only within Downloads."
        }
        guard downloads != nil else { return "Downloads access is unavailable. Choose Downloads explicitly and recheck." }
        if let downloads, let restriction = PlanDraft.protectedPathRestriction(item, downloads: downloads) {
            switch restriction {
            case .fileType(let ext): return "Protected file type (." + ext + "). This file or an ancestor is excluded from Downloads cleanup."
            case .directoryName(let name): return "Protected location (" + name + "). Files within it are excluded from Downloads cleanup."
            }
        }
        return eligible(item, in: scan) ? nil : "This observation cannot currently support cleanup. Recheck the location before choosing files."
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
    func executeApproved(holdingOperationLock: Bool = false, cancellation: CleanupCancellation? = nil) async {
        guard (canReview || holdingOperationLock), let batch = approvedBatch else { return }
        let leases: [ScopeAccessLease]
        do { leases = try AppLifecycleController.shared.locations.leases(for: batch.targets.map(\.scope)) }
        catch {
            for scope in Set(batch.targets.map(\.scope)) { let request = beginRefresh(scope); cancelRefresh(request) }
            message = "Access must be renewed before cleanup. Your choices were retained; no files moved."
            return
        }
        defer { for lease in leases { lease.close() } }
        approvedBatch = nil
        draft.clear(); scans.removeAll()
        AppLifecycleController.shared.hasPendingPlan = false
        if !holdingOperationLock { AppLifecycleController.shared.operationInProgress = true }
        await execution.run(batch, cancellation: cancellation)
        AppLifecycleController.shared.capacity.request(.cleanupEnded)
        if !holdingOperationLock { AppLifecycleController.shared.operationInProgress = false }
    }
    func toggleAll() async {
        guard !isPreparing && !isRefreshing && !execution.isRunning && !workspaceRunning && !chrome.isRunning else { return }
        if categoryState == .checked { draft.clear(); approvedBatch = nil; AppLifecycleController.shared.hasPendingPlan = false; return }
        guard let downloads else { return }
        var leases: [ScopeAccessLease] = []
        var availableScans: [ScanResult] = []
        for scan in scans.values where !unavailableScopes.contains(scan.scope.standardizedFileURL) {
            do { leases += try AppLifecycleController.shared.locations.leases(for: [scan.scope]); availableScans.append(scan) }
            catch { let request = beginRefresh(scan.scope); cancelRefresh(request) }
        }
        defer { for lease in leases { lease.close() } }
        invalidateReview()
        let version = mutationVersion, scans = availableScans, current = draft, allowed = retryTargetIDs
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
        guard !isPreparing && !execution.isRunning && !workspaceRunning && !chrome.isRunning else { return }
        approvedBatch = nil
        if !selected { draft.remove(item.url.path + "|" + item.resourceID + "|moveToTrash") }
        else {
            guard scan.exclusionFingerprint == expectedExclusionFingerprint, !isRefreshing, let downloads, retryTargetIDs?.contains(item.url.path + "|" + item.resourceID + "|moveToTrash") != false else { return }
            guard eligible(item, in: scan), scans[scan.scope]?.observedAt == scan.observedAt else { return }
            do {
                let leases = try AppLifecycleController.shared.locations.leases(for: [scan.scope])
                defer { for lease in leases { lease.close() } }
                try draft.select(item, in: scan, downloads: downloads); message = nil
            }
            catch { message = "This target is no longer eligible. Recheck its selected Downloads scope." }
        }
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func remove(_ target: PlannedTarget) {
        guard !isPreparing && !execution.isRunning && !workspaceRunning && !chrome.isRunning else { return }
        approvedBatch = nil
        draft.remove(target.id)
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    private func supportedAlternatives(excluding scope: URL) -> ([ScanResult], [ScopeAccessLease]) {
        var supported: [ScanResult] = [], leases: [ScopeAccessLease] = []
        for scan in scans.values where scan.scope.standardizedFileURL.path != scope.standardizedFileURL.path && scan.isComplete && !unavailableScopes.contains(scan.scope.standardizedFileURL) {
            guard let granted = try? AppLifecycleController.shared.locations.leases(for: [scan.scope]) else { continue }
            leases += granted; supported.append(scan)
        }
        return (supported, leases)
    }
    func dependentSelectionCount(for scope: URL) -> Int {
        let (supported, leases) = supportedAlternatives(excluding: scope)
        defer { for lease in leases { lease.close() } }
        var proposed = draft
        return proposed.rebindUnchangedSelected(removingScope: scope,
            using: supported,
            exclusionFingerprint: expectedExclusionFingerprint).dependentIDs.count
    }
    func suspendScope(_ scope: URL, forget: Bool = false) {
        let request = beginRefresh(scope)
        cancelRefresh(request)
        scans = scans.filter { $0.key.standardizedFileURL.path != scope.standardizedFileURL.path }
        let (supported, leases) = supportedAlternatives(excluding: scope)
        defer { for lease in leases { lease.close() } }
        let proof = draft.rebindUnchangedSelected(removingScope: scope,
            using: supported,
            exclusionFingerprint: expectedExclusionFingerprint)
        refresh.retirePending(after: proof, in: draft)
        if forget { for id in proof.dependentIDs { draft.remove(id) } }
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func deselectUnavailable() {
        for target in draft.selected where refresh.requiresRefresh(target.id) || unavailableSelected.contains(where: { $0.id == target.id }) { remove(target) }
    }
    func startNewPlan() {
        guard !workspaceRunning, !chrome.isRunning else { return }; endSession(); execution.clear(); chrome.endSession(); workspaceFinished = false; workspaceStopRequested = false; workspaceCancellation = nil; workspaceBefore = nil; workspaceAfter = nil; unavailableScopes.removeAll()
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
        let leases: [ScopeAccessLease]
        do { leases = try AppLifecycleController.shared.locations.leases(for: scopes) }
        catch { message = "Renew access to the unfinished files’ locations before rechecking. No retry was created."; return }
        defer { for lease in leases { lease.close() } }
        let cancellation = ScanCancellation(), token = UUID()
        retryCancellation = cancellation; retryGeneration = token
        isPreparing = true; isRetryRechecking = true; message = nil; invalidateReview()
        defer {
            AppLifecycleController.shared.capacity.request(.scanEnded)
            if retryGeneration == token { isPreparing = false; isRetryRechecking = false; retryCancellation = nil }
        }
        let activityEpoch = await ScanActivityHistory.shared.begin()
        guard retryGeneration == token, !cancellation.isCancellationRequested else { return }
        let activity = ActiveScanActivity(roots: scopes, epoch: activityEpoch)
        let observation = await Task.detached(priority: .userInitiated) {
            let scanner = FolderScanner()
            var reports: [ScanResult] = [], failed: [URL] = []
            var stoppedRoot: URL?
            var baselineIDs: [String: UUID] = [:]
            for scope in scopes {
                if cancellation.isCancellationRequested { break }
                let access = scope.startAccessingSecurityScopedResource()
                let growth = await GrowthHistoryModel.shared.begin(scope, exclusionFingerprint: policy.fingerprint)
                do {
                    let scan = try await scanner.scan(scope, cancellation: cancellation, exclusions: policy)
                    reports.append(scan)
                    await GrowthHistoryModel.shared.complete(scan, token: growth)
                    baselineIDs[scope.standardizedFileURL.path] = await MainActor.run { GrowthHistoryModel.shared.retainedBaseline(for: scan) }
                } catch {
                    if cancellation.isCancellationRequested { stoppedRoot = scope }
                    else { failed.append(scope) }
                }
                if access { scope.stopAccessingSecurityScopedResource() }
                if cancellation.isCancellationRequested { break }
            }
            return (reports, failed, stoppedRoot, baselineIDs)
        }.value
        let reports = observation.0
        for scan in reports { activity.observe(scan, baselineID: observation.3[scan.scope.standardizedFileURL.path]) }
        for scope in observation.1 { activity.failed(scope) }
        if cancellation.isCancellationRequested { activity.stopped(observation.2, progress: nil) }
        await ScanActivityHistory.shared.record(activity.summary(stopped: cancellation.isCancellationRequested), epoch: activity.epoch)
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
    func prepareWorkspaceReview() async throws -> WorkspaceCleanupReview {
        guard canReview else { throw PlanSelectionError.ineligible }
        let downloadsVersion = mutationVersion, chromeVersion = chrome.selectionRevision
        let files = draft.selectedCount > 0 ? try draft.review() : nil
        let groups = chrome.selectedCount > 0 ? await chrome.prepareReview() : nil
        guard canReview, mutationVersion == downloadsVersion, chrome.selectionRevision == chromeVersion,
              chrome.selectedCount == 0 || groups != nil else { throw PlanSelectionError.ineligible }
        return WorkspaceCleanupReview(downloads: files, chrome: groups, downloadsVersion: downloadsVersion, chromeVersion: chromeVersion)
    }
    func executeWorkspace(_ review: WorkspaceCleanupReview) async throws {
        guard canReview, mutationVersion == review.downloadsVersion, chrome.selectionRevision == review.chromeVersion else { throw PlanSelectionError.ineligible }
        if let files = review.downloads { try approve(files) }
        let cancellation = CleanupCancellation()
        workspaceCancellation = cancellation; workspaceStopRequested = false
        workspaceRunning = true; workspaceFinished = false
        let lifecycle = AppLifecycleController.shared
        lifecycle.operationInProgress = true
        defer { workspaceRunning = false; workspaceCancellation = nil; lifecycle.operationInProgress = false; lifecycle.hasPendingPlan = hasPendingChoices }
        workspaceBefore = await Task.detached { StartupVolumeCapacity.read() }.value
        if review.downloads != nil {
            await executeApproved(holdingOperationLock: true, cancellation: cancellation)
            // Access failure leaves the exact file choices intact and starts neither action.
            guard draft.selectedCount == 0 else { return }
        }
        if let caches = review.chrome { await chrome.execute(caches, cancellation: cancellation) }
        workspaceAfter = await Task.detached { StartupVolumeCapacity.read() }.value
        workspaceFinished = true
        lifecycle.capacity.request(.cleanupEnded)
    }
    func cancelWorkspace() { workspaceStopRequested = true; workspaceCancellation?.cancel(); execution.cancel(); chrome.cancel() }
    func endSession() { guard !execution.isRunning && !workspaceRunning && !chrome.isRunning else { return }; chrome.endSession(); retryCancellation?.cancel(); retryGeneration = UUID(); retryCancellation = nil; isRetryRechecking = false; isPreparing = false; retryTargetIDs = nil; retryExcludedURLs = []; draft.clear(); scans.removeAll(); unavailableScopes.removeAll(); isRefreshingBatch = false; refresh = RefreshChoices(); refreshRequests.removeAll(); approvedBatch = nil; AppLifecycleController.shared.hasPendingPlan = false }
}

@MainActor @Observable final class CleanupPlanPresentation {
    var search = ""
    var choosingItems = false
    var inspected: FileObservation?
    var offset: CGPoint?
    func reset() { search = ""; choosingItems = false; inspected = nil; offset = nil }
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: SessionPlan
    let recheck: (URL) -> Void
    let stopRefresh: () -> Void
    let chooseDownloads: () -> Void
    var exploreDownloads: (() -> Void)? = nil
    var viewHistory: (() -> Void)? = nil
    var newPlan: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    var backToExplorer: (() -> Void)? = nil
    var backToExplorerTitle = "Back to Explorer"
    var manageLocations: (() -> Void)? = nil
    var scopeMessage: String? = nil
    @Bindable var presentation: CleanupPlanPresentation
    @State private var review: WorkspaceCleanupReview?
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        if selection.workspaceRunning || selection.hasWorkspaceResult {
            VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                let includesChrome = selection.chrome.selectedCount > 0 || selection.chrome.isRunning || selection.chrome.result != nil
                if includesChrome {
                    PageHeader(title: selection.workspaceRunning ? "Running cleanup" : "Cleanup results", subtitle: "Review each action's recorded outcome. Chrome caches are permanently removed; Downloads go to Trash.")
                }
                if selection.execution.isRunning || selection.execution.result != nil || selection.execution.error != nil { CleanupExecutionView(model: selection.execution, retryMessage: selection.message, showsHeader: !includesChrome) }
                if selection.chrome.isRunning { ProgressView("Clearing selected Chrome cache groups…") }
                if let result = selection.chrome.result { ChromeResultsSection(result: result) }
                if selection.chrome.result != nil || selection.chrome.isRunning {
                    SummarySurface {
                        Text("Observed available-space change: " + (selection.workspaceObservedChange.map { ($0 >= 0 ? "+" : "−") + ByteCountFormatter.string(fromByteCount: abs($0), countStyle: .decimal) } ?? "Unknown"))
                        Text("Capacity is sampled separately and may change for other reasons. Cache removal is permanent; Downloads sent to Trash still occupy space.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(StillDesign.Space.page)
        } else {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if let backToExplorer { Button(backToExplorerTitle, systemImage: "chevron.left", action: backToExplorer) }
            PageHeader(title: "Cleanup plan", subtitle: selection.retryTargetIDs == nil ? "Choose categories, adjust items if needed, then review the changes." : "Only rechecked unfinished files are included. Completed successes and new discoveries stay excluded.")
                .padding(.bottom, StillDesign.Space.sm)
            ScanHistoryRecordingNotice()
            SelectionSummary(value: selection.workspaceSelectedSize, detail: selection.chrome.selectedCount == 0 ? "\(StillDesign.files(selection.draft.selectedCount)) selected" : "\(StillDesign.files(selection.draft.selectedCount)) · \(selection.chrome.selectedCount) Chrome groups selected", identifier: "liveSelectionSummary", consequence: selection.chrome.selectedCount == 0 ? "Space stays occupied until Finder empties Trash. Nothing changes before final confirmation." : "Chrome caches are permanently removed and may regrow. Downloads stay occupied in Trash.", title: selection.chrome.selectedCount == 0 ? "Selected for Trash" : "Selected for cleanup")
            if selection.pendingCount > 0 {
                StatusRow(text: "Refresh required · Previous choices retained for \(StillDesign.files(selection.pendingCount)).", symbol: "arrow.clockwise", role: .caution)
                Button("Deselect unavailable files") { selection.deselectUnavailable() }
            }
            if let scopeMessage {
                StatusRow(text: scopeMessage, symbol: "info.circle", role: .caution)
                if let manageLocations { Button("Manage locations", action: manageLocations) }
            }
            ForEach(selection.refresh.notices) { notice in
                StatusRow(text: notice.target.url.lastPathComponent + " · " + notice.message, symbol: "info.circle", role: .caution)
            }
            if !selection.observedDownloadsScopes.isEmpty {
                Text("Inspected coverage: " + selection.observedDownloadsScopes.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .help(selection.observedDownloadsScopes.map(\.path).joined(separator: "\n"))
            }
            if selection.displayedRows.isEmpty {
                CategoryPrerequisite(title: selection.isRefreshing ? "Refreshing…" : selection.overviewDownloadsCoverage == .complete ? "No eligible files" : selection.overviewDownloadsCoverage == .incomplete ? "Refresh required" : "Not scanned",
                    detail: selection.overviewDownloadsCoverage == .complete ? "No eligible files in the inspected Downloads locations." : "Scan included Downloads locations to choose exact files. Other folders are inspection only.",
                    actionTitle: selection.overviewDownloadsCoverage == .notInspected ? "Scan Downloads…" : "Scan Downloads again", enabled: !selection.isRefreshing && !selection.isPreparing, action: chooseDownloads)
            } else {
            CategorySelectionHeader(category: .downloads, state: selection.categoryState,
                                    title: selection.isRefreshing || selection.rows.count != selection.displayedRows.count ? "Downloads · \(StillDesign.files(selection.displayedRows.count)) previously observed" : "Downloads · \(StillDesign.files(selection.rows.count)) eligible",
                                    detail: selection.isRefreshing ? "Refreshing previous observations. Files cannot be selected or approved until checked." : selection.rows.count != selection.displayedRows.count ? "Previous observations include files requiring recheck. Only current eligible files can be selected." : "Move exact files to Trash. Personal files and installers are included only when selected.",
                                    size: selection.displayedLogicalBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown",
                                    enabled: !selection.isPreparing && !selection.isRefreshing && !selection.rows.isEmpty) {
                Task { await selection.toggleAll() }
            }
            if selection.overviewDownloadsCoverage == .incomplete {
                StatusRow(text: selection.rows.isEmpty ? "Previous observations require recheck. Current eligibility and uninspected contents remain unknown." : "Limited coverage · Only current eligible files can be included. Uninspected contents remain unknown.", symbol: "exclamationmark.circle", role: .caution)
            }
            if selection.isPreparing { ProgressView("Checking exact Downloads targets…") }
            if let approved = selection.approvedBatch { Text("Approved batch: \(approved.targets.count) files · No files moved.").foregroundStyle(.secondary) }
            if let approvalError { Text(approvalError).foregroundStyle(.secondary) }
            HStack {
                if let exploreDownloads { Button("Explore Downloads", action: exploreDownloads) }
                Button("Scan Downloads again", action: chooseDownloads).disabled(selection.isRefreshing || selection.isPreparing)
            }
            DisclosureGroup("Choose items", isExpanded: $presentation.choosingItems) {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    TextField("Search Downloads items", text: $presentation.search)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(selection.displayedRows.filter { presentation.search.isEmpty || $0.item.url.path.localizedCaseInsensitiveContains(presentation.search) }) { row in
                            InspectableItemRow(name: row.item.url.lastPathComponent, detail: row.item.url.pathComponents.dropFirst(row.scan.scope.pathComponents.count).joined(separator: "/"), size: ByteCountFormatter.string(fromByteCount: row.item.logicalBytes ?? 0, countStyle: .decimal), symbol: "doc", inspected: presentation.inspected?.id == row.item.id, inspect: { presentation.inspected = row.item }) {
                                Toggle("\(selection.draft.contains(row.item) ? "Selected" : "Select") \(row.item.url.lastPathComponent)", isOn: Binding(get: { selection.draft.contains(row.item) }, set: { selection.set(row.item, in: row.scan, selected: $0) }))
                                    .labelsHidden().disabled(selection.isPreparing || selection.isRefreshing || (!selection.eligible(row.item, in: row.scan) && !selection.draft.contains(row.item)))
                            }
                            if !selection.eligible(row.item, in: row.scan) || selection.refresh.requiresRefresh(row.item.url.path + "|" + row.item.resourceID + "|moveToTrash") {
                                StatusRow(text: selection.isRefreshing ? "Rechecking…" : "Refresh required", symbol: "arrow.clockwise", role: .caution).padding(.horizontal, StillDesign.Space.md)
                            }
                            Divider()
                        }
                    }
                    if let item = presentation.inspected {
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
            }
            ForEach(selection.unavailableOutsideDisplay) { target in
                SettingsRow(title: target.url.lastPathComponent, detail: "Selection retained · Recheck this location before review") {
                    Toggle("Selected \(target.url.lastPathComponent)", isOn: Binding(get: { true }, set: { if !$0 { selection.remove(target) } })).disabled(selection.isPreparing)
                }
            }
            if selection.retryTargetIDs != nil { Button("Review all Downloads…", action: chooseDownloads).disabled(selection.isRefreshing || selection.isPreparing) }
            if let message = selection.message { Text(message).foregroundStyle(.secondary) }
            ForEach(selection.retryExcludedURLs, id: \.path) { url in
                StatusRow(text: "\(url.lastPathComponent): changed or unavailable. Review it through a new scan from Overview.", symbol: "exclamationmark.circle", role: .caution).help(url.path)
            }
            DisclosureGroup("Size and selection details") {
                Text("Logical size describes the selected files, not guaranteed space freed. Linked files count once in the size total; each selected path is a separate target. Hidden search results keep their selections.").font(.caption).foregroundStyle(.secondary)
            }

        }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) { DestinationViewport(offset: $presentation.offset).frame(width: 0, height: 0) }
        }
        }.background(StillDesign.reading)
        if selection.isRetryRechecking {
            ActionStrip(message: "Rechecking unfinished identities. No files are moved.") {
                ProgressView().controlSize(.small)
                Button("Stop recheck") { selection.stopRetryRecheck() }
            }
        } else if selection.workspaceRunning || selection.execution.isRunning {
            ActionStrip(message: "Stopping preserves unstarted work. Completed Trash moves and cache removals are not rolled back.") {
                Button(selection.workspaceStopRequested ? "Stop requested" : "Stop after current file") { selection.cancelWorkspace() }.disabled(selection.workspaceStopRequested)
            }
        } else if selection.hasWorkspaceResult {
            ActionStrip(message: selection.execution.requiresRecoveryReview ? "Review unresolved records before making another plan." : "This run has ended. A new plan requires a fresh manual scan.") {
                if let viewHistory { Button("View history", action: viewHistory) }
                if selection.execution.requiresRecoveryReview, let reviewRecovery { Button("Review recovery", action: reviewRecovery) }
                if selection.execution.canRetry { Button("Recheck unfinished files") { Task { await selection.prepareRetry() } }.disabled(selection.isRefreshing || selection.isPreparing) }
                if let newPlan { Button("Start a new plan", action: newPlan).buttonStyle(.borderedProminent) }
            }
        } else if selection.execution.canRetry {
            ActionStrip(message: "A retry needs a fresh check and new approval; completed successes stay excluded.") {
                Button("Recheck unfinished files") { Task { await selection.prepareRetry() } }.buttonStyle(.borderedProminent).disabled(selection.isRefreshing || selection.isPreparing)
            }
        } else if selection.execution.result == nil && selection.execution.error == nil {
        ActionStrip(message: selection.isRefreshing ? "Review is paused while findings are rechecked." : selection.pendingCount > 0 ? "Refresh required before reviewing the selected files." : "Nothing changes until you confirm the next step.") {
ReviewCleanupButton(enabled: selection.canReview, focusRequest: reviewFocusRequest) {
                Task { do { review = try await selection.prepareWorkspaceReview(); approvalError = nil } catch { approvalError = "Recheck the selected targets before reviewing." } }
            }.fixedSize()
        }
        }
        }
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = "The plan changed. Review the latest targets before approving." } }
            }
        }
        .onAppear { reconcileInspector() }
        .onChange(of: selection.isRefreshing) { _, refreshing in if !refreshing { reconcileInspector() } }
        .onChange(of: selection.scans.values.map(\.observedAt).sorted()) { _, _ in reconcileInspector() }
        .onChange(of: selection.chrome.selectionRevision) { _, _ in if review != nil { review = nil } }
        .onChange(of: selection.mutationVersion) { _, _ in if review != nil { review = nil } }
    }
    private func reconcileInspector() {
        guard !selection.isRefreshing, let old = presentation.inspected else { return }
        presentation.inspected = selection.rows.first { $0.item.id == old.id && $0.item.resourceID == old.resourceID }?.item
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



/// Distinct immutable approvals share presentation, never target authority.
struct WorkspaceCleanupReview: Identifiable {
    let id = UUID()
    let downloads: CleanupReview?
    let chrome: ChromeCacheApproval?
    let downloadsVersion: UInt64
    let chromeVersion: UInt64
}
private struct WorkspaceCleanupConfirmationView: View {
    let review: WorkspaceCleanupReview
    let cancel: () -> Void
    let approve: () -> Void
    var body: some View {
        if review.chrome == nil, let files = review.downloads {
            CleanupConfirmationView(review: files, cancel: cancel, approve: approve)
        } else {
            VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
                PageHeader(title: "Review cleanup", subtitle: "Review each action before making changes.")
                ScrollView {
                    VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                        if let files = review.downloads {
                            Text("Move exact Downloads files to Trash").font(StillDesign.TypeStyle.section)
                            Text("Space stays occupied until Finder empties Trash. No whole folders, new discoveries or permanent-delete fallback.").font(.callout).foregroundStyle(.secondary)
                            ForEach(files.targets) { Text($0.url.path).font(.caption).textSelection(.enabled) }
                            Divider()
                        }
                        if let groups = review.chrome { ChromeConfirmationSection(approval: groups) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); Button("Run cleanup", action: approve).buttonStyle(.borderedProminent) }
            }.padding(StillDesign.Space.xl).frame(width: 640, height: 520).background(StillDesign.reading)
        }
    }
}
