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
    /// The skipped rows as checked again since the review opened (#377, #560); the review's own, with no Quit, when nil.
    var held: ReviewHeldItems? = nil
    /// A skipped line's "Quit X" link, when a known app that is open holds its rows (#377, #560).
    var quit: ((ReviewHeldItems.Line) -> StatusAction?)? = nil
    var body: some View {
        let held = held ?? ReviewHeldItems(candidates: review.approval.candidates, refusals: review.refusals, catalog: catalog, isOpen: { _ in false })
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            if review.approval.dryRun {
                StatusRow(text: "Dry run is on. Nothing on disk changes.", symbol: "eye", role: .neutral, identifier: "reviewPreviewNotice")
            }
            ForEach(ReviewGroup.groups(catalog: catalog, candidates: review.approval.candidates, skipped: Set(held.refusals.keys))) { group in
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
                        // One line per holder, its skipped size once on it (#560, Decision 125).
                        ForEach(held.lines(in: group.candidates)) { line in
                            StatusRow(text: skippedText(line), symbol: "exclamationmark.circle", role: .caution,
                                      identifier: "reviewSkipped-" + line.items[0].ruleID, action: quit?(line))
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
            if !review.approval.dryRun, let note = catalog.dockerReviewNote(for: review.approval.candidates) {
                StatusRow(text: note, symbol: "clock", identifier: "reviewDockerSettles")
            }
            // What an uninstall leaves, why and what to do, with a link to where it can be cleaned (#177, #354).
            ForEach(review.staying) { line in
                StatusRow(text: line.text, symbol: "info.circle", identifier: "reviewStaying-" + line.id,
                          action: line.link.flatMap { link in follow.map { follow in StatusAction(title: link.title, identifier: "reviewStayingLink-" + line.id) { follow(link) } } })
            }
        }
    }
    /// "Google Chrome is open, so its caches will be skipped · 2.3 GB"; a row skipped for its own reason names itself and the reason.
    private func skippedText(_ line: ReviewHeldItems.Line) -> String {
        guard let text = line.text else { return line.items[0].displayName + " will be skipped: " + line.refusal.reason }
        return text + " · " + line.size.text(upperBound: line.isUpperBound)
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
