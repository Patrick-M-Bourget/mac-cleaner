import SwiftUI

/// One `StatusRow` (#772) for every place CacheDrop couldn't read without Full Disk Access: "2 locations need Full Disk Access",
/// then Learn more. The places are named in its tooltip and accessibility value.
struct FullDiskAccessNote: View {
    let places: [String]
    @State private var showing = false
    var body: some View {
        StatusRow(text: (places.count == 1 ? "1 location needs" : "\(places.count) locations need") + " Full Disk Access", symbol: "lock.shield",
                  detail: places.joined(separator: ", "), action: StatusAction(title: "Learn more", identifier: "fullDiskAccessLink") { showing = true })
            .accessibilityElement(children: .contain)
            .sheet(isPresented: $showing) { FullDiskAccessSheet(model: FullDiskAccessModel()) { showing = false } }
    }
}
