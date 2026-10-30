import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// One quiet line with an Open Trash link, as `FullDiskAccessNote` is drawn (Decision 25). With `empty`, an "Empty from
/// Trash…" link for CacheDrop's own items comes first (#359); without `opensTrash`, it is the line's only link.
struct TrashLine: View {
    let text: String
    let identifier: String
    var empty: (() -> Void)? = nil
    var opensTrash = true
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.xs) {
            Image(systemName: "trash").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text + " ·").foregroundStyle(.secondary).accessibilityIdentifier(identifier)
            if let empty {
                Button("Empty from Trash…", action: empty).buttonStyle(.link).disabled(AppLifecycleController.shared.updateInstallation.blocksNewWork).accessibilityIdentifier(identifier + "Empty")
                if opensTrash { Text("·").foregroundStyle(.secondary).accessibilityHidden(true) }
            }
            if opensTrash { Button("Open Trash") { TrashModel.shared.open() }.buttonStyle(.link).accessibilityIdentifier(identifier + "Open") }
        }.font(CacheDropDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
