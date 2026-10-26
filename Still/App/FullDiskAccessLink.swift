import SwiftUI

/// Opens the shared Full Disk Access explanation. Every "not accessible" place uses this.
struct FullDiskAccessLink: View {
    var title = "Learn about broader access"
    var model: FullDiskAccessModel?
    @State private var showing = false
    var body: some View {
        Button(title, systemImage: "lock.shield") { showing = true }
            .buttonStyle(.link)
            .accessibilityIdentifier("fullDiskAccessLink")
            .sheet(isPresented: $showing) { FullDiskAccessSheet(model: model ?? FullDiskAccessModel()) { showing = false } }
    }
}
