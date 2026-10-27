import SwiftUI

/// A row for something CacheDrop couldn't read, such as a rule that declares `requiresFullDiskAccess`.
/// It always offers the same explanation.
struct NotAccessibleRow: View {
    let title: String
    var detail = "macOS protects this location. You can continue without it."
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            HStack {
                Text(title).font(CacheDropDesign.TypeStyle.section)
                Spacer()
                Text("Not accessible").font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
            }
            Text(detail).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FullDiskAccessLink(title: "Review access options")
        }.accessibilityElement(children: .contain)
    }
}
