import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// The cleanup plan: one row per catalog category, as Overview groups them, with its rules and items under "Choose items".
struct CatalogPlanSection: View {
    @Bindable var model: CatalogCleanupModel
    @Binding var expanded: Set<CatalogCategory>
    /// Where the empty state leads (#321).
    var exploreStorage: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            // Nothing known yet: skeleton rows; a rescan dims the rows already shown (#308).
            if !model.hasScanned {
                SkeletonRows(.category, identifier: "planSkeleton")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.planCategories) { row in
                        PlanCategoryRow(model: model, row: row, expanded: Binding(get: { expanded.contains(row.category) },
                                                                                 set: { if $0 { expanded.insert(row.category) } else { expanded.remove(row.category) } }))
                        Divider().padding(.vertical, CacheDropDesign.Space.md)
                    }
                }.waitingForScan(model.isScanning)
                if model.planCategories.isEmpty && !model.isScanning && !model.settingsUnreadable { NothingToCleanUp(identifier: "planEmpty", action: exploreStorage.map { EmptyStateAction("Explore storage", perform: $0) }) }
            }
            ForEach(model.overriddenRules) { rule in
                StatusRow(text: "\(rule.owner?.name ?? rule.title) keeps its data in a custom location, so CacheDrop leaves it alone.",
                          symbol: "info.circle", role: .neutral, identifier: "planOverridden-" + rule.id)
            }
            if !model.notAccessibleRules.isEmpty {
                HStack(spacing: CacheDropDesign.Space.sm) {
                    StatusRow(text: ListFormatter.localizedString(byJoining: model.notAccessibleRules.map(\.title)) + " needs Full Disk Access.", symbol: "lock",
                              identifier: "planNotAccessible").fixedSize()
                    FullDiskAccessLink(title: "Learn more", symbol: nil)
                    Spacer(minLength: 0)
                }
            }
            ForEach(model.notes, id: \.ruleID) { note in StatusRow(text: note.text, symbol: "info.circle", role: .neutral, identifier: "planNote-" + note.ruleID) }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
        }
    }
}

/// The one line every page that cleans, and Overview, shows when the Protected items settings couldn't be read (#310),
/// with Try again, which scans again.
struct SettingsUnreadableNotice: View {
    let model: CatalogCleanupModel
    var body: some View {
        if model.settingsUnreadable {
            StatusRow(text: CatalogCleanupModel.settingsUnreadableText, symbol: "exclamationmark.triangle", role: .caution, identifier: "settingsUnreadable",
                      action: StatusAction(title: "Try again", identifier: "settingsUnreadableTryAgain") { Task { await model.rescan() } })
                .disabled(model.isScanning)
        }
    }
}

/// A plan category through the shared `CategoryRow` (Decision 48), with its rules or items under "Choose items".
struct PlanCategoryRow: View {
    @Bindable var model: CatalogCleanupModel
    let row: CatalogOverview.Row
    @Binding var expanded: Bool
    /// The Applications page's Sort and search, for its leftovers (#295); nil lists everything.
    var listing: ApplicationsListing? = nil
    var body: some View {
        let state = model.selectionState(for: row.rules)
        CategoryRow(category: row.category.storageCategory, state: state, title: row.category.overviewTitle, detail: row.category.overviewDetail,
                    size: row.valueText, enabled: model.canEdit, identifier: "planCategory-" + row.id,
                    itemCount: row.planLayout == .categoryOnly ? nil : row.itemCount, expanded: $expanded,
                    toggle: { if model.toggleCategory(row.rules) { expanded = true } }) {
            if row.planLayout != .ruleRows, let rule = row.rules.first { PlanRunningOwners(model: model, rule: rule) }
        } items: {
            switch row.planLayout {
            case .ruleRows:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(row.rules) { rule in PlanRuleRows(model: model, rule: rule, listing: listing) }
                }
            case .items:
                if let rule = row.rules.first { PlanRuleItems(model: model, rule: rule, listing: listing) }
            case .categoryOnly:
                EmptyView()
            }
        }
    }
}

