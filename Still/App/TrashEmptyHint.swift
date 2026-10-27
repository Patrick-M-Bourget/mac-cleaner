import AppKit
import Observation
import StillCore
import SwiftUI

/// Results after a run moved items to the Trash: "Empty the Trash in Finder to free X · Open Trash", measured after the run.
struct TrashEmptyHint: View {
    let movedBytes: Int64
    @State private var measured = false
    var body: some View {
        Group {
            // The shared measurement, so a put back (#159) updates the line too.
            if measured, let text = (TrashModel.shared.contents ?? .unknown).emptyHint(movedBytes: movedBytes) { TrashLine(text: text, identifier: "resultsTrash") }
        }.task { await TrashModel.shared.refresh(); measured = true }
    }
}
