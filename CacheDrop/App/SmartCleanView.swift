import AppKit
import CacheDropCore
import SwiftUI

/// Smart clean (#141, #319, #779): the quickest effective first clean, on one screen. It decides; the Cleanup plan edits
/// (Decision 173). "Free up X", one row per recommended category, one caption that leads to the plan, and Clean up X.
/// Recommended items start ticked; choices are shared with the plan and Applications (Decision 67). Clean up opens the review sheet.
struct SmartCleanView: View {
    let selection: CleanupPlan
    /// Opens the Cleanup plan, with a category open when one is named.
    let openPlan: (CatalogCategory?) -> Void
    var viewHistory: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    /// The workspace's Scan again, for the state that says nothing here can be cleaned (#321).
    var scanAgain: () -> Void = {}
    @State private var approvalError: String?
    /// Clean up found nothing it can clean since the scan: the page says so, with Scan again (#321).
    @State private var nothingToClean = false
    /// Worth a look's open rows, this page's own (Decision 48: each screen keeps its open state).
    @State private var worthALookOpen: Set<CatalogCategory> = []
    private var model: CatalogCleanupModel { selection.catalog }

    var body: some View {
        let summary = SmartCleanSummary(ticked: model.smartCleanCandidates, catalog: model.catalog)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if selection.showsRun(for: .smartClean) { CleanupRunSection(selection: selection, reveal: proxy.revealRow) } else { page(summary) }
                }.background(CacheDropDesign.reading)
            }
            CleanupActionBar(selection: selection, source: .smartClean, viewHistory: viewHistory, reviewRecovery: reviewRecovery) {
                Button("Done") { selection.dismissResult() }.accessibilityIdentifier("smartCleanDone")
            } idle: {
                BusyAction(busy: selection.isCheckingReview) {
                    Button(summary.cleanUpTitle) { Task { await openReview() } }.buttonStyle(.borderedProminent)
                        .disabled(!selection.canReviewSmartClean).accessibilityIdentifier("smartCleanCleanUp")
                }.help(model.isScanning ? CacheDropDesign.waitForScanHelp : "")
            }
        }
        .sheet(isPresented: selection.reviewSheet(for: .smartClean)) {
            ReviewSheet(selection: selection) { snapshot in
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: model.selectionRevision(for: .smartClean)) { _, _ in if selection.reviewChoicesChanged(.smartClean) { approvalError = PlanReviewError.changedMessage } }
        .onChange(of: model.isScanning) { _, scanning in if scanning { nothingToClean = false } }
    }

    private func page(_ summary: SmartCleanSummary) -> some View {
        // What something holds stays in its category, unticked, with why (#374).
        let items = model.recommendedCandidates + model.recommendedHeld
        // No column header here, so no sort to choose: largest first (Decision 173).
        let rows = ListSort().ordered(CatalogOverview(catalog: model.catalog, candidates: items).rows,
                                      name: { $0.category.smartCleanTitle }, bytes: { $0.estimate.sortBytes })
        return VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: "Smart clean", subtitle: "What’s safe to clean, already ticked")
                .accessibilityElement(children: .combine).accessibilityIdentifier("smartCleanHeader")
                .padding(.bottom, CacheDropDesign.Space.sm)
            // The plan's card (Decision 74), titled "Free up" here (Decision 173): what the ticked items release, never what
            // goes to the Trash (#350, SPEC section 6), "Up to" when part of it is copies that share disk blocks.
            SelectionSummary(value: summary.freeUp ?? CacheDropDesign.noValue, detail: CacheDropDesign.items(summary.itemCount) + " selected",
                             identifier: "smartCleanSummary", title: SmartCleanSummary.title)
                .help(CacheDropDesign.selectionEstimateHelp)
            SettingsUnreadableNotice(model: model)
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution, identifier: "smartCleanError") }
            if nothingToClean {
                EmptyState(title: "Nothing here can be cleaned right now", symbol: "arrow.clockwise",
                           action: EmptyStateAction("Scan again", perform: scanAgain), identifier: "smartCleanNothingToClean")
            }
            // Nothing known yet: skeleton rows; a rescan dims the rows already shown (#308).
            if !model.hasScanned {
                SkeletonRows(.category, identifier: "smartCleanSkeleton")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        category(row, items: items)
                        Divider().padding(.vertical, CacheDropDesign.Space.md)
                    }
                }.waitingForScan(model.isScanning)
            }
            if rows.isEmpty && model.hasScanned && !model.isScanning && !model.settingsUnreadable { NothingToCleanUp(identifier: "smartCleanEmpty") }
            worthALook
            notIncluded
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The plan's category row (Decision 48) with the plan's what-it-is line and no "Choose items" (Decision 173): its checkbox,
    /// or a click on the row (Decision 69), ticks or unticks all of its recommended items. What something holds is never ticked
    /// with it (#374, Decision 78) and says why under the row.
    private func category(_ row: CatalogOverview.Row, items: [Candidate]) -> some View {
        let found = items.filter { candidate in row.rules.contains { $0.id == candidate.ruleID } }
        let selection = model.categorySelection(row.rules, items: found)
        let holds = CandidateHold.grouped(found).compactMap(\.hold)
        return CategoryRow(category: row.category.storageCategory, state: selection.state, title: row.category.smartCleanTitle,
                           detail: row.category.smartCleanDetail, size: row.valueText, enabled: model.canEdit, identifier: "smartCleanCategory-" + row.id,
                           itemCount: nil, expanded: .constant(false),
                           // Nothing may be ticked together (#384): the plan lists the items, to tick each on its own.
                           toggle: { if model.toggle(selection) { openPlan(row.category) } }) {
            ForEach(Array(holds.enumerated()), id: \.offset) { index, hold in
                StatusRow(text: hold.line, symbol: "exclamationmark.circle", role: .caution, identifier: "smartCleanHeld-\(row.id)-\(index + 1)")
            }
        } items: {
            EmptyView()
        }
    }

    /// What Smart clean leaves out, and the one way to change it: the Cleanup plan, with the same ticks (Decision 67).
    private var notIncluded: some View {
        HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.xs) {
            Text(SmartCleanSummary.notIncluded).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
            Button(SmartCleanSummary.adjust) { openPlan(nil) }.buttonStyle(.link).accessibilityIdentifier("smartCleanAdjust")
        }.font(CacheDropDesign.TypeStyle.caption).accessibilityElement(children: .contain).accessibilityIdentifier("smartCleanNotIncluded")
    }

    /// Worth a look (#780, Decision 178): a quiet group under the rows, above the caption, of the files from deleted apps the
    /// recommended plan doesn't take, never ticked for you, their ticks shared with Applications. Nothing in it, no header.
    @ViewBuilder private var worthALook: some View {
        let items = model.worthALookCandidates
        let rows = WorthALook.rows(items, catalog: model.catalog)
        if model.hasScanned, !rows.isEmpty {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                Text(WorthALook.title).font(CacheDropDesign.TypeStyle.section).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("smartCleanWorthALook")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        suggestion(row, items: items)
                        Divider().padding(.vertical, CacheDropDesign.Space.md)
                    }
                }.waitingForScan(model.isScanning)
            }.padding(.top, CacheDropDesign.Space.lg)
        }
    }

    /// A Worth a look row: the category row Applications draws (Decision 48), holding only what the plan doesn't take, so
    /// nothing shows twice. Its items, under Choose items, are ticked one by one where they must be (Decision 49).
    private func suggestion(_ row: CatalogOverview.Row, items: [Candidate]) -> some View {
        let found = items.filter { candidate in row.rules.contains { $0.id == candidate.ruleID } }
        let selection = model.categorySelection(row.rules, items: found)
        let expanded = Binding(get: { worthALookOpen.contains(row.category) },
                               set: { if $0 { worthALookOpen.insert(row.category) } else { worthALookOpen.remove(row.category) } })
        return CategoryRow(category: row.category.storageCategory, state: selection.state, title: row.category.overviewTitle,
                           detail: row.category.overviewDetail, size: row.valueText, enabled: model.canEdit, identifier: "smartCleanSuggestion-" + row.id,
                           itemCount: found.count, expanded: expanded,
                           // Nothing may be ticked together: the row opens its items to tick each on its own.
                           toggle: { if model.toggle(selection) { expanded.wrappedValue = true } }) {
            EmptyView()
        } items: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(row.rules) { rule in CatalogItemRows(model: model, rule: rule, only: Set(found.map(\.id))) }
            }
        }
    }

    private func openReview() async {
        do {
            guard try await selection.openReview(.smartClean, checks: selection.prepareSmartCleanReview) else { return }
            approvalError = nil; nothingToClean = false
        }
        catch PlanReviewError.nothingToClean { approvalError = nil; nothingToClean = true }
        catch { approvalError = PlanReviewError.message(for: error); nothingToClean = false }
    }
}
