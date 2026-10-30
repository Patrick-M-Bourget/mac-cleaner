import SwiftUI

/// Opens the shared Full Disk Access explanation. Every "not accessible" place uses this.
struct FullDiskAccessLink: View {
    let title: String
    var model: FullDiskAccessModel?
    @State private var showing = false
    var body: some View {
        Button(title) { showing = true }
            .buttonStyle(.link)
            .accessibilityIdentifier("fullDiskAccessLink")
            .sheet(isPresented: $showing) { FullDiskAccessSheet(model: model ?? FullDiskAccessModel()) { showing = false } }
    }
}

/// One quiet line for every place CacheDrop couldn't read without Full Disk Access: "2 locations need Full Disk Access · Learn more".
/// The places are named in its tooltip and accessibility value.
struct FullDiskAccessNote: View {
    let places: [String]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.xs) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityHidden(true)
            Text((places.count == 1 ? "1 location needs" : "\(places.count) locations need") + " Full Disk Access ·").foregroundStyle(.secondary)
                .help(places.joined(separator: ", ")).accessibilityValue(places.joined(separator: ", "))
            FullDiskAccessLink(title: "Learn more")
        }.font(CacheDropDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
