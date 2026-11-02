import Foundation
import os
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
@MainActor @Observable final class CleanupPlan {
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
    var workspaceSelectedSize: String {
        if !hasPendingChoices { return CacheDropDesign.noValue }
        return catalog.sizeText(of: catalog.selectedCandidates.filter(\.releasesSpace))
    }
    /// The last run left records whose outcome is unknown; they must be reviewed before another plan.
    var requiresRecoveryReview: Bool {
        guard let result = catalog.result else { return false }
        return result.rejectedReplay || result.journalFailure != nil || result.records.contains { $0.state == .unknown || $0.state == .intent }
    }
    private(set) var scans: [URL: ScanResult] = [:]
    private(set) var unavailableScopes: Set<URL> = []
    var canReview: Bool {
        !AppLifecycleController.shared.updateInstallation.blocksNewWork && !AppLifecycleController.shared.maintenanceInProgress && !workspaceRunning
        && (catalog.selectedCount == 0 || catalog.canReview) && hasPendingChoices
    }
    /// Categories with live, reviewable choices, for the sidebar badge.
    var actionableSelectedCategoryCount: Int {
        guard canReview else { return 0 }
        return catalog.selectedCategoryCount
    }
    private var expectedProtectedItemsFingerprint = "none"
    func invalidateCoverage() {
        refreshRequests.removeAll(); scans.removeAll()
        catalog.forgetPickedFiles()
    }
    func expectProtectedItems(_ fingerprint: String) {
        if expectedProtectedItemsFingerprint != fingerprint { invalidateCoverage(); expectedProtectedItemsFingerprint = fingerprint }
    }
    private var refreshRequests: [URL: RefreshRequest] = [:]
    func beginRefreshBatch(_ scopes: [URL]) -> [RefreshRequest] {
        return scopes.map { beginRefresh($0) }
    }
    func endRefreshBatch(_ unfinished: [RefreshRequest]) {
        for request in unfinished { cancelRefresh(request) }
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
        guard scan.exclusionFingerprint == expectedProtectedItemsFingerprint else { cancelRefresh(request); return }
        guard refreshRequests[request.scope]?.id == request.id else { return }
        if scan.isComplete { unavailableScopes.remove(scan.scope.standardizedFileURL) }
        refreshRequests[request.scope] = nil
    }
    func observe(_ scan: ScanResult) {
        guard scan.exclusionFingerprint == expectedProtectedItemsFingerprint else { return }
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
    /// Nothing blocks a review: no maintenance, no cleanup running, and the catalog can be edited, or `items` chosen (Decision 123).
    private func canStartReview(_ items: [Candidate]? = nil) -> Bool {
        !AppLifecycleController.shared.maintenanceInProgress && !workspaceRunning && (items.map(catalog.canChoose) ?? catalog.canEdit)
    }
    /// Whether a Smart clean can be reviewed: nothing else is running and the catalog can be edited.
    var canReviewSmartClean: Bool { canStartReview() && !catalog.smartCleanCandidates.isEmpty }
    /// Whether the Applications page's chosen leftovers can be reviewed (Decision 51).
    /// During a rescan that keeps its apps and plug-ins too, unless files from deleted apps are ticked (Decision 123); Clean up
    /// still waits for the scan.
    var canReviewApplications: Bool { let items = catalog.applicationsSelected; return !items.isEmpty && canStartReview(items) }
    /// Whether the page `source` can be reviewed and cleaned now.
    func canReview(_ source: CleanupSelections.Source) -> Bool {
        switch source { case .plan: canReview; case .smartClean: canReviewSmartClean; case .applications: canReviewApplications }
    }
    /// The open review sheet, from the click to Clean up (Decision 126, #463): it opens at once with the click-time checks
    /// running in it, and Clean up has nothing to run until they finish for the same choices.
    private(set) var reviewOpening = ReviewOpening<WorkspaceCleanupReview>()
    /// A page's click-time checks are running (#308): its button shows it is busy and ignores more clicks until they end.
    var isCheckingReview: Bool { reviewOpening.isChecking }
    private var reviewChecks: Task<WorkspaceCleanupReview, any Error>?
    /// Opens `source`'s review sheet at once and runs its click-time checks in it. True once its review is ready; false when
    /// another sheet is open or this one closed first. Throws why it closed: the checks' own error, or the choices changed.
    func openReview(_ source: CleanupSelections.Source, checks prepare: @escaping @MainActor () async throws -> WorkspaceCleanupReview) async throws -> Bool {
        guard let attempt = reviewOpening.open(source, revision: catalog.selectionRevision(for: source)) else { return false }
        ReviewSignposts.clicked()
        let checks = Task { @MainActor in
            #if DEBUG
            await Self.reviewPauseForTests()
            #endif
            try Task.checkCancellation()
            return try await ReviewSignposts.interval("Review checks") { try await prepare() }
        }
        reviewChecks = checks
        let result = await checks.result
        if reviewChecks == checks { reviewChecks = nil }
        let outcome = reviewOpening.finish(attempt, with: result, revision: catalog.selectionRevision(for: source))
        if outcome != .ready, outcome != .dropped { ReviewSignposts.closed() }
        switch outcome {
        case .ready: return true
        case .dropped: return false
        case .choicesChanged: throw PlanReviewError.changed
        case .failed: _ = try result.get(); throw PlanReviewError.changed
        }
    }
    /// Lets `reviewSheet(for:)` be shown and closed by the page; Cancel and Clean up close it too, and running checks stop.
    func reviewSheet(for source: CleanupSelections.Source) -> Binding<Bool> {
        Binding(get: { self.reviewOpening.isOpen(for: source) }, set: { if !$0 { self.closeReview() } })
    }
    func closeReview() { reviewOpening.close(); reviewChecks?.cancel(); reviewChecks = nil; ReviewSignposts.closed() }
    /// `source`'s choices moved: its open sheet, checking or ready, closes, and true says the page should say so (Decision 54).
    func reviewChoicesChanged(_ source: CleanupSelections.Source) -> Bool {
        guard reviewOpening.choicesChanged(source, to: catalog.selectionRevision(for: source)) else { return false }
        reviewChecks?.cancel(); reviewChecks = nil; ReviewSignposts.closed()
        return true
    }
    #if DEBUG
    /// A disposable test run can hold the review's click-time checks open (`CACHEDROP_TEST_REVIEW_PAUSE`, seconds, at most 10),
    /// so a UI journey sees the sheet checking (#463). Closing the sheet ends the wait. Never set outside tests.
    private static func reviewPauseForTests() async {
        guard LocalStateLocation.isDisposableTest, let pause = ProcessInfo.processInfo.environment["CACHEDROP_TEST_REVIEW_PAUSE"].flatMap(Double.init), pause > 0 else { return }
        try? await Task.sleep(for: .seconds(min(pause, 10)))
    }
    #endif
    /// Smart clean's review: the recommended part of the shared selection, checked now through the plan's review and executor (Decision 67).
    func prepareSmartCleanReview() async throws -> WorkspaceCleanupReview {
        guard canReviewSmartClean else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision(for: .smartClean)
        // A sheet closed while Smart clean's items were checked skips the review's own pass (#463).
        return try await ReviewCheckSteps.run({ await catalog.smartCleanCheckedNow() }, then: { checked in
            guard let checked else { throw failure }
            guard !checked.items.isEmpty else { throw PlanReviewError.nothingToClean }
            return try await review(checked.items, from: .smartClean, catalogVersion: catalogVersion, check: checked.check)
        })
    }
    /// The Applications page's review: its chosen items, through the plan's review and executor.
    func prepareApplicationsReview() async throws -> WorkspaceCleanupReview {
        guard canReviewApplications else { throw PlanReviewError.changed }
        return try await review(catalog.applicationsSelected, from: .applications, catalogVersion: catalog.selectionRevision(for: .applications))
    }
    /// A page's review of `items` through the plan's review, refused when the page's choices changed meanwhile.
    private func review(_ items: [Candidate], from source: CleanupSelections.Source, catalogVersion: UInt64, check: CandidateCheck? = nil) async throws -> WorkspaceCleanupReview {
        let review = try await catalog.prepareReview(of: items, using: check)
        guard let review else { throw failure }
        guard canReview(source), catalog.selectionRevision(for: source) == catalogVersion else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: review, catalogVersion: catalogVersion, source: source, model: catalog)
    }
    func prepareWorkspaceReview() async throws -> WorkspaceCleanupReview {
        guard canReview else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision(for: .plan)
        let items = catalog.selectedCount > 0 ? try await catalog.prepareReview() : nil
        if catalog.selectedCount > 0, items == nil, catalog.settingsUnreadable { throw PlanReviewError.settingsUnreadable }
        guard canReview, catalog.selectionRevision(for: .plan) == catalogVersion, catalog.selectedCount == 0 || items != nil else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: items, catalogVersion: catalogVersion, model: catalog)
    }
    /// Why a review couldn't be built: the settings couldn't be read, or the choices changed meanwhile.
    private var failure: PlanReviewError { catalog.settingsUnreadable ? .settingsUnreadable : .changed }
    func executeWorkspace(_ review: WorkspaceCleanupReview) async throws {
        // A review opened during a rescan (Decision 123) runs only once the scan ends.
        guard canReview(review.source), !catalog.isScanning, catalog.selectionRevision(for: review.source) == review.catalogVersion else { throw PlanReviewError.changed }
        // A plan bigger than what the trial has left never runs (Decision 137); the review sheet already said so.
        if let items = review.catalog, !AppLifecycleController.shared.cleanupAllowance.permits(
            items.approval.trialBytes(skipping: Set(items.refusals.keys), catalog: catalog.catalog), dryRun: items.approval.dryRun) { throw PlanReviewError.changed }
        await run(review)
        // CacheDrop scans again by itself, whichever page is open (#306); the pages keep the rows the run left, dimmed, until it ends (#375),
        // except Applications' apps and plug-ins when the run changed none of them (Decision 123).
        await catalog.rescanAfterRun()
    }
    private func run(_ review: WorkspaceCleanupReview) async {
        runSource = review.source
        let cancellation = CleanupCancellation()
        workspaceCancellation = cancellation; workspaceStopRequested = false
        workspaceRunning = true; workspaceFinished = false
        let lifecycle = AppLifecycleController.shared
        lifecycle.operationInProgress = true
        defer { workspaceRunning = false; workspaceCancellation = nil; lifecycle.operationInProgress = false; lifecycle.hasPendingPlan = hasPendingChoicesOnAnyPage }
        if let items = review.catalog {
            await catalog.execute(items.approval, cancellation: cancellation)
            // What the run removed or moved to the Trash counts toward the trial (Decision 137).
            if let result = catalog.result, result.batchID == items.approval.id { lifecycle.trial.record(result, of: items.approval, catalog: catalog.catalog) }
        }
        workspaceFinished = true
        lifecycle.capacity.request(.cleanupEnded)
    }
    /// Leaves a finished run's results; the shared selection already excludes the items the run cleaned (#349).
    func dismissResult() {
        guard !workspaceRunning, !catalog.isRunning else { return }
        workspaceFinished = false; catalog.dismissResult()
    }
    func cancelWorkspace() { workspaceStopRequested = true; workspaceCancellation?.cancel(); catalog.cancel() }
    func endSession() {
        guard !workspaceRunning && !catalog.isRunning else { return }
        catalog.endSession(); scans.removeAll(); unavailableScopes.removeAll()
        refreshRequests.removeAll(); AppLifecycleController.shared.hasPendingPlan = hasPendingChoicesOnAnyPage
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
        default: changedMessage
        }
    }
}

