import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// Results after a run moved items to the Trash (#359): "Open Trash", while CacheDrop's own items are still there, read
/// after the run. Empty from Trash… is the bar's prominent button meanwhile (#782, Decision 177). The summary's In the Trash
/// figure already says how much, so the line has no size or sentence of its own (#588, Decision 92 rule 2). With none left, no line.
struct TrashEmptyHint: View {
    @State private var measured = false
    private var trash = TrashModel.shared
    var body: some View {
        // A stack, not a Group: a Group passes `.task` to its children, and with the line not shown yet it has none, so the
        // reading after the run never started and the line never appeared (#392).
        VStack(alignment: .leading, spacing: 0) {
            // The shared reading, so a put back (#159) or an emptying updates the line too.
            if measured, trash.emptyableBytes > 0 { TrashLine(text: nil, identifier: "resultsTrash") }
        }.task { await trash.refresh(); measured = true }
    }
}

/// Results' bottom bar button while the run moved CacheDrop's own items to the Trash and they're still there (#782,
/// Decision 177): **Empty from Trash…**, prominent, so a first clean frees space for real. It opens the line's old sheet and
/// stays while the sheet is open; otherwise it's absent and the bar's own finish button leads.
struct ResultsEmptyFromTrashButton: View {
    let result: CatalogExecutionResult?
    @State private var sheet = EmptyFromTrashSheetState()
    private var trash = TrashModel.shared
    init(result: CatalogExecutionResult?) { self.result = result }
    /// Whether the bar leads with it, as `CatalogExecutionResult.leadsWithEmptyFromTrash` says.
    @MainActor static func leads(_ result: CatalogExecutionResult?) -> Bool {
        result?.leadsWithEmptyFromTrash(cacheDropBytesInTrash: TrashModel.shared.emptyable?.bytes) == true
    }
    var body: some View {
        if Self.leads(result) || sheet.request != nil {
            Button("Empty from Trash…") { sheet.open() }.buttonStyle(.borderedProminent)
                .disabled(AppLifecycleController.shared.updateInstallation.blocksNewWork)
                .accessibilityIdentifier("resultsEmptyFromTrash")
                .emptyFromTrashSheet($sheet.request)
        }
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
        heldLine = line; request = EmptyFromTrashRequest(scope: .cacheDropItems(items))
    }
    /// Opens Empty Trash… with everything in the Trash as read now (#605); with nothing readable, measures again instead.
    @MainActor mutating func open(wholeTrash review: WholeTrashReview?, line: String?) {
        guard let review else { Task { await TrashModel.shared.refresh() }; return }
        heldLine = line; request = EmptyFromTrashRequest(scope: .wholeTrash(review.items))
    }
}

/// What the sheet was opened with: the items offered at that moment, checked again when Empty is clicked.
struct EmptyFromTrashRequest: Identifiable {
    let id = UUID()
    let scope: EmptyingScope
}

/// What a Trash sheet deletes: CacheDrop's own items (#359), or everything in the Trash (#605, Decision 142).
enum EmptyingScope {
    case cacheDropItems([CleanupRecord])
    case wholeTrash([TrashItem])

    var title: String {
        switch self { case .cacheDropItems: "Empty from Trash"; case .wholeTrash: "Empty the Trash" }
    }
    var note: String {
        switch self {
        case .cacheDropItems: "Deleted permanently. They can’t be put back."
        case .wholeTrash: "Everything in the Trash, including files you put there yourself, is deleted permanently. It can’t be put back."
        }
    }
    /// Each item by name, with its size and full path.
    var rows: [(id: String, name: String, bytes: Int64, path: String)] {
        switch self {
        case .cacheDropItems(let items): items.map { ($0.id, $0.itemName ?? $0.originalURL.lastPathComponent, $0.recordedBytes, $0.originalURL.path) }
        case .wholeTrash(let items): items.map { ($0.id, $0.name, $0.bytes, $0.url.path) }
        }
    }
    @MainActor func empty() async {
        switch self {
        case .cacheDropItems(let items): await TrashModel.shared.empty(items)
        case .wholeTrash(let items): await TrashModel.shared.emptyWholeTrash(items)
        }
    }
}

extension View {
    /// Presents the sheet that deletes CacheDrop's own items from the Trash (#359).
    func emptyFromTrashSheet(_ request: Binding<EmptyFromTrashRequest?>) -> some View {
        sheet(item: request) { item in EmptyFromTrashSheet(scope: item.scope) { request.wrappedValue = nil } }
    }
}

/// The review sheet for emptying (#359, #605): the items, what happens to them and one Empty button that shows busy while
/// it runs; then what happened to each, skipped ones with their reason.
struct EmptyFromTrashSheet: View {
    let scope: EmptyingScope
    let close: () -> Void
    @Bindable private var trash = TrashModel.shared
    private var dryRun: Bool { AppLifecycleController.shared.selection.catalog.dryRun }
    var body: some View {
        ReviewSheetFrame(title: scope.title) {
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
                Button("Empty") { Task { await scope.empty() } }.buttonStyle(.borderedProminent).disabled(AppLifecycleController.shared.updateInstallation.blocksNewWork).accessibilityIdentifier("emptyFromTrashConfirm")
            }
        }
    }

    @ViewBuilder private var review: some View {
        if dryRun { StatusRow(text: "Dry run · Nothing changes", symbol: "eye", role: .neutral, identifier: "emptyPreviewNotice") }
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            heading
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                Text(scope.note).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(scope.rows, id: \.id) { row in line(name: row.name, path: row.path, trailing: SizeFormatter.text(row.bytes)) }
            }.padding(.leading, CacheDropDesign.Size.badgeIndent)
        }
    }
    private var heading: some View {
        HStack(spacing: CacheDropDesign.Space.md) {
            ConsequenceGroup.permanentlyRemoved.badge
            Text(CacheDropDesign.items(scope.rows.count)).font(CacheDropDesign.TypeStyle.section)
            Spacer()
            Text(SizeFormatter.text(scope.rows.reduce(0) { $0 + $1.bytes })).font(CacheDropDesign.TypeStyle.section).monospacedDigit()
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
            line(name: record.itemName ?? record.originalURL.lastPathComponent, path: record.originalURL.path, trailing: record.outcomeTitle)
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
    private func line(name: String, path: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).lineLimit(1).truncationMode(.middle).help(path)
            Spacer()
            Text(trailing).monospacedDigit()
        }.font(CacheDropDesign.TypeStyle.note).accessibilityElement(children: .combine).accessibilityIdentifier("emptyItem-" + (path as NSString).lastPathComponent)
    }
}
