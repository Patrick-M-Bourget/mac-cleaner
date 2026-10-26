import Foundation
import Observation
import StillCore
import SwiftUI

/// A user-scanned location being read again. Its earlier observation is not current until the scan finishes.
struct RefreshRequest: Sendable {
    let id = UUID()
    let scope: URL
}

/// The session's cleanup plan: catalog categories (Downloads and browser caches included).
/// Folder scans are kept for inspection only; they never authorize cleanup.
@MainActor @Observable final class SessionPlan {
    let catalog = CatalogCleanupModel()
    private(set) var workspaceRunning = false
    private(set) var workspaceFinished = false
    private(set) var workspaceStopRequested = false
    private var workspaceCancellation: CleanupCancellation?
    var hasWorkspaceResult: Bool { workspaceFinished || catalog.result != nil }
    var hasPendingChoices: Bool { catalog.selectedCount > 0 }
    var workspaceSelectedCount: Int { catalog.selectedCount }
    var workspaceSelectedSize: String {
        if !hasPendingChoices { return "—" }
        return ByteCountFormatter.string(fromByteCount: catalog.estimatedBytes, countStyle: .decimal)
    }
    /// "X of this goes to Trash", only when the selection includes Trash-bound items (that space stays used until Trash is emptied).
    var workspaceTrashNote: String? {
        catalog.selectedTrashBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) + " of this goes to Trash" }
    }
    /// The last run left records whose outcome is unknown; they must be reviewed before another plan.
    var requiresRecoveryReview: Bool {
        guard let result = catalog.result else { return false }
        return result.rejectedReplay || result.journalFailure != nil || result.records.contains { $0.state == .unknown || $0.state == .intent }
    }
    private(set) var scans: [URL: ScanResult] = [:]
    private(set) var message: String?
    private(set) var unavailableScopes: Set<URL> = []
    var canReview: Bool {
        !AppLifecycleController.shared.maintenanceInProgress && !workspaceRunning
        && (catalog.selectedCount == 0 || catalog.canReview) && hasPendingChoices
    }
    /// Categories with live, reviewable choices, for the sidebar badge.
    var actionableSelectedCategoryCount: Int {
        guard canReview else { return 0 }
        return catalog.selectedRuleCount
    }
    private var expectedExclusionFingerprint = "none"
    func invalidateCoverage() {
        refreshRequests.removeAll(); scans.removeAll()
        catalog.forgetPickedFiles()
        message = "Exclusion settings changed. Recheck selected locations to see the new coverage."
    }
    func expectExclusions(_ fingerprint: String) {
        if expectedExclusionFingerprint != fingerprint { invalidateCoverage(); expectedExclusionFingerprint = fingerprint }
    }
    private var refreshRequests: [URL: RefreshRequest] = [:]
    private var isRefreshingBatch = false
    var isRefreshing: Bool { isRefreshingBatch || !refreshRequests.isEmpty }
    func beginRefreshBatch(_ scopes: [URL]) -> [RefreshRequest] {
        isRefreshingBatch = true
        return scopes.map { beginRefresh($0) }
    }
    func endRefreshBatch(_ unfinished: [RefreshRequest]) {
        for request in unfinished { cancelRefresh(request) }
        isRefreshingBatch = false
    }
    var refreshScopes: [URL] { scans.keys.sorted { $0.path < $1.path } }
    func beginRefresh(_ scope: URL) -> RefreshRequest {
        unavailableScopes.insert(scope.standardizedFileURL)
        let request = RefreshRequest(scope: scope.standardizedFileURL)
        refreshRequests[request.scope] = request
        return request
    }
    func cancelRefresh(_ request: RefreshRequest) {
        guard refreshRequests[request.scope]?.id == request.id else { return }
        refreshRequests[request.scope] = nil
    }
    func finishRefresh(_ request: RefreshRequest, scan: ScanResult) async {
        guard scan.exclusionFingerprint == expectedExclusionFingerprint else { cancelRefresh(request); return }
        guard refreshRequests[request.scope]?.id == request.id else { return }
        if scan.isComplete { unavailableScopes.remove(scan.scope.standardizedFileURL) }
        refreshRequests[request.scope] = nil
    }
    func observe(_ scan: ScanResult) {
        guard scan.exclusionFingerprint == expectedExclusionFingerprint else { return }
        if let newer = scans[scan.scope], newer.observedAt > scan.observedAt { return }
        unavailableScopes.remove(scan.scope.standardizedFileURL)
        scans[scan.scope] = scan
    }
    /// A location was omitted, forgotten or lost access: its observation is no longer current.
    func suspendScope(_ scope: URL) {
        let request = beginRefresh(scope)
        cancelRefresh(request)
        scans = scans.filter { $0.key.standardizedFileURL.path != scope.standardizedFileURL.path }
        catalog.forgetPickedFiles(scope)
    }
    func startNewPlan() {
        guard !workspaceRunning, !catalog.isRunning else { return }
        endSession(); workspaceFinished = false; workspaceStopRequested = false; workspaceCancellation = nil; unavailableScopes.removeAll()
    }
    func prepareWorkspaceReview() async throws -> WorkspaceCleanupReview {
        guard canReview else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision
        let items = catalog.selectedCount > 0 ? await catalog.prepareReview() : nil
        guard canReview, catalog.selectionRevision == catalogVersion, catalog.selectedCount == 0 || items != nil else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: items, catalogVersion: catalogVersion)
    }
    func executeWorkspace(_ review: WorkspaceCleanupReview) async throws {
        guard canReview, catalog.selectionRevision == review.catalogVersion else { throw PlanReviewError.changed }
        let cancellation = CleanupCancellation()
        workspaceCancellation = cancellation; workspaceStopRequested = false
        workspaceRunning = true; workspaceFinished = false
        let lifecycle = AppLifecycleController.shared
        lifecycle.operationInProgress = true
        defer { workspaceRunning = false; workspaceCancellation = nil; lifecycle.operationInProgress = false; lifecycle.hasPendingPlan = hasPendingChoices }
        if let items = review.catalog { await catalog.execute(items.approval, cancellation: cancellation) }
        workspaceFinished = true
        lifecycle.capacity.request(.cleanupEnded)
    }
    func cancelWorkspace() { workspaceStopRequested = true; workspaceCancellation?.cancel(); catalog.cancel() }
    func endSession() {
        guard !workspaceRunning && !catalog.isRunning else { return }
        catalog.endSession(); scans.removeAll(); unavailableScopes.removeAll()
        isRefreshingBatch = false; refreshRequests.removeAll(); AppLifecycleController.shared.hasPendingPlan = false
    }
}
enum PlanReviewError: Error { case changed }

