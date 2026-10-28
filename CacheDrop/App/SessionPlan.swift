import Foundation
import Observation
import CacheDropCore
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
    /// The selection the running or last finished cleanup came from; only its page shows the run (#141).
    private(set) var runSource = CleanupSelections.Source.plan
    func showsRun(for source: CleanupSelections.Source) -> Bool { runSource == source && (workspaceRunning || hasWorkspaceResult) }
    var hasPendingChoices: Bool { catalog.selectedCount > 0 }
    /// Choices on the plan or the Applications page, which quitting would lose (#270).
    var hasPendingChoicesOnAnyPage: Bool { catalog.anyPageDiffersFromRecommended }
    var workspaceSelectedCount: Int { catalog.selectedCount }
    var workspaceSelectedSize: String {
        if !hasPendingChoices { return "—" }
        return ByteCountFormatter.string(fromByteCount: catalog.estimatedBytes, countStyle: .decimal)
    }
    /// "X of this goes to Trash", only when the selection includes Trash-bound items (that space stays used until Trash is emptied).
    var workspaceTrashNote: String? {
        CacheDropDesign.goesToTrash(catalog.selectedCandidates)
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
        message = "Protected items changed. Scan again to see what’s offered now."
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
    /// Nothing blocks a review: no maintenance, no cleanup running, and the catalog can be edited.
    private var canStartReview: Bool { !AppLifecycleController.shared.maintenanceInProgress && !workspaceRunning && catalog.canEdit }
    /// Whether a Smart clean can be reviewed: nothing else is running and the catalog can be edited.
    var canReviewSmartClean: Bool { canStartReview && !catalog.smartCleanCandidates.isEmpty }
    /// Whether the Applications page's chosen leftovers can be reviewed (Decision 51).
    var canReviewApplications: Bool { canStartReview && !catalog.applicationsSelected.isEmpty }
    /// Whether the page `source` can be reviewed and cleaned now.
    func canReview(_ source: CleanupSelections.Source) -> Bool {
        switch source { case .plan: canReview; case .smartClean: canReviewSmartClean; case .applications: canReviewApplications }
    }
    /// A page's Review cleanup or Clean up is running its click-time checks (#308): the button shows it is busy and
    /// ignores more clicks until they end.
    private(set) var isCheckingReview = false
    /// Runs one page's click-time checks; nil when another page's are already running.
    func checkingReview(_ prepare: () async throws -> WorkspaceCleanupReview) async throws -> WorkspaceCleanupReview? {
        guard !isCheckingReview else { return nil }
        isCheckingReview = true
        defer { isCheckingReview = false }
        return try await prepare()
    }
    /// Smart clean's review (#141): its own selection, checked now, through the same review and executor as the plan.
    func prepareSmartCleanReview() async throws -> WorkspaceCleanupReview {
        guard canReviewSmartClean else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision(for: .smartClean)
        guard let items = await catalog.smartCleanCheckedNow() else { throw failure }
        guard !items.isEmpty else { throw PlanReviewError.nothingToClean }
        return try await review(items, from: .smartClean, catalogVersion: catalogVersion)
    }
    /// The Applications page's review: its chosen items, through the plan's review and executor.
    func prepareApplicationsReview() async throws -> WorkspaceCleanupReview {
        guard canReviewApplications else { throw PlanReviewError.changed }
        return try await review(catalog.applicationsSelected, from: .applications, catalogVersion: catalog.selectionRevision(for: .applications))
    }
    /// A page's review of `items` through the plan's review, refused when the page's choices changed meanwhile.
    private func review(_ items: [Candidate], from source: CleanupSelections.Source, catalogVersion: UInt64) async throws -> WorkspaceCleanupReview {
        let review = await catalog.prepareReview(of: items)
        guard let review else { throw failure }
        guard canReview(source), catalog.selectionRevision(for: source) == catalogVersion else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: review, catalogVersion: catalogVersion, source: source)
    }
    func prepareWorkspaceReview() async throws -> WorkspaceCleanupReview {
        guard canReview else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision(for: .plan)
        let items = catalog.selectedCount > 0 ? await catalog.prepareReview() : nil
        if catalog.selectedCount > 0, items == nil, catalog.settingsUnreadable { throw PlanReviewError.settingsUnreadable }
        guard canReview, catalog.selectionRevision(for: .plan) == catalogVersion, catalog.selectedCount == 0 || items != nil else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: items, catalogVersion: catalogVersion)
    }
    /// Why a review couldn't be built: the settings couldn't be read, or the choices changed meanwhile.
    private var failure: PlanReviewError { catalog.settingsUnreadable ? .settingsUnreadable : .changed }
    func executeWorkspace(_ review: WorkspaceCleanupReview) async throws {
        guard canReview(review.source), catalog.selectionRevision(for: review.source) == review.catalogVersion else { throw PlanReviewError.changed }
        await run(review)
        // A run empties the catalog, so CacheDrop scans again by itself, whichever page is open (#306).
        await catalog.rescan()
    }
    private func run(_ review: WorkspaceCleanupReview) async {
        runSource = review.source
        let cancellation = CleanupCancellation()
        workspaceCancellation = cancellation; workspaceStopRequested = false
        workspaceRunning = true; workspaceFinished = false
        let lifecycle = AppLifecycleController.shared
        lifecycle.operationInProgress = true
        defer { workspaceRunning = false; workspaceCancellation = nil; lifecycle.operationInProgress = false; lifecycle.hasPendingPlan = hasPendingChoicesOnAnyPage }
        if let items = review.catalog { await catalog.execute(items.approval, cancellation: cancellation) }
        workspaceFinished = true
        lifecycle.capacity.request(.cleanupEnded)
    }
    /// Leaves a finished Smart clean's results; the Cleanup plan's selection is kept (#141).
    func dismissResult() {
        guard !workspaceRunning, !catalog.isRunning else { return }
        workspaceFinished = false; catalog.dismissResult()
    }
    func cancelWorkspace() { workspaceStopRequested = true; workspaceCancellation?.cancel(); catalog.cancel() }
    func endSession() {
        guard !workspaceRunning && !catalog.isRunning else { return }
        catalog.endSession(); scans.removeAll(); unavailableScopes.removeAll()
        isRefreshingBatch = false; refreshRequests.removeAll(); AppLifecycleController.shared.hasPendingPlan = hasPendingChoicesOnAnyPage
    }
}
enum PlanReviewError: Error {
    case changed, nothingToClean
    /// The Protected items settings couldn't be read; the page shows `SettingsUnreadableNotice` instead (#310).
    case settingsUnreadable
    /// What every page that cleans says when its choices changed before or under its review sheet (#307).
    static let changedMessage = "Your choices changed. Check the items and try again."
    /// The page's line for a review that couldn't open; nil when `SettingsUnreadableNotice` already says why (#310).
    static func message(for error: Error) -> String? {
        switch error as? PlanReviewError {
        case .settingsUnreadable: nil
        case .nothingToClean: "Nothing here can be cleaned right now. Scan again."
        default: changedMessage
        }
    }
}

