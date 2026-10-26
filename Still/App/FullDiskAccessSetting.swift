import StillCore
import SwiftUI

/// The Locations & access row: current state plus the shared explanation.
struct FullDiskAccessSetting: View {
    @State private var model = FullDiskAccessModel()
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            StatusRow(text: "Full Disk Access · " + (model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…"),
                      symbol: "lock.shield", role: model.status == .granted ? .success : .neutral, identifier: "fullDiskAccessStatus")
            Text("Optional. Broad access can include sensitive Mail and Messages data.")
                .font(StillDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FullDiskAccessLink(model: model)
        }.task { await model.refresh() }
    }
}
