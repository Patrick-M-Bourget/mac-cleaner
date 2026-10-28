import AppKit
import CacheDropCore
import SwiftUI

/// Smart clean (#141): the recommended plan on its own page. Only data that rebuilds itself, grouped by category, all ticked
/// and each untickable, with one Clean up that opens the review sheet. Its selection is its own; the Cleanup plan's never changes.
struct SmartCleanView: View {
    let selection: SessionPlan
    /// Opens the Cleanup plan, with a category open when one is named.
    let openPlan: (CatalogCategory?) -> Void
    var viewHistory: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    /// Which categories are open, kept by the caller like the plan's `CleanupPlanPresentation` (Decision 48).
    let presentation: SmartCleanPresentation
    @State private var review: WorkspaceCleanupReview?
    @State private var approvalError: String?
    private var model: CatalogCleanupModel { selection.catalog }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if selection.showsRun(for: .smartClean) { CleanupRunSection(selection: selection) } else { page }
            }.background(CacheDropDesign.reading)
            CleanupActionBar(selection: selection, source: .smartClean, viewHistory: viewHistory, reviewRecovery: reviewRecovery) {
                Button("Done") { selection.dismissResult() }.buttonStyle(.borderedProminent).accessibilityIdentifier("smartCleanDone")
            } idle: {
                Button("Clean up") { Task { await openReview() } }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!selection.canReviewSmartClean).accessibilityIdentifier("smartCleanCleanUp")
            }
        }
        .sheet(item: $review) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: model.selectionRevision) { _, _ in if review != nil { review = nil; approvalError = PlanReviewError.changedMessage } }
        .task { await model.scanIfNeeded() }
    }

    private var page: some View {
        let items = model.recommendedCandidates
        let rows = CatalogOverview(catalog: model.catalog, candidates: items).rows
        return VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: title, subtitle: "Rebuildable caches, build files and logs. Never your files.")
                .accessibilityElement(children: .combine).accessibilityIdentifier("smartCleanHeader")
                .padding(.bottom, CacheDropDesign.Space.sm)
            meter
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution, identifier: "smartCleanError") }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    category(row, items: items)
                    Divider().padding(.vertical, CacheDropDesign.Space.md)
                }
            }
            if rows.isEmpty && model.hasScanned && !model.isScanning {
                Text("Nothing to clean right now.").font(.callout).foregroundStyle(.secondary)
            }
            notIncluded
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The same meter as Overview's, with what Smart clean would free in full colour and the rest dimmed (#164).
    @ViewBuilder private var meter: some View {
        let reading = AppLifecycleController.shared.capacity.reading
        if let breakdown = model.breakdown(available: reading?.available, total: reading?.total, trash: TrashModel.shared.contents, highlightingSmartClean: true),
           breakdown.segments.contains(where: { $0.bytes > 0 }) {
            CapacityMeter(available: reading?.available, total: reading?.total, showsValue: false, prominent: true, breakdown: breakdown,
                          open: { part in part.categories.forEach { openPlan($0) } })
                .accessibilityIdentifier("smartCleanMeter").padding(.bottom, CacheDropDesign.Space.sm)
        }
    }

    /// "Smart clean · X ready to clean": the ticked items' size; "Up to" when part of it is copies that share disk blocks.
    private var title: String {
        let ticked = model.smartCleanCandidates
        guard !ticked.isEmpty else { return "Smart clean" }
        let upperBound = ticked.contains { model.catalog.rule($0.ruleID)?.estimateIsUpperBound == true }
        return "Smart clean · " + SizeEstimate(sum: ticked.map(SizeEstimate.init)).text(upperBound: upperBound) + " ready to clean"
    }

    /// The plan's category row (Decision 48): its checkbox ticks or unticks all of its recommended items; "Choose items · N"
    /// opens one line per rule (or per app or profile when a rule groups them), unless the category has only one. N counts
    /// those lines, not the items behind them (#229).
    private func category(_ row: CatalogOverview.Row, items: [Candidate]) -> some View {
        let found = items.filter { candidate in row.rules.contains { $0.id == candidate.ruleID } }
        let ticked = found.filter(model.isInSmartClean).count
        let state: CategorySelectionState = ticked == 0 ? .unchecked : ticked == found.count ? .checked : .mixed
        let lines = lines(row, found: found)
        let expanded = Binding(get: { presentation.expandedCategories.contains(row.category) },
                               set: { if $0 { presentation.expandedCategories.insert(row.category) } else { presentation.expandedCategories.remove(row.category) } })
        return CategoryRow(category: row.category.storageCategory, state: state, title: row.category.overviewTitle, detail: row.category.overviewDetail,
                           size: row.valueText, enabled: model.canEdit, identifier: "smartCleanCategory-" + row.id,
                           itemCount: lines.count > 1 ? lines.count : nil, expanded: expanded,
                           toggle: { model.setSmartClean(found, state != .checked) }) {
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
    }
    private func lines(_ row: CatalogOverview.Row, found: [Candidate]) -> [Line] {
        row.rules.flatMap { rule -> [Line] in
            let items = found.filter { $0.ruleID == rule.id }
            let groups = Dictionary(grouping: items) { $0.group }
            return groups.keys.sorted { ($0 ?? "").localizedStandardCompare($1 ?? "") == .orderedAscending }.map { group in
                let name = group.map { row.rules.count > 1 ? rule.title + " · " + $0 : $0 } ?? rule.title
                return Line(id: rule.id + "|" + (group ?? ""), name: name, rule: rule, items: groups[group] ?? [])
            }
        }
    }
    private func line(_ line: Line) -> some View {
        InspectableItemRow(name: line.name, detail: "",
                           size: catalogBytes(line.items.reduce(0) { $0 + $1.estimatedBytes }, complete: line.items.allSatisfy(\.sizeComplete),
                                              upperBound: line.rule.estimateIsUpperBound, estimate: line.items.contains(where: \.sizeIsEstimate)),
                           symbol: "folder", inspected: false, inspect: { Finder.reveal(line.items.map(\.url)) }) {
            Toggle("Include " + line.name, isOn: Binding(get: { line.items.allSatisfy(model.isInSmartClean) }, set: { model.setSmartClean(line.items, $0) }))
                .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("smartCleanLine-" + line.id)
        }.help(line.items.map(\.url.path).sorted().joined(separator: "\n"))
    }

    /// What Smart clean leaves out, each a link to the Cleanup plan, where it can be chosen by hand.
    private var notIncluded: some View {
        let kinds: [(title: String, category: CatalogCategory?)] = [("Trash items", .downloads), ("models", .models), ("iCloud copies", .icloud),
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
        do { review = try await selection.prepareSmartCleanReview(); approvalError = nil }
        catch PlanReviewError.nothingToClean { approvalError = "Nothing here can be cleaned right now. Scan again." }
        catch { approvalError = PlanReviewError.changedMessage }
    }
}