/// Why a rule can't be cleaned right now: its owner is open. One quiet line with one link, as `TrashLine` is drawn
/// (Decision 25): "Quit <App>" for an open app, "Check again" for a command-line tool (#138).
struct PlanRunningOwners: View {
    let model: CatalogCleanupModel
    let rule: CleanupRule
    /// Only these owners' lines, as an app's or plug-in product's row on the Applications page shows them (#177, #176).
    var only: Set<String>? = nil
    var body: some View {
        ForEach(model.runningOwnerNotices(for: rule).filter { only?.contains($0.name) ?? true }, id: \.name) { owner in
            let quitting = model.quitStates[owner.name] == .quitting
            HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.xs) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(StatusRole.caution.color).accessibilityHidden(true)
                Text(owner.notice.text + " ·").foregroundStyle(.secondary).accessibilityIdentifier("planRunning-" + rule.id)
                switch owner.notice.action {
                case .quitApp(let title):
                    Button(quitting ? "Quitting…" : title) { Task { await model.quitApp(named: owner.name) } }.disabled(quitting)
                        .buttonStyle(.link).accessibilityIdentifier("planRunningQuit-" + rule.id)
                case .checkAgain:
                    Button("Check again") { Task { await model.checkRunningOwnersAgain() } }
                        .buttonStyle(.link).accessibilityIdentifier("planRunningCheck-" + rule.id)
                }
            }.font(CacheDropDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
        }
    }
}

/// A rule's items, each chosen on its own: profiles or apps when it groups them, otherwise single items.
private struct PlanRuleItems: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var listing: ApplicationsListing? = nil
    var body: some View {
        if !rule.selectedOneByOne, model.candidates(for: rule).contains(where: { $0.group != nil }) { CatalogProfileRows(model: model, rule: rule, listing: listing) }
        else { CatalogItemRows(model: model, rule: rule, listing: listing) }
    }
}

/// A rule inside its category, then the items it lets you choose one by one (Downloads files, models, profiles).
private struct PlanRuleRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    /// A search that matches none of the rule's items hides its row (#295).
    var listing: ApplicationsListing? = nil
    var body: some View {
        let items = model.candidates(for: rule), state = model.selectionState(for: [rule])
        if !items.contains(where: { listing?.matches($0) ?? true }) { EmptyView() } else {
        // A tool-asked rule's line says where its folder came from (#206); what the rule covers moves to the tooltip.
        let source = items.lazy.compactMap(\.folderSource).first
        VStack(alignment: .leading, spacing: 0) {
            InspectableItemRow(name: rule.title, detail: source ?? rule.detail,
                               size: catalogBytes(model.estimatedBytes(for: rule), complete: model.sizeComplete(for: rule), upperBound: rule.estimateIsUpperBound,
                                                  estimate: model.sizeIsEstimate(for: rule)),
                               symbol: rule.offersFiles ? "doc.on.doc" : "folder", inspected: false,
                               inspect: { Finder.reveal(items.map(\.url)) }, detailLineLimit: 1) {
                MacroCategoryCheckbox(state: state, label: rule.title, enabled: model.canEdit && !rule.selectedOneByOne, action: { model.setSelected(rule, state != .checked) },
                                      identifier: "planRule-" + rule.id, showsTitle: false).fixedSize()
            }.help(source.map { _ in rule.detail + "\n" + items.map(\.url.path).joined(separator: "\n") } ?? "")
            PlanRunningOwners(model: model, rule: rule).padding(.leading, CacheDropDesign.Space.xl).padding(.bottom, CacheDropDesign.Space.sm)
            if rule.choosesItems && !rule.groupsByProject { CatalogItemRows(model: model, rule: rule, listing: listing).padding(.leading, CacheDropDesign.Space.xl) }
            else if items.contains(where: { $0.group != nil }) { CatalogProfileRows(model: model, rule: rule, listing: listing).padding(.leading, CacheDropDesign.Space.xl) }
            Divider()
        }
        }
    }
}
