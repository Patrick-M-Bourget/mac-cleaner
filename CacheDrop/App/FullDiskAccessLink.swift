import SwiftUI

/// One `StatusRow` (#772) for every place CacheDrop couldn't read without Full Disk Access: "2 locations need Full Disk Access",
/// then Learn more. The places are named in its tooltip and accessibility value. Learn more asks the window's presenter
/// for the sheet (#802), so a grant that clears the note leaves the sheet open on its granted Done.
struct FullDiskAccessNote: View {
    let places: [String]
    @Environment(\.showFullDiskAccess) private var showFullDiskAccess
    var body: some View {
        StatusRow(text: (places.count == 1 ? "1 location needs" : "\(places.count) locations need") + " Full Disk Access", symbol: "lock.shield",
                  detail: places.joined(separator: ", "), action: StatusAction(title: "Learn more", identifier: "fullDiskAccessLink") { showFullDiskAccess?() })
            .accessibilityElement(children: .contain)
    }
}

/// Presents the Full Disk Access sheet for every note below it (#802): it outlives the notes, which a rescan removes.
private struct FullDiskAccessSheetPresenter: ViewModifier {
    @State private var showing = false
    @State private var model = FullDiskAccessModel()
    func body(content: Content) -> some View {
        content
            // A fresh model each time, so the sheet starts from Checking…, never from an earlier opening's status.
            .environment(\.showFullDiskAccess) { model = FullDiskAccessModel(); showing = true }
            .sheet(isPresented: $showing) { FullDiskAccessSheet(model: model) { showing = false } }
    }
}

private struct ShowFullDiskAccessKey: EnvironmentKey { static var defaultValue: (() -> Void)? { nil } }
extension EnvironmentValues {
    /// Opens the window's Full Disk Access sheet; nil where nothing presents it.
    var showFullDiskAccess: (() -> Void)? { get { self[ShowFullDiskAccessKey.self] } set { self[ShowFullDiskAccessKey.self] = newValue } }
}
extension View {
    /// The one place the window's Full Disk Access notes open their sheet from (#802).
    func fullDiskAccessSheetPresenter() -> some View { modifier(FullDiskAccessSheetPresenter()) }
}
