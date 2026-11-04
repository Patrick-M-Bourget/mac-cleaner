import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// One quiet line with an Open Trash link, as `FullDiskAccessNote` is drawn (Decision 25). With `empty`, an "Empty from
/// Trash…" link for CacheDrop's own items comes first (#359); with `emptyAll`, "Empty Trash…" for everything in it
/// (#605, Decision 142); without `opensTrash`, no Open Trash. Without `text`, the line is just its links (Results, #588).
struct TrashLine: View {
    let text: String?
    let identifier: String
    var empty: (() -> Void)? = nil
    var emptyAll: (() -> Void)? = nil
    var opensTrash = true
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.xs) {
            Image(systemName: "trash").foregroundStyle(.secondary).accessibilityHidden(true)
            if let text { Text(text + " ·").foregroundStyle(.secondary).accessibilityIdentifier(identifier) }
            let links: [(title: String, id: String, action: () -> Void)] = [
                empty.map { ("Empty from Trash…", identifier + "Empty", $0) },
                emptyAll.map { ("Empty Trash…", identifier + "EmptyAll", $0) },
                opensTrash ? ("Open Trash", identifier + "Open", { TrashModel.shared.open() }) : nil,
            ].compactMap { $0 }
            ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                if index > 0 { Text("·").foregroundStyle(.secondary).accessibilityHidden(true) }
                Button(link.title, action: link.action).buttonStyle(.link)
                    .disabled(link.id != identifier + "Open" && AppLifecycleController.shared.updateInstallation.blocksNewWork)
                    .accessibilityIdentifier(link.id)
            }
        }.font(CacheDropDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
