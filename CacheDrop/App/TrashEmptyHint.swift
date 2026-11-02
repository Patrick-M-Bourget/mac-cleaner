import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// Results after a run moved items to the Trash (#359): "Empty from Trash… · Open Trash", while CacheDrop's own items are
/// still there, read after the run. The summary's In the Trash figure already says how much, so the line has no size or
/// sentence of its own (#588, Decision 92 rule 2). With none left, no line.
struct TrashEmptyHint: View {
    @State private var measured = false
    @State private var sheet = EmptyFromTrashSheetState()
    private var trash = TrashModel.shared
    var body: some View {
        // A stack, not a Group: a Group passes `.task` to its children, and with the line not shown yet it has none, so the
        // reading after the run never started and the line never appeared (#392).
        VStack(alignment: .leading, spacing: 0) {
            // The shared reading, so a put back (#159) or an emptying updates the line too; it stays while its sheet is open.
            if measured, trash.emptyableBytes > 0 || sheet.request != nil {
                TrashLine(text: nil, identifier: "resultsTrash", empty: { sheet.open() }).emptyFromTrashSheet($sheet.request)
            }
        }.task { await trash.refresh(); measured = true }
    }
}

/// A Trash line's sheet (#359): what it was opened with, and the line's text while it is open, so the line (and with it
/// the sheet) stays after its items are deleted, until Done.
struct EmptyFromTrashSheetState {
    var request: EmptyFromTrashRequest?
    private var heldLine: String?
    /// The line to show: `current`, or while the sheet is open the one it was opened from.
    func line(_ current: String?) -> String? { current ?? (request != nil ? heldLine : nil) }
    @MainActor mutating func open(_ line: String? = nil) {
        guard let items = TrashModel.shared.emptyable?.items, !items.isEmpty else { return }
        heldLine = line; request = EmptyFromTrashRequest(items: items)
    }
}

/// What the sheet was opened with: the items offered at that moment, checked again when Empty is clicked.
struct EmptyFromTrashRequest: Identifiable {
    let id = UUID()
    let items: [CleanupRecord]
}

extension View {
    /// Presents the sheet that deletes CacheDrop's own items from the Trash (#359).
    func emptyFromTrashSheet(_ request: Binding<EmptyFromTrashRequest?>) -> some View {
        sheet(item: request) { item in EmptyFromTrashSheet(items: item.items) { request.wrappedValue = nil } }
    }
}

/// The review sheet for emptying (#359): the items, what happens to them and one Empty button that shows busy while it
/// runs; then what happened to each, skipped ones with their reason.
struct EmptyFromTrashSheet: View {
    let items: [CleanupRecord]
    let close: () -> Void
    @Bindable private var trash = TrashModel.shared
    private var dryRun: Bool { AppLifecycleController.shared.selection.catalog.dryRun }
    var body: some View {
        ReviewSheetFrame(title: "Empty from the Trash") {
            if let result = trash.emptyingResult { outcome(result) } else { review }
        } actions: {
            actions
        }.accessibilityIdentifier("emptyFromTrashSheet")
            .onAppear { trash.dismissEmptyingResult() }
    }

    @ViewBuilder private var actions: some View {
        if trash.emptyingResult != nil {
            Button("Done") { trash.dismissEmptyingResult(); close() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("emptyFromTrashDone")
        } else {
            Button("Cancel", action: close).keyboardShortcut(.cancelAction).disabled(trash.isEmptying)
            BusyAction(busy: trash.isEmptying) {
                Button("Empty") { Task { await trash.empty(items) } }.buttonStyle(.borderedProminent).disabled(AppLifecycleController.shared.updateInstallation.blocksNewWork).accessibilityIdentifier("emptyFromTrashConfirm")
            }
        }
    }

    @ViewBuilder private var review: some View {
        if dryRun { StatusRow(text: "Dry run is on. Nothing on disk changes.", symbol: "eye", role: .neutral, identifier: "emptyPreviewNotice") }
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            heading
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                Text("Deleted permanently. They can’t be put back.").font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                ForEach(items) { item in line(item, trailing: SizeFormatter.text(item.recordedBytes)) }
            }.padding(.leading, CacheDropDesign.Size.badgeIndent)
        }
    }
    private var heading: some View {
        HStack(spacing: CacheDropDesign.Space.md) {
            ConsequenceGroup.permanentlyRemoved.badge
            Text(CacheDropDesign.items(items.count)).font(CacheDropDesign.TypeStyle.section)
            Spacer()
            Text(SizeFormatter.text(items.reduce(0) { $0 + $1.recordedBytes })).font(CacheDropDesign.TypeStyle.section).monospacedDigit()
        }
    }

    @ViewBuilder private func outcome(_ result: TrashEmptyingResult) -> some View {
        StatusRow(text: summary(result), symbol: result.dryRun ? "eye" : "checkmark.circle", role: result.dryRun ? .neutral : .success,
                  identifier: "emptyFromTrashSummary")
        if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .caution) }
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            ForEach(result.records.attentionFirst) { record in outcomeRow(record) }
        }
    }
    private func outcomeRow(_ record: CleanupRecord) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            line(record, trailing: record.outcomeTitle)
            if record.needsAttention {
                Text(record.message).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// "Dry run · Nothing changed", or what was deleted and the space measured around each item (SPEC section 6).
    private func summary(_ result: TrashEmptyingResult) -> String {
        if result.dryRun { return "Dry run · Nothing changed" }
        let deleted = "Deleted " + CacheDropDesign.items(result.deletedCount) + " from the Trash"
        guard result.deletedCount > 0 else { return deleted }
        return deleted + " · Measured freed space: " + (MeasuredFreedSpace.shown(result.measuredFreedBytes).map { SizeFormatter.text($0) } ?? SizeEstimate.unknown.text)
    }
    /// One item, by name, then its size or outcome.
    private func line(_ record: CleanupRecord, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(record.itemName ?? record.originalURL.lastPathComponent).lineLimit(1).truncationMode(.middle).help(record.originalURL.path)
            Spacer()
            Text(trailing).monospacedDigit()
        }.font(CacheDropDesign.TypeStyle.note).accessibilityElement(children: .combine).accessibilityIdentifier("emptyItem-" + record.originalURL.lastPathComponent)
    }
}
