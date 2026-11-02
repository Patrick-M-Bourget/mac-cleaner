import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// Overview: "Trash holds X · Empty Trash… · Open Trash", only when its size is known and not 0. With CacheDrop's own
/// items in the Trash (#359): "Trash holds 9.4 GB · 7.1 GB from CacheDrop · Empty from Trash… · Empty Trash…", the whole
/// Trash's parts only when it can be read (#605, Decision 142).
struct TrashNote: View {
    private var model = TrashModel.shared
    @State private var sheet = EmptyFromTrashSheetState()
    var body: some View {
        // Measured by Overview's own task (`TrashModel.refresh`): a task here wouldn't run while the line is hidden.
        // The same line the menu bar menu says (Decision 141).
        let line = TrashContents.line(model.contents, fromCacheDrop: model.emptyableBytes)
        let own = model.emptyableBytes > 0
        let readable = if case .holds = model.contents { true } else { false }
        if let text = sheet.line(line) {
            TrashLine(text: text, identifier: "overviewTrash", empty: own ? { sheet.open(text) } : nil,
                      emptyAll: readable ? { openWholeTrash(text) } : nil, opensTrash: !own)
                .emptyFromTrashSheet($sheet.request)
                .onChange(of: model.wholeTrashRequested, initial: true) { _, requested in
                    if requested { model.wholeTrashRequested = false; openWholeTrash(text) }
                }
        }
    }
    private func openWholeTrash(_ text: String) {
        Task { sheet.open(wholeTrash: await model.reviewWholeTrash(), line: text) }
    }
}
