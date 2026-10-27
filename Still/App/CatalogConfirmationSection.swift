import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

extension ConsequenceGroup {
    var badge: CategoryBadge {
        switch self {
        case .permanentlyRemoved: CategoryBadge(symbol: "xmark.bin", color: StillDesign.purple)
        case .movedToTrash: CategoryBadge(symbol: "trash", color: StillDesign.orange)
        case .localCopiesRemoved: CategoryBadge(symbol: "icloud", color: StillDesign.blue)
        case .commandsRun: CategoryBadge(symbol: "terminal", color: StillDesign.teal)
        }
    }
}

/// The review sheet, grouped by consequence: each group's consequence once, one line per category, the files behind one disclosure.
struct CatalogConfirmationSection: View {
    let review: CatalogReview
    let catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if review.approval.previewOnly {
                StatusRow(text: "Dry run is on. Nothing on disk changes.", symbol: "eye", role: .neutral, identifier: "reviewPreviewNotice")
            }
            ForEach(ReviewGroup.groups(catalog: catalog, candidates: review.approval.candidates)) { group in
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    HStack(spacing: StillDesign.Space.md) {
                        group.consequence.badge
                        Text(group.consequence.title).font(StillDesign.TypeStyle.section)
                        Spacer()
                        Text(SizeEstimate(sum: group.lines.map(\.estimate)).text(upperBound: group.lines.contains(where: \.isUpperBound)))
                            .font(StillDesign.TypeStyle.section).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                        Text(group.consequence.consequence).font(StillDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(group.lines) { line in
                            HStack {
                                Text(line.category.overviewTitle)
                                Spacer()
                                Text(line.estimate.text(upperBound: line.isUpperBound)).monospacedDigit()
                            }.font(StillDesign.TypeStyle.note).accessibilityElement(children: .combine).accessibilityIdentifier("reviewLine-\(group.consequence)-\(line.id)")
                        }
                        ForEach(group.candidates.filter { review.refusals[$0.id] != nil }) { item in
                            StatusRow(text: item.displayName + " will be skipped: " + (review.refusals[item.id]?.reason ?? ""), symbol: "exclamationmark.circle", role: .caution)
                        }
                        ActionDisclosureGroup(StillDesign.items(group.candidates.count) + " · Show files") {
                            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                                ForEach(group.lines) { line in ForEach(line.rules) { rule in files(rule, line.candidates(for: rule)) } }
                            }.padding(.top, StillDesign.Space.sm)
                        }
                    }.padding(.leading, StillDesign.Size.badgeIndent)
                }
                Divider()
            }
        }
    }
    private func files(_ rule: CleanupRule, _ items: [Candidate]) -> some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Text(rule.title).font(StillDesign.TypeStyle.caption.weight(.medium))
            Text(rule.consequence).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in
                // A tool shows the exact command, e.g. `ollama rm llama3:latest` or `docker builder prune -a -f`.
                if let tool = rule.tool { Text(tool.commandLine(for: item.toolArgument)).font(StillDesign.TypeStyle.code).textSelection(.enabled) }
                // A command that takes an identifier (a simulator's UDID) also names the item.
                if rule.tool?.deletesLocationAfter ?? true || item.toolItem != nil {
                    Text(item.displayName + " · " + PathDisplay.shortLocation(of: item.url, home: CatalogCleanupModel.checkHome))
                        .font(StillDesign.TypeStyle.caption).help(item.url.path)
                }
            }
        }
    }
}
