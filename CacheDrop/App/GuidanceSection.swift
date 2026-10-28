import CacheDropCore
import SwiftUI

/// App-managed storage (Decision 25): its own quiet page, reached from one Overview row. Each row opens the app or
/// place that manages it; CacheDrop shows the size and never changes these (SPEC section 3).
struct AppManagedStorageView: View {
    @Bindable var model: CatalogCleanupModel
    let back: () -> Void
    var body: some View {
        let protected = model.guidance.filter { $0.size == .notAccessible }
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "App-managed storage", subtitle: "Review protected data in the app that owns it.",
                       back: BackButton(destination: Destination.overview.rawValue, identifier: "appManagedBack", action: back))
            if !protected.isEmpty {
                FullDiskAccessNote(places: protected.compactMap { model.guidanceRule($0)?.title }).accessibilityIdentifier("guidanceAccess")
            }
            // Nothing known yet: skeleton rows; a rescan dims the rows already shown (#308).
            if !model.hasScanned { SkeletonRows(.review, identifier: "guidanceSkeleton") }
            RecommendationGroup {
                ForEach(Array(model.guidance.enumerated()), id: \.element.id) { index, finding in
                    if let rule = model.guidanceRule(finding), let guidance = rule.guidance {
                        if index > 0 { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }
                        let needsAccess = finding.size == .notAccessible
                        StorageReviewRow(category: rule.managedCategory, title: rule.title,
                                         detail: finding.libraries.map { FoundLibrary.summary($0, nouns: rule.libraryNouns, notSearched: finding.notSearched) } ?? finding.plugIns.map(\.summary) ?? finding.workspaces?.summary
                                             ?? rule.detail.firstSentence,
                                         value: needsAccess ? "Needs access" : finding.size.text,
                                         actionTitle: guidance.openTitle, action: { Task { await model.open(finding) } },
                                         identifier: "guidance-" + finding.id, mutedValue: needsAccess)
                            .help(rule.detail)
                        if let plugIns = finding.plugIns, !plugIns.products.isEmpty { PlugInProductRows(model: model, inventory: plugIns) }
                        if let libraries = finding.libraries { LibraryRows(model: model, rule: rule, guidance: guidance, libraries: libraries) }
                    }
                }
            }.waitingForScan(model.isScanning)
            if let status = model.guidanceStatus { StatusRow(text: status, symbol: "info.circle", identifier: "guidanceStatus") }
        }
    }
}

/// A guidance row's library packages (#180, #178, #179): each with its volume and size, revealed in Finder, never offered.
/// Below them, the app's own steps and the vendor's help page.
private struct LibraryRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    let guidance: Guidance
    let libraries: [FoundLibrary]
    var body: some View {
        ActionDisclosureGroup("Show \(rule.libraryNouns.many) · \(libraries.count)") {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(libraries) { library in
                        InspectableItemRow(name: library.name, detail: library.volume, size: library.size.text, symbol: rule.librarySymbol,
                                           inspected: false, inspect: { model.reveal(library) }, actionLabel: "Reveal \(library.name) in Finder") { EmptyView() }
                            .help(library.url.path)
                    }
                }
                Text(rule.detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let url = guidance.learnMore {
                    Link("Learn more", destination: url).font(CacheDropDesign.TypeStyle.caption).accessibilityIdentifier("guidanceLearnMore-" + rule.id)
                }
            }
        }.padding(.horizontal, CacheDropDesign.Space.lg).padding(.bottom, CacheDropDesign.Space.md)
    }
}

extension CleanupRule {
    /// The symbol beside each of a rule's libraries.
    var librarySymbol: String { id == "final-cut-libraries" ? "film" : "photo.on.rectangle" }
    /// What each listed package stands for: Lightroom's previews are counted by their catalogs (#179).
    var libraryNouns: (one: String, many: String) {
        if case .lightroomPreviews? = guidance?.sizing { return ("catalog", "catalogs") }
        return ("library", "libraries")
    }

    /// The badge for an app-managed row; a place without its own symbol keeps the shared app-managed one.
    var managedCategory: StorageCategory {
        switch id {
        case "device-backups": .deviceBackups
        case "mail-attachments": .mail
        case "messages-attachments": .messages
        case "photos-library": .photos
        case "time-machine-snapshots": .timeMachine
        case "xcode-archives": .xcodeArchives
        case "audio-plug-ins", "rack-extensions", "logic-sound-library", "ableton-packs", "splice-samples": .audioPlugIns
        default: .managed
        }
    }
}

extension GuidanceSize {
    /// Unknown is never 0 (SPEC section 1).
    var text: String {
        switch self {
        case .estimate(let estimate): estimate.text
        case .notAccessible: "Not accessible"
        case .unavailable: "Not available"
        case .snapshots(let count): (count == 1 ? "1 snapshot" : "\(count) snapshots") + " · Size unknown"
        }
    }
}

private extension String {
    /// A row's one short line: the detail's first sentence. The whole detail is the row's tooltip.
    var firstSentence: String {
        guard let end = range(of: ". ") else { return self }
        return String(self[..<end.lowerBound]) + "."
    }
}
