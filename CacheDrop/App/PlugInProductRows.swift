import CacheDropCore
import SwiftUI

/// The audio plug-ins by product (#174, Decision 42), under the Audio plug-ins row: maker, version, formats,
/// architectures, place and size, each with Reveal in Finder. Read-only: nothing here is chosen or removed.
struct PlugInProductRows: View {
    @Bindable var model: CatalogCleanupModel
    let inventory: PlugInInventory
    var body: some View {
        ActionDisclosureGroup("Show products · \(inventory.products.count)") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(inventory.products) { product in
                    InspectableItemRow(name: product.name, detail: detail(product), size: product.size.text, symbol: "pianokeys",
                                       inspected: false, inspect: { model.reveal(product) }) { EmptyView() }
                        .help(product.files.map(\.url.path).joined(separator: "\n"))
                }
            }
        }.padding(.horizontal, CacheDropDesign.Space.lg).padding(.bottom, CacheDropDesign.Space.md)
    }
    /// "Maker · 2.1 · AU, VST3 · Apple silicon, Intel · /Library/Audio/Plug-Ins". Apple's own say so, since they come with macOS.
    private func detail(_ product: PlugInProduct) -> String {
        // An AUv3 lives inside its app, which is the place that matters.
        let folders = Set(product.files.map { file in
            file.format == .auv3 ? "In " + file.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                : PathDisplay.shortLocation(of: file.url, home: CatalogCleanupModel.checkHome)
        })
        let place = folders.count == 1 ? folders.first! : "\(folders.count) places"
        let parts: [String?] = [product.isApple ? "Apple · comes with macOS" : product.maker, product.versions.joined(separator: ", "),
                     product.formats.map(\.rawValue).joined(separator: ", "), product.architectures.joined(separator: ", "), place]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