@MainActor @Observable final class CleanupPlanPresentation {
    var search = ""
    var choosingItems = false
    var inspected: FileObservation?
    var offset: CGPoint?
    /// Categories whose "Choose items" is open; opening a category from Overview opens it.
    var expandedCategories: Set<CatalogCategory> = []
    func reset() { search = ""; choosingItems = false; inspected = nil; offset = nil; expandedCategories = [] }
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: SessionPlan
    var viewHistory: (() -> Void)? = nil
    var newPlan: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    var backToExplorer: (() -> Void)? = nil
    var backToExplorerTitle = "Back to Explorer"
    @Bindable var presentation: CleanupPlanPresentation
    @State private var review: WorkspaceCleanupReview?
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        if selection.workspaceRunning || selection.hasWorkspaceResult {
            VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                PageHeader(title: selection.workspaceRunning ? "Running cleanup" : selection.catalog.result?.previewOnly == true ? "Preview results" : "Cleanup results")
                if selection.catalog.isRunning { ProgressView(selection.catalog.previewOnly ? "Checking selected items…" : "Cleaning selected items…") }
                if let result = selection.catalog.result { CatalogResultsSection(result: result, catalog: selection.catalog.catalog) }
                if let message = selection.catalog.message { StatusRow(text: message, symbol: "exclamationmark.triangle", role: .caution) }
            }.padding(StillDesign.Space.page)
        } else {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if let backToExplorer { Button(backToExplorerTitle, systemImage: "chevron.left", action: backToExplorer) }
            PageHeader(title: "Cleanup plan", subtitle: "Choose categories, adjust items if needed, then review the changes.")
                .padding(.bottom, StillDesign.Space.sm)
            ScanHistoryRecordingNotice()
            SelectionSummary(value: selection.workspaceSelectedSize,
                             detail: StillDesign.items(selection.catalog.selectedCount) + " selected",
                             identifier: "liveSelectionSummary", consequence: selection.workspaceTrashNote, title: "Potential space released",
                             consequenceIdentifier: "liveSelectionTrash")
                .help("Sizes are estimates from the scan, not guaranteed space freed. Linked files count once. Each item is checked again just before Still acts on it.")
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution) }
            CatalogPlanSection(model: selection.catalog, expanded: $presentation.expandedCategories)
        }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) { DestinationViewport(offset: $presentation.offset).frame(width: 0, height: 0) }
        }
        }.background(StillDesign.reading)
        if selection.workspaceRunning {
            ActionStrip(message: "Stopping preserves unstarted work. Completed Trash moves and cache removals are not rolled back.") {
                Button(selection.workspaceStopRequested ? "Stop requested" : "Stop after current item") { selection.cancelWorkspace() }.disabled(selection.workspaceStopRequested)
            }
        } else if selection.hasWorkspaceResult {
            ActionStrip(message: selection.requiresRecoveryReview ? "Review unresolved records before making another plan." : nil) {
                if let viewHistory { Button("View history", action: viewHistory) }
                if selection.requiresRecoveryReview, let reviewRecovery { Button("Review recovery", action: reviewRecovery) }
                if let newPlan { Button("Start a new plan", action: newPlan).buttonStyle(.borderedProminent) }
            }
        } else {
            ActionStrip(leading: { PreviewOnlyToggle(model: selection.catalog) }) {
                ReviewCleanupButton(enabled: selection.canReview, focusRequest: reviewFocusRequest) {
                    Task { do { review = try await selection.prepareWorkspaceReview(); approvalError = nil } catch { approvalError = "Your choices changed. Review the latest items and try again." } }
                }.fixedSize()
            }
        }
        }
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = "The plan changed. Review the latest items before approving." } }
            }
        }
        .onChange(of: selection.catalog.selectionRevision) { _, _ in if review != nil { review = nil } }
    }
}

/// Distinct immutable approvals share presentation, never target authority.
struct WorkspaceCleanupReview: Identifiable {
    let id = UUID()
    let catalog: CatalogReview?
    let catalogVersion: UInt64
}
private struct WorkspaceCleanupConfirmationView: View {
    let review: WorkspaceCleanupReview
    let cancel: () -> Void
    let approve: () -> Void
    /// Only catalog actions are selected and Preview only is on, so nothing will change.
    private var previewOnlyRun: Bool { review.catalog?.approval.previewOnly == true }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            PageHeader(title: "Review your changes", subtitle: "Check what each action does. You can go back and change your selection.")
            ScrollView {
                VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                    if let items = review.catalog { CatalogConfirmationSection(review: items, catalog: Catalog(rules: BuiltInCatalog.rules)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); Button(previewOnlyRun ? "Run preview" : "Run cleanup", action: approve).buttonStyle(.borderedProminent) }
        }.padding(StillDesign.Space.xl).frame(width: 640, height: 520).background(StillDesign.reading)
    }
}