@MainActor @Observable final class CleanupPlanPresentation {
    var search = ""
    var choosingItems = false
    var inspected: FileObservation?
    var offset: CGPoint?
    /// Categories whose "Choose items" is open; opening a category from Overview opens it.
    var expandedCategories: Set<CatalogCategory> = []
    func reset() { search = ""; choosingItems = false; inspected = nil; offset = nil; expandedCategories = [] }
}

/// Smart clean's open categories (#219): its own, separate from the plan's, kept until CacheDrop quits. Categories start collapsed.
@MainActor @Observable final class SmartCleanPresentation {
    var expandedCategories: Set<CatalogCategory> = []
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: SessionPlan
    var viewHistory: (() -> Void)? = nil
    var newPlan: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    var backToExplorer: (() -> Void)? = nil
    var backToExplorerDestination = "Explore storage"
    @Bindable var presentation: CleanupPlanPresentation
    /// Where the plan's empty state leads (#321).
    var exploreStorage: (() -> Void)? = nil
    @State private var review: WorkspaceCleanupReview?
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        if selection.showsRun(for: .plan) {
            CleanupRunSection(selection: selection)
        } else {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: "Cleanup plan", subtitle: "Choose categories, adjust items if needed, then review the changes.",
                       back: backToExplorer.map { BackButton(destination: backToExplorerDestination, action: $0) })
                .padding(.bottom, CacheDropDesign.Space.sm)
            ScanHistoryRecordingNotice()
            SelectionSummary(value: selection.workspaceSelectedSize,
                             detail: CacheDropDesign.items(selection.catalog.selectedCount) + " selected",
                             identifier: "liveSelectionSummary", consequence: selection.workspaceTrashNote, title: "Potential space released",
                             consequenceIdentifier: "liveSelectionTrash")
                .help("Sizes are estimates from the scan, not guaranteed space freed. Linked files count once. Each item is checked again just before CacheDrop acts on it.")
            SettingsUnreadableNotice(model: selection.catalog)
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution) }
            CatalogPlanSection(model: selection.catalog, expanded: $presentation.expandedCategories, exploreStorage: exploreStorage)
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) { DestinationViewport(offset: $presentation.offset).frame(width: 0, height: 0) }
        }
        }.background(CacheDropDesign.reading)
        CleanupActionBar(selection: selection, source: .plan, viewHistory: viewHistory, reviewRecovery: reviewRecovery) {
            if let newPlan { Button("Start a new plan", action: newPlan).buttonStyle(.borderedProminent) }
        } idle: {
            BusyAction(busy: selection.isCheckingReview) {
                ReviewCleanupButton(enabled: selection.canReview && !selection.isCheckingReview, focusRequest: reviewFocusRequest,
                                    tooltip: selection.catalog.isScanning ? CacheDropDesign.waitForScanHelp : nil) { Task { await openReview() } }.fixedSize()
            }
        }
        }
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: selection.catalog.selectionRevision(for: .plan)) { _, _ in if review != nil { review = nil; approvalError = PlanReviewError.changedMessage } }
    }
    private func openReview() async {
        do {
            guard let checked = try await selection.checkingReview(selection.prepareWorkspaceReview) else { return }
            review = checked; approvalError = nil
        } catch { approvalError = PlanReviewError.message(for: error) }
    }
}