/// Scrolls the plan to `presentation.scrollTarget` once its row is drawn, after the viewport settles (#351). A target the
/// plan can't show now (a run's results, or nothing found there) is dropped, so it never jumps the plan later.
private struct PlanScrollTarget: ViewModifier {
    let selection: CleanupPlan
    let presentation: CleanupPlanPresentation
    let proxy: ScrollViewProxy
    func body(content: Content) -> some View {
        content.onAppear(perform: scroll)
            .onChange(of: presentation.scrollTarget) { _, _ in scroll() }
            .onChange(of: selection.catalog.hasScanned) { _, _ in scroll() }
    }
    private func scroll() {
        guard let target = presentation.scrollTarget, selection.catalog.hasScanned else { return }
        presentation.scrollTarget = nil
        guard !selection.showsRun(for: .plan), selection.catalog.plans(target) else { return }
        DispatchQueue.main.async { withAnimation(nil) { proxy.scrollTo(target, anchor: .top) } }
    }
}

@MainActor @Observable final class CleanupPlanPresentation {
    var sort = ListSort()
    var offset: CGPoint?
    /// Categories whose "Choose items" is open; opening a category from Overview opens it.
    var expandedCategories: Set<CatalogCategory> = []
    /// A category to bring into view once the plan shows it (#351); cleared once scrolled to.
    var scrollTarget: CatalogCategory?
    func reset() { offset = nil; expandedCategories = []; scrollTarget = nil }
    /// Opens `category` and scrolls to it, instead of restoring where the plan was left (#351).
    func reveal(_ category: CatalogCategory) { expandedCategories.insert(category); scrollTarget = category; offset = nil }
}

