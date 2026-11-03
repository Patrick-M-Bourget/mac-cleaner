import Foundation

/// The names and sizes Overview and Smart clean show for the catalog, shared by the app and `cachedrop` (#626) so a
/// terminal says exactly what the window says.
extension CatalogCategory {
    /// Overview's row title for a category; the rows themselves come from what the catalog found.
    public var overviewTitle: String {
        switch self {
        case .developer: "Developer caches and build files"
        case .browser: "Browser caches"
        case .downloads: "Downloads"
        case .system: "App caches"
        case .audio: "Audio software"
        case .models: "Models and disk images"
        case .updaters: "App update downloads"
        case .logs: "Logs and crash reports"
        case .icloud: "Downloaded iCloud files"
        case .files: "Large and old files"
        case .managed: "App-managed storage"
        case .leftovers: "Files from deleted apps"
        case .apps: "Apps, plug-ins and their files"
        }
    }
    /// Smart clean's title: it takes only downloads untouched for 7 days (#342), so it says so.
    public var smartCleanTitle: String { self == .downloads ? "Old downloads" : overviewTitle }
}

extension CatalogOverview.Row {
    /// The row's size; "Up to" when part of it is copies that share disk blocks.
    public var valueText: String { estimate.text(upperBound: rules.contains(where: \.estimateIsUpperBound)) }
}

extension CatalogOverview {
    /// Overview's "Recommended for review" figure (SPEC section 6): an estimate, and an upper bound because clones share
    /// blocks; "Empty" when nothing is recommended, never "Up to Zero KB" (#568, Decision 131).
    public static func recommendedText(_ estimate: SizeEstimate) -> String {
        if estimate == .measured(0) { return "Empty" }
        let size = SizeFormatter.text(estimate, upperBound: true)
        if case .atLeast = estimate { return size + " · Some sizes unknown" }
        return size
    }
}
