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
    /// Follows a staying line's link (#354); without it the lines show no link.
    var follow: ((AppUninstall.Staying.Link) -> Void)? = nil
    /// The rows' reasons as checked again since the review opened (#377); the review's own when nil.
    var refusals: [String: CheckRefusal]? = nil
    /// A row's "Quit X" link, when a known app that is open holds it (#377).
    var quit: ((Candidate) -> StatusAction?)? = nil
    var body: some View {
        let refusals = refusals ?? review.refusals
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
                        ForEach(group.candidates.filter { refusals[$0.id] != nil }) { item in
                            StatusRow(text: item.displayName + " will be skipped: " + (refusals[item.id]?.reason ?? ""), symbol: "exclamationmark.circle", role: .caution,
                                      identifier: "reviewSkipped-" + item.ruleID, action: quit?(item))
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
            // Docker's space arrives after its prune (#411); Results check again a minute later.
            if !review.approval.previewOnly, let note = catalog.dockerReviewNote(for: review.approval.candidates) {
                StatusRow(text: note, symbol: "clock", identifier: "reviewDockerSettles")
            }
            // What an uninstall leaves, why and what to do, with a link to where it can be cleaned (#177, #354).
            ForEach(review.staying) { line in
                StatusRow(text: line.text, symbol: "info.circle", identifier: "reviewStaying-" + line.id,
                          action: line.link.flatMap { link in follow.map { follow in StatusAction(title: link.title, identifier: "reviewStayingLink-" + line.id) { follow(link) } } })
            }
        }
    }
    private func files(_ rule: CleanupRule, _ items: [Candidate]) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            Text(rule.title).font(CacheDropDesign.TypeStyle.caption.weight(.medium))
            // Only what this rule adds to its group's line (Decision 92 rules 2 and 7); most Trash rules add nothing.
            if !rule.consequence.isEmpty {
                Text(rule.consequence).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
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