/// Smart clean's open categories (#219): its own, separate from the plan's, kept until CacheDrop quits. Categories start collapsed.
@MainActor @Observable final class SmartCleanPresentation {
    var sort = ListSort()
    var expandedCategories: Set<CatalogCategory> = []
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: CleanupPlan
    var viewHistory: (() -> Void)? = nil
    var newPlan: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    var backToExplorer: (() -> Void)? = nil
    var backToExplorerDestination = "Explore storage"
    @Bindable var presentation: CleanupPlanPresentation
    /// Where the plan's empty state leads (#321).
    var exploreStorage: (() -> Void)? = nil
    /// Opens Applications, where files from deleted apps are chosen (#481).
    var openApplications: (() -> Void)? = nil
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    var body: some View {
        VStack(spacing: 0) {
        ScrollViewReader { proxy in
        ScrollView {
        if selection.showsRun(for: .plan) {
            CleanupRunSection(selection: selection, reveal: proxy.revealRow)
        } else {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: "Cleanup plan", subtitle: "Choose categories, adjust items if needed, then review the changes.",
                       back: backToExplorer.map { BackButton(destination: backToExplorerDestination, action: $0) })
                .padding(.bottom, CacheDropDesign.Space.sm)
            ScanHistoryRecordingNotice()
            SelectionSummary(value: selection.workspaceSelectedSize,
                             detail: CacheDropDesign.items(selection.catalog.selectedCount) + " selected",
                             identifier: "liveSelectionSummary", title: "Ready to clean", elsewhere: applicationsLink)
                .help(CacheDropDesign.selectionEstimateHelp)
            SettingsUnreadableNotice(model: selection.catalog)
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution) }
            CatalogPlanSection(model: selection.catalog, expanded: $presentation.expandedCategories, sort: $presentation.sort, exploreStorage: exploreStorage)
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) { DestinationViewport(offset: $presentation.offset).frame(width: 0, height: 0) }
        }
        }.background(CacheDropDesign.reading).modifier(PlanScrollTarget(selection: selection, presentation: presentation, proxy: proxy))
        }
        CleanupActionBar(selection: selection, source: .plan, viewHistory: viewHistory, reviewRecovery: reviewRecovery) {
            if let newPlan { Button("Start a new plan", action: newPlan).buttonStyle(.borderedProminent) }
        } idle: {
            BusyAction(busy: selection.isCheckingReview) {
                ReviewCleanupButton(enabled: selection.canReview && !selection.isCheckingReview, focusRequest: reviewFocusRequest,
                                    tooltip: selection.catalog.isScanning ? CacheDropDesign.waitForScanHelp : nil) { Task { await openReview() } }.fixedSize()
            }
        }
        }
        .sheet(isPresented: selection.reviewSheet(for: .plan), onDismiss: { reviewFocusRequest += 1 }) {
            ReviewSheet(selection: selection) { snapshot in
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: selection.catalog.selectionRevision(for: .plan)) { _, _ in if selection.reviewChoicesChanged(.plan) { approvalError = PlanReviewError.changedMessage } }
    }
    /// The shared selection's part on Applications, which the plan's count leaves out (#481): Smart clean counts it too.
    private var applicationsLink: (title: String, open: () -> Void)? {
        let count = selection.catalog.applicationsSelected.count
        guard count > 0, let openApplications else { return nil }
        return ("\(count) on Applications", openApplications)
    }
    private func openReview() async {
        do {
            guard try await selection.openReview(.plan, checks: selection.prepareWorkspaceReview) else { return }
            approvalError = nil
        } catch { approvalError = PlanReviewError.message(for: error) }
    }
}

