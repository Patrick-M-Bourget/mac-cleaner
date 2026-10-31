import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// One row per profile, app or project with its size; choosing a row chooses all of its folders.
struct CatalogProfileRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    /// The Applications page's sort and search, for its leftover groups (#295); nil lists every group by name.
    var listing: ApplicationsListing? = nil
    var sort: ListSort? = nil
    var body: some View {
        let groups = Dictionary(grouping: model.candidates(for: rule).filter { listing?.matches($0) ?? true }) { $0.group ?? "" }
        let order = sort ?? listing?.sort ?? ListSort(column: .name, ascending: true)
        let names = sort == nil ? Array(groups.keys) : groups.keys.sorted()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(order.ordered(names, name: { $0 }, bytes: {
                sort == nil ? groups[$0, default: []].reduce(0) { $0 + $1.estimatedBytes }
                    : SizeEstimate(sum: groups[$0, default: []].map(SizeEstimate.init)).sortBytes
            }), id: \.self) { profile in
                let items = groups[profile] ?? []
                let ticked = Binding(get: { items.allSatisfy(model.isSelected) }, set: { on in items.forEach { model.setSelected($0, on) } })
                // Clicking the row ticks the group, as its checkbox does; Finder is its own Reveal link (#367, Decision 72).
                InspectableItemRow(name: profile, detail: detail(items),
                                   size: SizeFormatter.text(SizeEstimate(sum: items.map(SizeEstimate.init)), upperBound: rule.estimateIsUpperBound),
                                   symbol: rule.groupsByProject ? "folder" : items.contains { $0.appName != nil } ? "app" : "person.crop.circle", inspected: false,
                                   inspect: rule.itemRowClick == .tick ? { if model.canEdit { ticked.wrappedValue.toggle() } } : nil, detailLineLimit: 1,
                                   actionLabel: "Select " + profile, reveal: { Finder.reveal(items.map(\.url)) },
                                   revealIdentifier: "planProfileReveal-\(rule.id)-\(profile)") {
                    Toggle("Select " + profile, isOn: ticked)
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planProfile-\(rule.id)-\(profile)")
                }.help(items.map(\.url.path).sorted().joined(separator: "\n"))
            }
        }
    }
    /// The folders' names; for a project, also when it last changed (#157).
    private func detail(_ items: [Candidate]) -> String {
        // A project being worked on (#374): unticked, saying why.
        if let hold = items.lazy.compactMap(\.hold).first { return hold.line }
        let names = items.map(\.url.lastPathComponent).sorted().joined(separator: ", ")
        guard rule.groupsByProject, let changed = items.compactMap(\.lastUsed).max() else { return names }
        return names + " · Modified " + changed.formatted(date: .abbreviated, time: .omitted)
    }
}
