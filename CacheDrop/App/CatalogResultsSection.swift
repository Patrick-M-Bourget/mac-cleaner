import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// Results: outcomes first (skipped and failed items on top, with their reason), details on demand.
struct CatalogResultsSection: View {
    let result: CatalogExecutionResult
    let catalog: Catalog
    /// The disk is still to be read again a minute after the run's Docker prunes (#411).
    var settling = false
    /// What that check found, shown under the measured freed space (#411).
    var settledLine: String? = nil
    /// Scrolls the page's own scroll view to a result row, for the "Not cleaned" line (#374): `ScrollViewProxy.revealRow`.
    var reveal: (CleanupRecord.ID) -> Void = { _ in }
    /// One switch for every row's path and messages, so the list stays one line per item until asked.
    @State private var showsDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            if result.previewOnly {
                let previewed = result.records.filter(\.wasPreviewed)
                StatusRow(text: "Dry run · Nothing changed · " + catalogBytes(previewed.reduce(0) { $0 + $1.recordedBytes }, upperBound: upperBound(previewed)) + " would be affected",
                          symbol: "eye", role: .neutral, identifier: "catalogPreviewNotice")
            } else {
                // SPEC section 6: measured and estimated, reported separately; Trash is never counted as freed.
                // Everything went to the Trash (#312): nothing is freed yet, so no "Zero KB · Measured freed space".
                let onlyTrashed = result.records.movedOnlyToTrash
                SummarySurface {
                    HStack(alignment: .top, spacing: CacheDropDesign.Space.xl) {
                        if !onlyTrashed {
                            metric(MeasuredFreedSpace.shown(result.measuredFreedBytes).map { catalogBytes($0) } ?? SizeEstimate.unknown.text, "Measured freed space", followUp: settledLine)
                        }
                        let upperBound = upperBound(result.records)
                        metric(catalogBytes(result.estimatedBytes, upperBound: upperBound), upperBound ? "Estimated before cleanup · Upper bound" : "Estimated before cleanup")
                        if result.movedToTrashBytes > 0 { metric(catalogBytes(result.movedToTrashBytes), "In the Trash · Freed when you empty it") }
                    }
                }
                notCleaned
                // One explanation (Decision 25): while Docker hands space back, the note says a check is coming instead (#411).
                if settling {
                    HStack(spacing: CacheDropDesign.Space.sm) {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                        Text("Docker returns space to macOS over the next minute. CacheDrop will check again.")
                            .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("resultsSettling")
                    }
                } else if !onlyTrashed {
                    Text("Measured from the change in available space around each item. Other activity on this Mac can affect it.")
                        .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                }
                if result.movedToTrashBytes > 0 { TrashEmptyHint() }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(showsDetails ? "Hide paths and messages" : "Show paths and messages") { showsDetails.toggle() }
                        .buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption).accessibilityIdentifier("resultsDetailsToggle")
                }
                ForEach(result.records.attentionFirst) { record in
                    CatalogResultRow(record: record, rule: record.ruleID.flatMap { catalog.rule($0) }, showsDetails: showsDetails).id(record.id)
                    Divider()
                }
            }
            if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .caution) }
        }
    }
    /// What the run didn't clean (#374), in one line under the metrics that leads to those rows, listed first below.
    @ViewBuilder private var notCleaned: some View {
        let skipped = result.records.filter(\.needsAttention)
        if let first = skipped.first {
            Button("Not cleaned · " + CacheDropDesign.items(skipped.count) + " · " + catalogBytes(skipped.reduce(0) { $0 + $1.recordedBytes })) {
                reveal(first.id)
            }.buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption).accessibilityIdentifier("resultsNotCleaned")
        }
    }
    private func upperBound(_ records: [CleanupRecord]) -> Bool { records.contains { $0.ruleID.flatMap { catalog.rule($0)?.estimateIsUpperBound } == true } }
    /// A figure and its label; `followUp` adds a later finding below it, never into the figure (#411).
    private func metric(_ value: String, _ label: String, followUp: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            Text(value).font(CacheDropDesign.TypeStyle.value).monospacedDigit()
            Text(label).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            if let followUp { Text(followUp).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("resultsSettled") }
        }
    }
}

/// One result: name and short location, outcome and size; its reason when it needs attention; path and messages when shown.
private struct CatalogResultRow: View {
    let record: CleanupRecord
    let rule: CleanupRule?
    let showsDetails: Bool
    private var showsFolder: Bool { rule?.showsFolder ?? true }
    private var name: String {
        let file = record.originalURL.lastPathComponent
        return record.itemName ?? record.uninstalledName ?? rule?.itemName?(file) ?? (rule?.choosesItems == true ? file : rule?.title ?? file)
    }
    var body: some View {
        let role: StatusRole = record.state == .succeeded ? .success : record.wasPreviewed ? .neutral : .caution
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.md) {
                Image(systemName: record.state == .succeeded ? "checkmark.circle" : record.wasPreviewed ? "eye" : "exclamationmark.circle").foregroundStyle(role.color)
                    .frame(width: CacheDropDesign.Space.lg)
                // Docker's rows have no folder of their own to show (#420).
                (Text(name).font(CacheDropDesign.TypeStyle.rowTitle)
                    + Text(showsFolder ? " · " + PathDisplay.shortLocation(of: record.originalURL, home: CatalogCleanupModel.checkHome) : "").foregroundStyle(.secondary))
                    .lineLimit(1).help(showsFolder ? record.originalURL.path : "")
                Spacer(minLength: CacheDropDesign.Space.md)
                if record.state == .succeeded, let trashed = record.trashURL {
                    if TrashModel.shared.putBackOutcomes[record.id] == nil, !TrashModel.shared.emptiedIDs.contains(record.id) {
                        Button("Reveal in Trash") { Finder.reveal([trashed]) }.buttonStyle(.link)
                            .accessibilityLabel("Reveal \(record.originalURL.lastPathComponent) in Trash")
                    }
                    PutBackLink(record: record)
                }
                Text(record.outcomeTitle).font(CacheDropDesign.TypeStyle.note)
                Text(catalogBytes(record.recordedBytes)).font(CacheDropDesign.TypeStyle.note).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                if record.needsAttention || record.finishedAfterStop { Text(record.message).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let later = record.laterMeasurementText {
                    Text(later).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("laterMeasurement-" + (record.ruleID ?? ""))
                }
                if showsDetails {
                    if showsFolder { Text(record.originalURL.path).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    if !record.needsAttention && !record.finishedAfterStop { Text(record.message).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                    if let output = record.toolOutput {
                        Text(output).font(CacheDropDesign.TypeStyle.code).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("toolOutput-" + (record.ruleID ?? ""))
                    }
                }
            }.padding(.leading, CacheDropDesign.Space.lg + CacheDropDesign.Space.md)
        }.padding(.vertical, CacheDropDesign.Space.md)
    }
}

extension ScrollViewProxy {
    /// Brings a result row to the top of the page's scroll view (#374). A `ScrollViewReader` reaches only scroll views inside
    /// it, so each page that shows results reads its own and hands this down.
    func revealRow(_ id: CleanupRecord.ID) { withAnimation { scrollTo(id, anchor: .top) } }
}
