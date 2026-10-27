import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

extension ConsequenceGroup {
    var badge: CategoryBadge {
        switch self {
        case .permanentlyRemoved: CategoryBadge(symbol: "xmark.bin", color: CacheDropDesign.purple)
        case .movedToTrash: CategoryBadge(symbol: "trash", color: CacheDropDesign.orange)
        case .localCopiesRemoved: CategoryBadge(symbol: "icloud", color: CacheDropDesign.blue)
        case .commandsRun: CategoryBadge(symbol: "terminal", color: CacheDropDesign.teal)
        }
    }
}

/// The review sheet, grouped by consequence: each group's consequence once, one line per category, the files behind one disclosure.
struct CatalogConfirmationSection: View {
    let review: CatalogReview
    let catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            if review.approval.previewOnly {
                StatusRow(text: "Dry run is on. Nothing on disk changes.", symbol: "eye", role: .neutral, identifier: "reviewPreviewNotice")
            }
            ForEach(ReviewGroup.groups(catalog: catalog, candidates: review.approval.candidates)) { group in
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    HStack(spacing: CacheDropDesign.Space.md) {
                        group.consequence.badge
                        Text(group.consequence.title).font(CacheDropDesign.TypeStyle.section)
                        Spacer()
                        Text(SizeEstimate(sum: group.lines.map(\.estimate)).text(upperBound: group.lines.contains(where: \.isUpperBound)))
                            .font(CacheDropDesign.TypeStyle.section).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                        Text(group.consequence.consequence).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(group.lines) { line in
                            HStack {
                                Text(line.category.overviewTitle)
                                Spacer()
                                Text(line.estimate.text(upperBound: line.isUpperBound)).monospacedDigit()
                            }.font(CacheDropDesign.TypeStyle.note).accessibilityElement(children: .combine).accessibilityIdentifier("reviewLine-\(group.consequence)-\(line.id)")
                        }
                        ForEach(group.candidates.filter { review.refusals[$0.id] != nil }) { item in
                            StatusRow(text: item.displayName + " will be skipped: " + (review.refusals[item.id]?.reason ?? ""), symbol: "exclamationmark.circle", role: .caution)
                        }
                        ActionDisclosureGroup(CacheDropDesign.items(group.candidates.count) + " · Show files") {
                            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                                ForEach(group.lines) { line in ForEach(line.rules) { rule in files(rule, line.candidates(for: rule)) } }
                            }.padding(.top, CacheDropDesign.Space.sm)
                        }
                    }.padding(.leading, CacheDropDesign.Size.badgeIndent)
                }
                Divider()
            }
            // What an uninstall leaves, and why (#177).
            ForEach(review.staying) { line in StatusRow(text: line.text, symbol: "info.circle", identifier: "reviewStaying-" + line.id) }
        }
    }
    private func files(_ rule: CleanupRule, _ items: [Candidate]) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            Text(rule.title).font(CacheDropDesign.TypeStyle.caption.weight(.medium))
            Text(rule.consequence).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // An app's files are grouped by the folder they are in (#177).
            if rule.category == .apps {
                ForEach(AppUninstall.byPlace(items), id: \.place) { place in
                    Text(PathDisplay.shortLocation(of: place.items[0].url, home: CatalogCleanupModel.checkHome)).font(CacheDropDesign.TypeStyle.caption.weight(.medium))
                    ForEach(place.items) { item in Text(item.displayName).font(CacheDropDesign.TypeStyle.caption).help(item.url.path) }
                }
            } else {
            ForEach(items) { item in
                // A tool shows the exact command, e.g. `ollama rm llama3:latest` or `docker builder prune -a -f`.
                if let tool = rule.tool { Text(tool.commandLine(for: item.toolArgument)).font(CacheDropDesign.TypeStyle.code).textSelection(.enabled) }
                // A command that takes an identifier (a simulator's UDID) also names the item.
                if rule.tool?.deletesLocationAfter ?? true || item.toolItem != nil {
                    Text(item.displayName + " · " + PathDisplay.shortLocation(of: item.url, home: CatalogCleanupModel.checkHome))
                        .font(CacheDropDesign.TypeStyle.caption).help(item.url.path)
                }
            }
            }
        }
    }
}
