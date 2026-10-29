import AppKit
import CacheDropCore
import SwiftUI

/// Smart clean (#141, #319): the recommended plan on its own page, grouped by category with one consequence line each, all
/// ticked and each untickable, with one Clean up that opens the review sheet. Its selection is its own; the Cleanup plan's never changes.
struct SmartCleanView: View {
    let selection: SessionPlan
    /// Opens the Cleanup plan, with a category open when one is named.
    let openPlan: (CatalogCategory?) -> Void
    var viewHistory: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    /// Which categories are open, kept by the caller like the plan's `CleanupPlanPresentation` (Decision 48).
    let presentation: SmartCleanPresentation
    /// The workspace's Scan again, for the state that says nothing here can be cleaned (#321).
    var scanAgain: () -> Void = {}
    @State private var review: WorkspaceCleanupReview?
    @State private var approvalError: String?
    /// Clean up found nothing it can clean since the scan: the page says so, with Scan again (#321).
    @State private var nothingToClean = false
    private var model: CatalogCleanupModel { selection.catalog }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if selection.showsRun(for: .smartClean) { CleanupRunSection(selection: selection) } else { page }
            }.background(CacheDropDesign.reading)
            CleanupActionBar(selection: selection, source: .smartClean, viewHistory: viewHistory, reviewRecovery: reviewRecovery) {
                Button("Done") { selection.dismissResult() }.buttonStyle(.borderedProminent).accessibilityIdentifier("smartCleanDone")
            } idle: {
                BusyAction(busy: selection.isCheckingReview) {
                    Button("Clean up") { Task { await openReview() } }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!selection.canReviewSmartClean).accessibilityIdentifier("smartCleanCleanUp")
                }.help(model.isScanning ? CacheDropDesign.waitForScanHelp : "")
            }
        }
        .sheet(item: $review) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: model.selectionRevision(for: .smartClean)) { _, _ in if review != nil { review = nil; approvalError = PlanReviewError.changedMessage } }
        .onChange(of: model.isScanning) { _, scanning in if scanning { nothingToClean = false } }
    }

    private var page: some View {
        // What something holds stays listed, unticked, with why (#374).
        let items = model.recommendedCandidates + model.recommendedHeld
        let rows = CatalogOverview(catalog: model.catalog, candidates: items).rows
        return VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: "Smart clean", subtitle: "A safe plan from what takes up space. Untick anything you want to keep.")
                .accessibilityElement(children: .combine).accessibilityIdentifier("smartCleanHeader")
                .padding(.bottom, CacheDropDesign.Space.sm)
            summary
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
            notIncluded
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The Cleanup plan's summary card (#370, Decision 74): what the ticked items release, never what goes to the Trash
    /// (#350, SPEC section 6), "Up to" when part of it is copies that share disk blocks; and how many items are ticked.
    private var summary: some View {
        let ticked = model.smartCleanCandidates, releasing = ticked.filter(\.releasesSpace)
        let upperBound = releasing.contains { model.catalog.rule($0.ruleID)?.estimateIsUpperBound == true }
        let value = releasing.isEmpty ? "—" : SizeEstimate(sum: releasing.map(SizeEstimate.init)).text(upperBound: upperBound)
        return SelectionSummary(value: value, detail: CacheDropDesign.items(ticked.count) + " selected", identifier: "smartCleanSummary",
                                title: "Ready to clean")
            .help(CacheDropDesign.selectionEstimateHelp)
    }

    /// The plan's category row (Decision 48): its checkbox ticks or unticks all of its recommended items; "Choose items · N"
    /// opens one line per rule (or per app or profile when a rule groups them), unless the category has only one. N counts
    /// those lines, not the items behind them (#229).
    private func category(_ row: CatalogOverview.Row, items: [Candidate]) -> some View {
        let found = items.filter { candidate in row.rules.contains { $0.id == candidate.ruleID } }
        // A held item is ticked on its own, never with its category (#374).
        let free = found.filter { $0.hold == nil }, together = free.isEmpty ? found : free
        let ticked = found.filter(model.isSelected).count
        let state: CategorySelectionState = ticked == 0 ? .unchecked : together.allSatisfy(model.isSelected) ? .checked : .mixed
        let lines = lines(row, found: found)
        let expanded = Binding(get: { presentation.expandedCategories.contains(row.category) },
                               set: { if $0 { presentation.expandedCategories.insert(row.category) } else { presentation.expandedCategories.remove(row.category) } })
        // One consequence line per category (#319), from what its rules do.
        let consequence = SmartCleanConsequence.line(for: row.category, rules: row.rules)
        return CategoryRow(category: row.category.storageCategory, state: state, title: row.category.overviewTitle, detail: consequence,
                           size: row.valueText, enabled: model.canEdit, identifier: "smartCleanCategory-" + row.id,
                           itemCount: lines.count > 1 ? lines.count : nil, expanded: expanded,
                           toggle: { model.setSelected(state != .checked ? together : found, state != .checked) }) {
            EmptyView()
        } items: {
            VStack(alignment: .leading, spacing: 0) { ForEach(lines) { line($0) } }
        }
    }

    private struct Line: Identifiable {
        let id: String
        let name: String
        let rule: CleanupRule
        let items: [Candidate]
        /// What holds these items (#374); nil for free ones.
        var hold: CandidateHold? = nil
    }
    private func lines(_ row: CatalogOverview.Row, found: [Candidate]) -> [Line] {
        row.rules.flatMap { rule -> [Line] in
            let items = found.filter { $0.ruleID == rule.id }
            let groups = Dictionary(grouping: items) { $0.group }
            return groups.keys.sorted { ($0 ?? "").localizedStandardCompare($1 ?? "") == .orderedAscending }.flatMap { group in
                let name = group.map { row.rules.count > 1 ? rule.title + " · " + $0 : $0 } ?? rule.title
                // Held items get a line of their own per reason, unticked, saying why (#374).
                let byHold = Dictionary(grouping: groups[group] ?? []) { $0.hold }
                return byHold.keys.sorted { ($0?.line ?? "") < ($1?.line ?? "") }.map { hold in
                    Line(id: rule.id + "|" + (group ?? "") + (hold.map { "|held-" + $0.line } ?? ""), name: name, rule: rule, items: byHold[hold] ?? [], hold: hold)
                }
            }
        }
    }
    private func line(_ line: Line) -> some View {
        InspectableItemRow(name: line.name, detail: line.hold?.line ?? "",
                           size: catalogBytes(line.items.reduce(0) { $0 + $1.estimatedBytes }, complete: line.items.allSatisfy(\.sizeComplete),
                                              upperBound: line.rule.estimateIsUpperBound, estimate: line.items.contains(where: \.sizeIsEstimate)),
                           symbol: "folder", inspected: false,
                           // Clicking the line ticks it, as its checkbox does; Finder is its own Reveal link (#367, Decision 72).
                           inspect: line.rule.itemRowClick == .tick ? { if model.canEdit { model.setSelected(line.items, !line.items.allSatisfy(model.isSelected)) } } : nil,
                           actionLabel: "Include " + line.name, reveal: { Finder.reveal(line.items.map(\.url)) }, revealIdentifier: "smartCleanLineReveal-" + line.id) {
            Toggle("Include " + line.name, isOn: Binding(get: { line.items.allSatisfy(model.isSelected) }, set: { model.setSelected(line.items, $0) }))
                .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("smartCleanLine-" + line.id)
        }.help(line.items.map(\.url.path).sorted().joined(separator: "\n"))
    }

    /// What Smart clean leaves out, each a link to the Cleanup plan, where it can be chosen by hand.
    private var notIncluded: some View {
        let kinds: [(title: String, category: CatalogCategory?)] = [("newer downloads", .downloads), ("models", .models), ("iCloud copies", .icloud),
                                                                    ("your files", .files), ("anything a running app is using", nil)]
        return HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.xs) {
            Text("Not included:").foregroundStyle(.secondary)
            ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                if index > 0 { Text("·").foregroundStyle(.secondary) }
                Button(kind.title) { openPlan(kind.category) }.buttonStyle(.link)
                    .accessibilityIdentifier("smartCleanNotIncluded-" + (kind.category?.rawValue ?? "running"))
            }
        }.font(CacheDropDesign.TypeStyle.caption).accessibilityElement(children: .contain).accessibilityIdentifier("smartCleanNotIncluded")
    }

    private func openReview() async {
        do {
            guard let checked = try await selection.checkingReview(selection.prepareSmartCleanReview) else { return }
            review = checked; approvalError = nil; nothingToClean = false
        }
        catch PlanReviewError.nothingToClean { approvalError = nil; nothingToClean = true }
        catch { approvalError = PlanReviewError.message(for: error); nothingToClean = false }
    }
}
