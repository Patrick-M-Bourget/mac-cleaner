import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// The Trash's `StatusRow` (#772) with an Open Trash link. With `empty`, an "Empty from Trash…" link for CacheDrop's own items
/// comes first (#359); with `emptyAll`, "Empty Trash…" for everything in it (#605, Decision 142); without `opensTrash`, no
/// Open Trash. Without `text`, the line is just its links (Results, #588).
struct TrashLine: View {
    let text: String?
    let identifier: String
    var empty: (() -> Void)? = nil
    var emptyAll: (() -> Void)? = nil
    var opensTrash = true
    var body: some View {
        let blocked = AppLifecycleController.shared.updateInstallation.blocksNewWork
        let actions = [
            empty.map { StatusAction(title: "Empty from Trash…", identifier: identifier + "Empty", isDisabled: blocked, action: $0) },
            emptyAll.map { StatusAction(title: "Empty Trash…", identifier: identifier + "EmptyAll", isDisabled: blocked, action: $0) },
            opensTrash ? StatusAction(title: "Open Trash", identifier: identifier + "Open") { TrashModel.shared.open() } : nil,
        ].compactMap { $0 }
        StatusRow(text: text ?? "", symbol: "trash", identifier: identifier, actions: actions).accessibilityElement(children: .contain)
    }
}
