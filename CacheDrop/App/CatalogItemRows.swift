import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// Single items a rule found (Downloads files, models, disk images), each chosen on its own. Nothing is preselected.
struct CatalogItemRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    /// Only this installed app's items, on its Applications row (#177).
    var app: String? = nil
    /// The Applications page's Sort and search, for its leftovers (#295); nil lists every item by name.
    var listing: ApplicationsListing? = nil
    var body: some View {
        let found = model.candidates(for: rule).filter { app.map($0.isUninstalled(with:)) ?? true }
        let items = listing.map { $0.ordered(found.filter($0.matches), name: \.displayName, bytes: \.estimatedBytes) }
            ?? found.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                // Clicking the row ticks the item, as its checkbox does; Finder is its own Reveal link (#356, #367, Decision 72).
                InspectableItemRow(name: item.displayName, detail: detail(item), size: catalogBytes(item.estimatedBytes, estimate: item.sizeIsEstimate),
                                   symbol: item.isDirectory ? "folder" : "doc", inspected: false,
                                   inspect: rule.itemRowClick == .tick ? { if model.canEdit { model.setSelected(item, !model.isSelected(item)) } } : nil,
                                   detailLineLimit: 1, actionLabel: "Select " + item.displayName,
                                   reveal: { Finder.reveal([item.url]) }, revealIdentifier: "planItemReveal-" + item.displayName) {
                    Toggle("Select " + item.displayName, isOn: Binding(get: { model.isSelected(item) }, set: { model.setSelected(item, $0) }))
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planItem-" + item.displayName)
                }.help(item.url.path)
            }
        }
    }
    private func detail(_ item: Candidate) -> String {
        // A possibly related leftover says why it is shown (#173).
        if let reason = item.leftover?.reason { return reason }
        // A plug-in item other products use too (#176, Decision 52).
        if let shared = item.sharedLabel { return shared }
        let folder = PathDisplay.shortLocation(of: item.url, home: CatalogCleanupModel.checkHome)
        return item.lastUsed.map { folder + " · Last used " + $0.formatted(date: .abbreviated, time: .omitted) } ?? folder
    }
}
