import AppKit
import Observation
import StillCore
import SwiftUI

/// One quiet line with an Open Trash link, as `FullDiskAccessNote` is drawn (Decision 25).
struct TrashLine: View {
    let text: String
    let identifier: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.xs) {
            Image(systemName: "trash").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text + " ·").foregroundStyle(.secondary).accessibilityIdentifier(identifier)
            Button("Open Trash") { TrashModel.shared.open() }.buttonStyle(.link).accessibilityIdentifier(identifier + "Open")
        }.font(StillDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
