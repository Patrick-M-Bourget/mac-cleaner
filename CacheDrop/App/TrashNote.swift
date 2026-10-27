import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// Overview: "Trash holds X · Open Trash", only when its size is known and not 0.
struct TrashNote: View {
    private var model = TrashModel.shared
    var body: some View {
        // Measured by Overview's own task (`TrashModel.refresh`): a task here wouldn't run while the line is hidden.
        if let text = model.contents?.overviewText { TrashLine(text: text, identifier: "overviewTrash") }
    }
}
