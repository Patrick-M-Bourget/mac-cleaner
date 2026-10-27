import AppKit
import Foundation
import Observation
import StillCore
import SwiftUI

/// One row per profile or app with its cache size; choosing a row chooses all of its folders.
struct CatalogProfileRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        let groups = Dictionary(grouping: model.candidates(for: rule)) { $0.group ?? "" }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { profile in
                let items = groups[profile] ?? []
                InspectableItemRow(name: profile, detail: items.map(\.url.lastPathComponent).sorted().joined(separator: ", "),
                                   size: catalogBytes(items.reduce(0) { $0 + $1.estimatedBytes }, complete: items.allSatisfy(\.sizeComplete)),
                                   symbol: items.contains { $0.appName != nil } ? "app" : "person.crop.circle", inspected: false,
                                   inspect: { Finder.reveal(items.map(\.url)) }, detailLineLimit: 1) {
                    Toggle("Select " + profile, isOn: Binding(get: { items.allSatisfy(model.isSelected) }, set: { on in items.forEach { model.setSelected($0, on) } }))
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planProfile-\(rule.id)-\(profile)")
                }.help(items.map(\.url.path).sorted().joined(separator: "\n"))
            }
        }
    }
}
