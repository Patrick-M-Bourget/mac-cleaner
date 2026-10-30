import CacheDropCore
import SwiftUI

/// The Locations & access settings row: Full Disk Access, its current state and the shared explanation.
struct FullDiskAccessSetting: View {
    @State private var model = FullDiskAccessModel()
    var body: some View {
        RecommendationGroup {
            HStack(spacing: CacheDropDesign.Space.md) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary).frame(width: CacheDropDesign.Size.rowIcon).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                    Text("Full Disk Access").font(CacheDropDesign.TypeStyle.rowTitle)
                    Text("Optional. Broad access can include sensitive Mail and Messages data.")
                        .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…")
                    .foregroundStyle(model.status == .granted ? StatusRole.success.color : StatusRole.neutral.color)
                    .accessibilityLabel("Full Disk Access · " + (model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…"))
                    .accessibilityIdentifier("fullDiskAccessStatus")
                FullDiskAccessLink(title: "Learn more", model: model)
            }.padding(CacheDropDesign.Space.lg)
        }.task { await model.refresh() }
    }
}
