import AppKit
import Observation
import StillCore
import SwiftUI

/// Results after a run moved items to the Trash: "Empty the Trash in Finder to free X · Open Trash", measured after the run.
struct TrashEmptyHint: View {
    let movedBytes: Int64
    @State private var measured: TrashContents?
    var body: some View {
        Group {
            if let text = measured?.emptyHint(movedBytes: movedBytes) { TrashLine(text: text, identifier: "resultsTrash") }
        }.task { measured = await TrashModel.shared.refresh() ?? .unknown }
    }
}
