import AppKit
import Foundation
import Observation
import StillCore
import SwiftUI

/// Results: outcomes first (skipped and failed items on top, with their reason), details on demand.
struct CatalogResultsSection: View {
    let result: CatalogExecutionResult
    let catalog: Catalog
    /// One switch for every row's path and messages, so the list stays one line per item until asked.
    @State private var showsDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if result.previewOnly {
                let previewed = result.records.filter(\.wasPreviewed)
                StatusRow(text: "Dry run · Nothing changed · " + catalogBytes(previewed.reduce(0) { $0 + $1.recordedBytes }, upperBound: upperBound(previewed)) + " would be affected",
                          symbol: "eye", role: .neutral, identifier: "catalogPreviewNotice")
            } else {
                // SPEC section 6: measured and estimated, reported separately; Trash is never counted as freed.
                SummarySurface {
                    HStack(alignment: .top, spacing: StillDesign.Space.xl) {
                        metric(result.measuredFreedBytes.map { catalogBytes($0) } ?? SizeEstimate.unknown.text, "Measured freed space")
                        let upperBound = upperBound(result.records)
                        metric(catalogBytes(result.estimatedBytes, upperBound: upperBound), upperBound ? "Estimated before cleanup · Upper bound" : "Estimated before cleanup")
                        if result.movedToTrashBytes > 0 { metric(catalogBytes(result.movedToTrashBytes), "Moved to Trash · Not yet freed") }
                    }
                }
                Text("Measured from the change in available space around each item. Other activity on this Mac can affect it.")
                    .font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                if result.movedToTrashBytes > 0 { TrashEmptyHint(movedBytes: result.movedToTrashBytes) }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(showsDetails ? "Hide paths and messages" : "Show paths and messages") { showsDetails.toggle() }
                        .buttonStyle(.link).font(StillDesign.TypeStyle.caption).accessibilityIdentifier("resultsDetailsToggle")
                }
                ForEach(result.records.attentionFirst) { record in
                    CatalogResultRow(record: record, rule: record.ruleID.flatMap { catalog.rule($0) }, showsDetails: showsDetails)
                    Divider()
                }
            }
            if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .caution) }
        }
    }
    private func upperBound(_ records: [CleanupRecord]) -> Bool { records.contains { $0.ruleID.flatMap { catalog.rule($0)?.estimateIsUpperBound } == true } }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Text(value).font(StillDesign.TypeStyle.value).monospacedDigit()
            Text(label).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
        }
    }
}

/// One result: name and short location, outcome and size; its reason when it needs attention; path and messages when shown.
private struct CatalogResultRow: View {
    let record: CleanupRecord
    let rule: CleanupRule?
    let showsDetails: Bool
    private var name: String {
        let file = record.originalURL.lastPathComponent
        return record.itemName ?? rule?.itemName?(file) ?? (rule?.choosesItems == true ? file : rule?.title ?? file)
    }
    var body: some View {
        let role: StatusRole = record.state == .succeeded ? .success : record.wasPreviewed ? .neutral : .caution
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.md) {
                Image(systemName: record.state == .succeeded ? "checkmark.circle" : record.wasPreviewed ? "eye" : "exclamationmark.circle").foregroundStyle(role.color)
                    .frame(width: StillDesign.Space.lg)
                (Text(name).font(StillDesign.TypeStyle.rowTitle)
                    + Text(" · " + PathDisplay.shortLocation(of: record.originalURL, home: CatalogCleanupModel.checkHome)).foregroundStyle(.secondary))
                    .lineLimit(1).help(record.originalURL.path)
                Spacer(minLength: StillDesign.Space.md)
                if record.state == .succeeded, let trashed = record.trashURL {
                    if TrashModel.shared.putBackOutcomes[record.id] == nil {
                        Button("Reveal in Trash") { Finder.reveal([trashed]) }.buttonStyle(.link)
                            .accessibilityLabel("Reveal \(record.originalURL.lastPathComponent) in Trash")
                    }
                    PutBackLink(record: record)
                }
                Text(record.outcomeTitle).font(StillDesign.TypeStyle.note)
                Text(catalogBytes(record.recordedBytes)).font(StillDesign.TypeStyle.note).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                if record.needsAttention { Text(record.message).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if showsDetails {
                    Text(record.originalURL.path).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if !record.needsAttention { Text(record.message).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                    if let output = record.toolOutput {
                        Text(output).font(StillDesign.TypeStyle.code).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("toolOutput-" + (record.ruleID ?? ""))
                    }
                }
            }.padding(.leading, StillDesign.Space.lg + StillDesign.Space.md)
        }.padding(.vertical, StillDesign.Space.md)
    }
}
