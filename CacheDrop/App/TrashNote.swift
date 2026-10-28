import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// Overview: "Trash holds X · Open Trash", only when its size is known and not 0. With CacheDrop's own items in the
/// Trash (#359): "Trash holds 9.4 GB · 7.1 GB from CacheDrop · Empty from Trash…", its first part only when readable.
struct TrashNote: View {
    private var model = TrashModel.shared
    @State private var sheet = EmptyFromTrashSheetState()
    var body: some View {
        // Measured by Overview's own task (`TrashModel.refresh`): a task here wouldn't run while the line is hidden.
        let fromCacheDrop = model.emptyableBytes > 0 ? (model.contents ?? .unknown).overviewText(fromCacheDrop: model.emptyableBytes) : nil
        if let text = sheet.line(fromCacheDrop) {
            TrashLine(text: text, identifier: "overviewTrash", empty: { sheet.open(text) }, opensTrash: false).emptyFromTrashSheet($sheet.request)
        } else if let text = model.contents?.overviewText {
            TrashLine(text: text, identifier: "overviewTrash")
        }
    }
}
