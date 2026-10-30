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
        return catalog.selectedRuleCount
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
    /// Smart clean's review: the recommended part of the shared selection, checked now through the plan's review and executor (Decision 67).
    func prepareSmartCleanReview() async throws -> WorkspaceCleanupReview {
        guard canReviewSmartClean else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision(for: .smartClean)
        guard let checked = await catalog.smartCleanCheckedNow() else { throw failure }
        guard !checked.items.isEmpty else { throw PlanReviewError.nothingToClean }
        return try await review(checked.items, from: .smartClean, catalogVersion: catalogVersion, check: checked.check)
    }
    /// The Applications page's review: its chosen items, through the plan's review and executor.
    func prepareApplicationsReview() async throws -> WorkspaceCleanupReview {
        guard canReviewApplications else { throw PlanReviewError.changed }
        return try await review(catalog.applicationsSelected, from: .applications, catalogVersion: catalog.selectionRevision(for: .applications))
    }
    /// A page's review of `items` through the plan's review, refused when the page's choices changed meanwhile.
    private func review(_ items: [Candidate], from source: CleanupSelections.Source, catalogVersion: UInt64, check: CandidateCheck? = nil) async throws -> WorkspaceCleanupReview {
        let review = await catalog.prepareReview(of: items, using: check)
        guard let review else { throw failure }
        guard canReview(source), catalog.selectionRevision(for: source) == catalogVersion else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: review, catalogVersion: catalogVersion, source: source, model: catalog)
    }
    func prepareWorkspaceReview() async throws -> WorkspaceCleanupReview {
        guard canReview else { throw PlanReviewError.changed }
        let catalogVersion = catalog.selectionRevision(for: .plan)
        let items = catalog.selectedCount > 0 ? await catalog.prepareReview() : nil
        if catalog.selectedCount > 0, items == nil, catalog.settingsUnreadable { throw PlanReviewError.settingsUnreadable }
        guard canReview, catalog.selectionRevision(for: .plan) == catalogVersion, catalog.selectedCount == 0 || items != nil else { throw PlanReviewError.changed }
        return WorkspaceCleanupReview(catalog: items, catalogVersion: catalogVersion, model: catalog)
    }
    /// Why a review couldn't be built: the settings couldn't be read, or the choices changed meanwhile.
    private var failure: PlanReviewError { catalog.settingsUnreadable ? .settingsUnreadable : .changed }
    func executeWorkspace(_ review: WorkspaceCleanupReview) async throws {
        guard canReview(review.source), catalog.selectionRevision(for: review.source) == review.catalogVersion else { throw PlanReviewError.changed }
        await run(review)
        // CacheDrop scans again by itself, whichever page is open (#306); the pages keep the rows the run left, dimmed, until it ends (#375).
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
    @State private var review: WorkspaceCleanupReview?
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
            CatalogPlanSection(model: selection.catalog, expanded: $presentation.expandedCategories, exploreStorage: exploreStorage)
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
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: selection.catalog.selectionRevision(for: .plan)) { _, _ in if review != nil { review = nil; approvalError = PlanReviewError.changedMessage } }
    }
    /// The shared selection's part on Applications, which the plan's count leaves out (#481): Smart clean counts it too.
    private var applicationsLink: (title: String, open: () -> Void)? {
        let count = selection.catalog.applicationsSelected.count
        guard count > 0, let openApplications else { return nil }
        return ("\(count) on Applications", openApplications)
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
            PageHeader(title: selection.workspaceRunning ? "Cleaning up…" : "Cleanup results")
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
            if let items = review.catalog {
                CatalogConfirmationSection(review: items, catalog: catalog, follow: follow, refusals: held?.refusals, quit: quitAction)
            }
        } actions: {
            Button("Cancel", action: cancelled).keyboardShortcut(.cancelAction); Button("Clean up", action: approve).buttonStyle(.borderedProminent)
        }
    }
    /// The plan's running-owner lines catch up once the sheet is gone, never under it (#307).
    private func cancelled() {
        cancel()
        if quitAnApp, let model = review.model { Task { await model.checkRunningOwnersAgain() } }
    }
    private func quitAction(_ item: Candidate) -> StatusAction? {
        guard let held, let owner = held.holder(of: item), let title = held.quitTitle(for: item) else { return nil }
        let busy = quitting.contains(owner)
        // The candidate's id, which starts with its rule's: rows of one rule each get their own link (#384).
        return StatusAction(title: busy ? "Quitting…" : title, identifier: "reviewQuit-" + item.id, isDisabled: busy) { quit(owner) }
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
struct ReviewSheetFrame<Content: View, Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) { content() }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            SheetFooter(actions: actions)
        }.padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetWide.width, height: CacheDropDesign.Size.sheetWide.height).background(CacheDropDesign.reading).cacheDropButtonRule()
    }
}
