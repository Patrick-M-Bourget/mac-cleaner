import AppKit
import Foundation
import Observation
import StillCore
import SwiftUI

/// Single items a rule found (Downloads files, models, disk images), each chosen on its own. Nothing is preselected.
struct CatalogItemRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        let items = model.candidates(for: rule).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                InspectableItemRow(name: item.displayName, detail: detail(item), size: catalogBytes(item.estimatedBytes, estimate: item.sizeIsEstimate),
                                   symbol: item.isDirectory ? "folder" : "doc", inspected: false, inspect: { Finder.reveal([item.url]) },
                                   detailLineLimit: 1) {
                    Toggle("Select " + item.displayName, isOn: Binding(get: { model.isSelected(item) }, set: { model.setSelected(item, $0) }))
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planItem-" + item.displayName)
                }.help(item.url.path)
            }
        }
    }
    private func detail(_ item: Candidate) -> String {
        let folder = PathDisplay.shortLocation(of: item.url, home: CatalogCleanupModel.checkHome)
        return item.lastUsed.map { folder + " · Last used " + $0.formatted(date: .abbreviated, time: .omitted) } ?? folder
    }
}
