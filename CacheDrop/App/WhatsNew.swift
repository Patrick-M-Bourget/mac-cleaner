import SwiftUI
import CacheDropCore

/// Help → What’s New in CacheDrop (#553, Decision 161): the running version's release notes, drawn natively from the
/// content the build bundles (Decision 122), summary first, then the changes.
struct WhatsNewWindow: View {
    static let id = "whats-new"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    var body: some View {
        WhatsNewContent(notes: Result { try ReleaseNotes.bundled(version: version, resources: Bundle.main.resourceURL) }, version: version ?? "")
            .frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading)
    }
}

/// The notes, or why there are none: only a development build can lack its version's notes.
struct WhatsNewContent: View {
    let notes: Result<ReleaseNotes, any Error>
    let version: String
    var body: some View {
        switch notes {
        case .success(let notes): WhatsNewNotes(notes: notes)
        case .failure:
            EmptyState(title: "This build has no notes for CacheDrop \(version)", symbol: "doc.text", identifier: "whatsNewEmpty")
                .padding(.horizontal, CacheDropDesign.Space.xl)
        }
    }
}

/// The eyebrow, the summary as the heading, then each change on its own row under a hairline, as the update window
/// lists them (notes.css), drawn with the app's own type and separators.
private struct WhatsNewNotes: View {
    let notes: ReleaseNotes
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Text("What’s new in \(notes.version)").font(CacheDropDesign.TypeStyle.caption.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary).accessibilityIdentifier("whatsNewVersion")
            Text(notes.summary).font(CacheDropDesign.TypeStyle.sheet).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("whatsNewSummary")
                .padding(.bottom, CacheDropDesign.Space.sm)
            ForEach(Array(notes.changes.enumerated()), id: \.offset) { _, change in
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    Divider()
                    Text(change).font(CacheDropDesign.TypeStyle.note).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("whatsNewChange")
                }
            }
        }
        .padding(CacheDropDesign.Space.xl).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Help's menu item; a view so it can open the window.
struct WhatsNewMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("What’s New in CacheDrop") { openWindow(id: WhatsNewWindow.id) }.accessibilityIdentifier("whatsNewMenu")
    }
}