/// Distinct immutable approvals share presentation, never target authority.
struct WorkspaceCleanupReview: Identifiable {
    let id = UUID()
    let catalog: CatalogReview?
    let catalogVersion: UInt64
    /// The page that opened the review; cleaned items leave the shared selection on every page (#349).
    var source = CleanupSelections.Source.plan
    /// Checks the rows again after the review quit an app (#377).
    weak var model: CatalogCleanupModel?
}
/// A running or finished cleanup from any page: the header, progress and outcomes.
struct CleanupRunSection: View {
    let selection: CleanupPlan
    /// Scrolls the page to a result row (`ScrollViewProxy.revealRow`).
    var reveal: (CleanupRecord.ID) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: selection.workspaceRunning ? "Cleaning up…" : "Results")
            if selection.catalog.isRunning {
                if let progress = selection.catalog.runProgress { running(progress) }
                else { ProgressView(selection.catalog.dryRun ? "Checking selected items…" : "Cleaning selected items…") }
            }
            if let result = selection.catalog.result {
                CatalogResultsSection(result: result, catalog: selection.catalog.catalog, settling: selection.catalog.isSettling(result),
                                      settledLine: selection.catalog.settledLine(for: result), reveal: reveal)
            }
            if let message = selection.catalog.message { StatusRow(text: message, symbol: "exclamationmark.triangle", role: .caution) }
            SettingsUnreadableNotice(model: selection.catalog)
        }.padding(CacheDropDesign.Space.page)
    }
}
extension CleanupRunSection {
    /// Variant A (#355): Overview's startup volume card, its bar shaving down at the tip as items finish, a tag at the tip
    /// saying what the run freed (the card's footer says it instead with Reduce Motion), and the run's categories below.
    @ViewBuilder fileprivate func running(_ progress: CleanupRunProgress) -> some View {
        card(progress)
        categories(progress)
    }
    /// The card. A dry run's bar stays still: nothing is released, only counted.
    @ViewBuilder private func card(_ progress: CleanupRunProgress) -> some View {
        let dryRun = selection.catalog.dryRun, said = Self.freed(progress, dryRun: dryRun)
        if let capacity = selection.catalog.runCapacity {
            let used = dryRun ? capacity.usedAtStart : max(0, capacity.usedAtStart - progress.releasedBytes)
            VolumeSummary(available: capacity.total - used, total: capacity.total, observation: reduceMotion ? said ?? "" : "",
                          breakdown: progress.breakdown(usedAtStart: capacity.usedAtStart, total: capacity.total,
                                                        trash: TrashModel.shared.contents ?? .unknown, releasing: !dryRun),
                          tipLabel: reduceMotion ? nil : said ?? "")
                .accessibilityElement(children: .contain).accessibilityIdentifier("cleaningUpCard")
        } else if let said {
            Text(said).font(CacheDropDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier("cleaningUpFreed")
        }
    }
    private func categories(_ progress: CleanupRunProgress) -> some View {
        let dryRun = selection.catalog.dryRun
        return RecommendationGroup {
            ForEach(Array(progress.categories.enumerated()), id: \.offset) { index, category in
                if index > 0 { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }
                StorageReviewRow(category: category.category.storageCategory, title: category.category.overviewTitle, detail: "",
                                 value: Self.value(category), meaning: Self.meaning(category, dryRun: dryRun),
                                 identifier: "cleaningUpCategory-" + category.category.rawValue, mutedValue: category.state == .waiting)
            }
        }
    }
    /// What the run has done so far: what it freed, or else what it moved to the Trash (Decision 69: that frees nothing
    /// until the Trash is emptied); nil before anything finished. A dry run says what it would do.
    fileprivate static func freed(_ progress: CleanupRunProgress, dryRun: Bool) -> String? {
        if progress.releasedBytes > 0 { return SizeFormatter.text(progress.releasedBytes) + (dryRun ? " would be freed" : " freed") }
        if progress.movedToTrashBytes > 0 { return SizeFormatter.text(progress.movedToTrashBytes) + (dryRun ? " would go to the Trash" : " moved to the Trash") }
        return nil
    }
    /// "2 of 3", or "Done" once every item in the category is finished.
    fileprivate static func value(_ category: CleanupRunProgress.Category) -> String {
        category.state == .done ? "Done" : "\(category.finished) of \(category.total)"
    }
    /// What the category is doing: waiting, being cleaned (checked, in a dry run), or what it skipped or never started.
    fileprivate static func meaning(_ category: CleanupRunProgress.Category, dryRun: Bool) -> String {
        switch category.state {
        case .waiting: return "Waiting"
        case .cleaning: return dryRun ? "Checking…" : "Cleaning…"
        case .done:
            return [category.skipped > 0 ? CacheDropDesign.items(category.skipped) + " skipped" : nil,
                    category.notStarted > 0 ? CacheDropDesign.items(category.notStarted) + " not started" : nil].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// The bottom bar of a page that cleans (Decision 46): Stop while its run goes, the result's buttons after it, and the
/// page's own actions otherwise. `finish` is the result's last button: Done, or Start a new plan.
struct CleanupActionBar<Finish: View, Idle: View>: View {
    let selection: CleanupPlan
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
    let selection: CleanupPlan
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
    /// Follows a staying line's link (#354).
    var follow: ((AppUninstall.Staying.Link) -> Void)? = nil
    private let catalog = Catalog(rules: BuiltInCatalog.rules)
    /// The rows a running app holds, with "Quit X" (#377); checked again here, so the choices and the sheet stay as they are.
    @State private var held: ReviewHeldItems?
    @State private var quitting: Set<RuleOwner> = []
    @State private var quitAnApp = false
    init(review: WorkspaceCleanupReview, cancel: @escaping () -> Void, approve: @escaping () -> Void, follow: ((AppUninstall.Staying.Link) -> Void)? = nil) {
        self.review = review; self.cancel = cancel; self.approve = approve; self.follow = follow
        let catalog = catalog, quitter = CatalogCleanupModel.quitter
        _held = State(initialValue: review.catalog.map { ReviewHeldItems(candidates: $0.approval.candidates, refusals: $0.refusals, catalog: catalog, isOpen: quitter.isOpen) })
    }
    var body: some View {
        ReviewSheetFrame(title: "Review your cleanup", subtitle: "Clean up does exactly what’s listed here.") {
            trial.line
            if let items = review.catalog {
                CatalogConfirmationSection(review: items, catalog: catalog, follow: follow, held: held, quit: quitAction)
            }
        } actions: {
            Button("Cancel", action: cancelled).keyboardShortcut(.cancelAction)
            if !trial.fits { TrialOfferButtons() }
            // Applications' review can open during a rescan (Decision 123); Clean up waits for it, as Decision 61 says.
            if trial.fits {
                Button("Clean up", action: approve).buttonStyle(.borderedProminent).disabled(scanning)
                    .help(scanning ? CacheDropDesign.waitForScanHelp : "")
            } else {
                // Past the trial's cap Clean up can't run, so it isn't the prominent action; Buy is (Decision 137).
                Button("Clean up", action: approve).disabled(true)
            }
        }
        // Once at the start too: a holder may have quit while the checks ran, or held rows only through helpers that were closing.
        .task {
            let quits = CatalogCleanupModel.appTerminations()
            await checkQuitAppsAgain()
            for await _ in quits { await checkQuitAppsAgain() }
        }
    }
    private var scanning: Bool { review.model?.isScanning == true }
    private var trial: TrialReviewGate { TrialReviewGate(review: review.catalog, held: held, catalog: catalog) }
    /// The plan's running-owner lines catch up once the sheet is gone, never under it (#307).
    private func cancelled() {
        cancel()
        if quitAnApp, let model = review.model { Task { await model.checkRunningOwnersAgain() } }
    }
    private func quitAction(_ line: ReviewHeldItems.Line) -> StatusAction? {
        guard let owner = line.quitOwner, let title = line.quitTitle else { return nil }
        let busy = quitting.contains(owner)
        // The line's first candidate id, which starts with its rule's: each line gets its own link (#384, #560).
        return StatusAction(title: busy ? "Quitting…" : title, identifier: "reviewQuit-" + line.id, isDisabled: busy) { quit(owner) }
    }
    /// An app quit some other way while the sheet is open (#560): the rows of each holder no longer open are checked again,
    /// and again for a few seconds while some stay held, as when its helpers are still closing. The sheet stays open (#307).
    private func checkQuitAppsAgain() async {
        let quitter = CatalogCleanupModel.quitter
        for attempt in 0..<5 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            let owners = held?.ownersToCheckAgain(isOpen: quitter.isOpen).filter { !quitting.contains($0) } ?? []
            guard !owners.isEmpty else { return }
            quitAnApp = true
            // One check for every holder's rows: each pass reads the running processes once, not once per holder.
            let rows = owners.flatMap { held?.candidates(heldBy: $0) ?? [] }
            guard let checked = await review.model?.checkedAgain(rows) else { continue }
            // A Quit clicked meanwhile checks its own rows again when its app has gone.
            for owner in owners where !quitting.contains(owner) {
                held?.quitEnded(owner, outcome: .quit, isOpen: quitter.isOpen) { checked[$0.id] }
            }
        }
    }
    /// A normal quit request, never a force quit; once the app is gone its rows are checked again, otherwise they keep their reason.
    private func quit(_ owner: RuleOwner) {
        guard !quitting.contains(owner), let rows = held?.candidates(heldBy: owner) else { return }
        quitting.insert(owner); quitAnApp = true
        Task {
            let quitter = CatalogCleanupModel.quitter
            let outcome = await AppQuitRequest(quitter: quitter).quit(owner)
            let checked = outcome == .quit ? await review.model?.checkedAgain(rows) : nil
            held?.quitEnded(owner, outcome: checked == nil ? .stillOpen : outcome, isOpen: quitter.isOpen) { checked?[$0.id] }
            quitting.remove(owner)
        }
    }
}
/// The review sheet's frame: its header, the scrolling list, then its footer. Emptying from the Trash reuses it (#359).
/// It fits its content (#574), from `sheetWideMinHeight` up to `sheetWide`'s height, where the list scrolls.
struct ReviewSheetFrame<Content: View, Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    /// The list's own height, so the scroll view asks for no more than it shows.
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) { content() }.frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(idealHeight: contentHeight, maxHeight: contentHeight > 0 ? contentHeight : nil)
            // Checking turning into the review, Show files and a Quit re-check change the height smoothly, or at once
            // under Reduce Motion (#574).
            .animation(reduceMotion ? nil : .easeInOut(duration: CacheDropDesign.Motion.waiting), value: contentHeight)
            // Room the minimum height leaves over goes under the list, with no second gap above the footer's line.
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            SheetFooter(actions: actions)
        }.padding(CacheDropDesign.Space.xl)
            .frame(width: CacheDropDesign.Size.sheetWide.width)
            .frame(minHeight: CacheDropDesign.Size.sheetWideMinHeight, maxHeight: CacheDropDesign.Size.sheetWide.height)
            .background(CacheDropDesign.reading).cacheDropButtonRule()
    }
}

