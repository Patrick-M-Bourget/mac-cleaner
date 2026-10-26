import StillCore
import SwiftUI

/// Overview's guidance section: each category's size, or "Not accessible", with an "Open …" button.
struct GuidanceSection: View {
    @Bindable var model: CatalogCleanupModel
    @State private var expanded = true
    var body: some View {
        if !model.guidance.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    Text("Review these where they are managed. Still shows their size and never changes them.").font(StillDesign.TypeStyle.note).foregroundStyle(.secondary)
                    RecommendationGroup {
                        ForEach(model.guidance) { finding in
                            if let rule = model.guidanceRule(finding), let guidance = rule.guidance {
                                StorageReviewRow(category: .managed, title: rule.title, detail: rule.detail, value: finding.size.text,
                                                 meaning: "Guidance only · " + guidance.openTitle, actionTitle: guidance.openTitle,
                                                 action: { Task { await model.open(finding) } }, identifier: "guidance-" + finding.id)
                                // Each row Full Disk Access would open gets its own link, as `NotAccessibleRow` does.
                                if finding.size == .notAccessible {
                                    FullDiskAccessLink(title: "Review access options").padding(.horizontal, StillDesign.Space.lg)
                                        .accessibilityIdentifier("guidanceAccess-" + finding.id)
                                }
                                if finding.id != model.guidance.last?.id { Divider().padding(.horizontal, StillDesign.Space.lg) }
                            }
                        }
                    }
                    if let status = model.guidanceStatus { StatusRow(text: status, symbol: "info.circle", identifier: "guidanceStatus") }
                }.padding(.top, StillDesign.Space.sm)
            } label: {
                // On the title only: on the group it replaces every row's own identifier.
                Text("App-managed storage").font(StillDesign.TypeStyle.section).accessibilityIdentifier("guidanceSection")
            }
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
