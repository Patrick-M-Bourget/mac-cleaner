import StillCore
import SwiftUI

/// App-managed storage (Decision 25): its own quiet page, reached from one Overview row. Each row opens the app or
/// place that manages it; Still shows the size and never changes these (SPEC section 3).
struct AppManagedStorageView: View {
    @Bindable var model: CatalogCleanupModel
    let back: () -> Void
    var body: some View {
        let protected = model.guidance.filter { $0.size == .notAccessible }
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            HStack(alignment: .top) {
                PageHeader(title: "App-managed storage", subtitle: "Review protected data in the app that owns it.")
                Spacer(minLength: StillDesign.Space.md)
                Button("Back to overview", action: back).accessibilityIdentifier("appManagedBack")
            }
            if !protected.isEmpty {
                FullDiskAccessNote(places: protected.compactMap { model.guidanceRule($0)?.title }).accessibilityIdentifier("guidanceAccess")
            }
            RecommendationGroup {
                ForEach(Array(model.guidance.enumerated()), id: \.element.id) { index, finding in
                    if let rule = model.guidanceRule(finding), let guidance = rule.guidance {
                        if index > 0 { Divider().padding(.horizontal, StillDesign.Space.lg) }
                        let needsAccess = finding.size == .notAccessible
                        StorageReviewRow(category: rule.managedCategory, title: rule.title, detail: rule.detail.firstSentence,
                                         value: needsAccess ? "Needs access" : finding.size.text,
                                         actionTitle: guidance.openTitle, action: { Task { await model.open(finding) } },
                                         identifier: "guidance-" + finding.id, mutedValue: needsAccess)
                            .help(rule.detail)
                    }
                }
            }
            if let status = model.guidanceStatus { StatusRow(text: status, symbol: "info.circle", identifier: "guidanceStatus") }
        }
    }
}

extension CleanupRule {
    /// The badge for an app-managed row; a place without its own symbol keeps the shared app-managed one.
    var managedCategory: StorageCategory {
        switch id {
        case "device-backups": .deviceBackups
        case "mail-attachments": .mail
        case "messages-attachments": .messages
        case "photos-library": .photos
        case "time-machine-snapshots": .timeMachine
        case "xcode-archives": .xcodeArchives
        case "audio-plug-ins", "rack-extensions": .audioPlugIns
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