/// The review sheet from the click (Decision 126, #463): its checks running, then the review once they finish. `run` gets
/// the review Clean up was pressed on; nothing runs unless it is still the open sheet's.
struct ReviewSheet: View {
    let selection: CleanupPlan
    /// Follows a staying line's link (#354).
    var follow: ((AppUninstall.Staying.Link) -> Void)? = nil
    let run: (WorkspaceCleanupReview) -> Void
    /// The review last shown, kept while the sheet slides away so it never flips back to checking.
    @State private var shown: WorkspaceCleanupReview?
    var body: some View {
        Group {
            if let review = selection.reviewOpening.review ?? shown {
                WorkspaceCleanupConfirmationView(review: review, cancel: selection.closeReview, approve: { approve(review) }, follow: follow).id(review.id)
            } else {
                ReviewChecksRunning(cancel: selection.closeReview)
            }
        }
        .onAppear { ReviewSignposts.sheetShown(); if selection.reviewOpening.review != nil { ReviewSignposts.reviewShown() } }
        .onChange(of: selection.reviewOpening.review?.id) { _, _ in
            if let review = selection.reviewOpening.review { shown = review; ReviewSignposts.reviewShown() }
        }
    }
    private func approve(_ review: WorkspaceCleanupReview) {
        guard selection.reviewOpening.review?.id == review.id else { return }
        selection.closeReview()
        run(review)
    }
}

