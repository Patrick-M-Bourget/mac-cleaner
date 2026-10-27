import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// A small "Put back" link for an item a run moved to the Trash (#159). Once used it reads "Put back", or why it couldn't.
struct PutBackLink: View {
    let record: CleanupRecord
    /// History already shows this item as put back.
    var alreadyPutBack = false
    /// Called after a put back that changed something, so History reloads.
    var didPutBack: () -> Void = {}
    @Bindable private var trash = TrashModel.shared
    var body: some View {
        let name = record.originalURL.lastPathComponent
        switch trash.putBackOutcomes[record.id] {
        case .restored:
            Text("Put back").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("putBackDone-" + name)
        case .refused(let refusal):
            Text(refusal.reason).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("putBackRefused-" + name)
        case nil:
            if alreadyPutBack {
                Text("Put back").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("putBackDone-" + name)
            } else if record.canPutBack {
                Button("Put back") {
                    Task {
                        await trash.putBack(record)
                        if trash.putBackOutcomes[record.id] != nil { didPutBack() }
                    }
                }.buttonStyle(.link).disabled(trash.puttingBack.contains(record.id))
                    .help("Return it from the Trash to " + PathDisplay.shortLocation(of: record.originalURL.path))
                    .accessibilityLabel("Put back \(name)").accessibilityIdentifier("putBack-" + name)
            }
        }
    }
}