/// Distinct immutable approvals share presentation, never target authority.
struct WorkspaceCleanupReview: Identifiable {
    let id = UUID()
    let catalog: CatalogReview?
    let catalogVersion: UInt64
    /// The selection it came from; a finished run clears only that one (#141).
    var source = CleanupSelections.Source.plan
}
/// A running or finished cleanup, from either selection: the header, progress and outcomes.
struct CleanupRunSection: View {
    let selection: SessionPlan
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: selection.workspaceRunning ? "Cleaning up…" : "Cleanup results")
            if selection.catalog.isRunning { ProgressView(selection.catalog.dryRun ? "Checking selected items…" : "Cleaning selected items…") }
            if let result = selection.catalog.result { CatalogResultsSection(result: result, catalog: selection.catalog.catalog) }
            if let message = selection.catalog.message { StatusRow(text: message, symbol: "exclamationmark.triangle", role: .caution) }
            SettingsUnreadableNotice(model: selection.catalog)
        }.padding(CacheDropDesign.Space.page)
    }
}
/// The bottom bar of a page that cleans (Decision 46): Stop while its run goes, the result's buttons after it, and the
/// page's own actions otherwise. `finish` is the result's last button: Done, or Start a new plan.
struct CleanupActionBar<Finish: View, Idle: View>: View {
    let selection: SessionPlan
    let source: CleanupSelections.Source
    var viewHistory: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    /// The idle bar's note, such as how many items are ticked (#295).
    var idleNote: String? = nil
    @ViewBuilder var finish: () -> Finish
    @ViewBuilder var idle: () -> Idle
    var body: some View {
        if selection.showsRun(for: source) && selection.workspaceRunning {
            CleanupStopStrip(selection: selection)
        } else if selection.showsRun(for: source) {
            ActionStrip(message: selection.requiresRecoveryReview ? recoveryNote : nil) {
                if let viewHistory { Button("View history", action: viewHistory) }
                if selection.requiresRecoveryReview, let reviewRecovery { Button("Review interrupted cleanup", action: reviewRecovery) }
                finish()
            }
        } else {
            ActionStrip(message: idleNote) { idle() }
        }
    }
    private var recoveryNote: String {
        source == .plan ? "Review the interrupted cleanup before making another plan." : "Review the interrupted cleanup before cleaning again."
    }
}
/// The running cleanup's one action.
struct CleanupStopStrip: View {
    let selection: SessionPlan
    var body: some View {
        ActionStrip(message: "Stopping won’t undo what’s done. A tool stopped midway may have removed part of its cache.", showsBackgroundWork: false, wrapsNote: true) {
            Button(selection.workspaceStopRequested ? "Stop requested" : "Stop cleanup") { selection.cancelWorkspace() }.disabled(selection.workspaceStopRequested)
        }
    }
}
struct WorkspaceCleanupConfirmationView: View {
    let review: WorkspaceCleanupReview
    let cancel: () -> Void
    let approve: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: "Review your changes", subtitle: "Check what each action does. You can go back and change your selection.")
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                    if let items = review.catalog { CatalogConfirmationSection(review: items, catalog: Catalog(rules: BuiltInCatalog.rules)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            SheetFooter { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Button("Clean up", action: approve).buttonStyle(.borderedProminent) }
        }.padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetWide.width, height: CacheDropDesign.Size.sheetWide.height).background(CacheDropDesign.reading).cacheDropButtonRule()
    }
}
