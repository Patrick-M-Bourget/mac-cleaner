import SwiftUI

/// Opens the shared Full Disk Access explanation. Every "not accessible" place uses this.
struct FullDiskAccessLink: View {
    var title = "Learn about broader access"
    var model: FullDiskAccessModel?
    /// nil draws the link as text only, as inside `FullDiskAccessNote`.
    var symbol: String? = "lock.shield"
    @State private var showing = false
    var body: some View {
        Group {
            if let symbol { Button(title, systemImage: symbol) { showing = true } } else { Button(title) { showing = true } }
        }
            .buttonStyle(.link)
            .accessibilityIdentifier("fullDiskAccessLink")
            .sheet(isPresented: $showing) { FullDiskAccessSheet(model: model ?? FullDiskAccessModel()) { showing = false } }
    }
}

/// One quiet line for every place Still couldn't read without Full Disk Access: "2 locations need Full Disk Access · Learn more".
/// The places are named in its tooltip and accessibility value.
struct FullDiskAccessNote: View {
    let places: [String]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.xs) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityHidden(true)
            Text((places.count == 1 ? "1 location needs" : "\(places.count) locations need") + " Full Disk Access ·").foregroundStyle(.secondary)
                .help(places.joined(separator: ", ")).accessibilityValue(places.joined(separator: ", "))
            FullDiskAccessLink(title: "Learn more", symbol: nil)
        }.font(StillDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