/// The review sheet while its click-time checks run (Decision 126): what it is doing, and Clean up unavailable until they finish.
struct ReviewChecksRunning: View {
    let cancel: () -> Void
    var body: some View {
        ReviewSheetFrame(title: "Review your cleanup", subtitle: "Clean up does exactly what’s listed here.") {
            HStack(spacing: CacheDropDesign.Space.sm) {
                ProgressView().controlSize(.small)
                Text("Checking selected items…")
            }.font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine).accessibilityIdentifier("reviewChecking")
            SkeletonRows(.line, identifier: "reviewSkeleton")
        } actions: {
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button("Clean up") {}.buttonStyle(.borderedProminent).disabled(true).help("Available once every item is checked")
        }
    }
}

/// Signposts for the click to the review sheet (#463), read in Instruments' os_signpost or Points of Interest: subsystem
/// `com.patrickbourget.CacheDrop`, category `ReviewLatency`. "Click to sheet" and "Click to review" start at the click;
/// "Review checks" spans the click-time checks, and the steps inside them have their own intervals. Release-safe.
@MainActor enum ReviewSignposts {
    nonisolated static let signposter = OSSignposter(subsystem: "com.patrickbourget.CacheDrop", category: "ReviewLatency")
    private static var toSheet: OSSignpostIntervalState?
    private static var toReview: OSSignpostIntervalState?
    static func clicked() {
        closed()
        toSheet = signposter.beginInterval("Click to sheet"); toReview = signposter.beginInterval("Click to review")
    }
    static func sheetShown() { toSheet.map { signposter.endInterval("Click to sheet", $0) }; toSheet = nil }
    static func reviewShown() { toReview.map { signposter.endInterval("Click to review", $0) }; toReview = nil }
    /// The sheet closed, or never got a review: whatever is still open ends here.
    static func closed() { sheetShown(); reviewShown() }
    /// One step of the checks, as its own interval.
    static func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
