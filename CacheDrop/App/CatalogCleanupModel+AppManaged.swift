import Foundation
import CacheDropCore

/// Guidance-only categories (SPEC section 3): sized and shown with where to manage them, never in a plan.
extension CatalogCleanupModel {
    func appManagedRule(_ finding: GuidanceFinding) -> CleanupRule? { catalog.rule(finding.ruleID) }
    /// Seconds each guidance location is sized for: short, so a large Photos library doesn't hold up the scan.
    nonisolated static let appManagedTimeBudget: TimeInterval = 10
    /// Sizes the guidance rules from metadata only. Read-only. A size cut short by `appManagedTimeBudget` reads "At least".
    /// `fullDiskAccess` is the catalog scan's own probe, so one scan never probes twice.
    func scanAppManaged(home: URL, fullDiskAccess: FullDiskAccessStatus, receipts: ReceiptListings) async {
        let catalog = catalog, system = Self.systemRoot, snapshots = Self.snapshots, apps = Self.appPresence
        appManaged = await Task.detached(priority: .utility) {
            catalog.guidance(home: home, systemRoot: system, sizer: KnownLocationSizer(timeBudget: Self.appManagedTimeBudget), snapshots: snapshots,
                             fullDiskAccess: fullDiskAccess, appPresence: apps, receipts: receipts)
        }.value
    }
    /// CacheDrop became active: if Full Disk Access was granted while it was away, rescan the catalog and guidance once,
    /// so "needs Full Disk Access" lines go away without Scan again (#124). Probing never asks for access.
    func rescanIfFullDiskAccessGranted() async {
        guard canEdit, !isScanning, let home = Self.home else { return }
        guard fullDiskAccessRescan.activated(probing: FullDiskAccessProbe(home: home)) else { return }
        await scan()
    }
    /// Opens where the finding is managed: its app, a System Settings pane, or the folder in Finder.
    func open(_ finding: GuidanceFinding) async {
        let name = appManagedRule(finding)?.guidance?.placeName ?? "it"
        appManagedStatus = await catalog.open(finding, using: Self.appManagedOpener) ? Self.openedStatus(name) : "Couldn’t open \(name)."
    }
    /// Shows a plug-in product's files selected in Finder. A debug test run reveals nothing.
    func reveal(_ product: PlugInProduct) { reveal(product.name, product.files.map(\.url)) }
    /// Shows a library package selected in Finder (#180, #178). Nothing inside it is opened.
    func reveal(_ library: FoundLibrary) { reveal(library.name, [library.url]) }
    private func reveal(_ name: String, _ urls: [URL]) {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { appManagedStatus = "Test run: would reveal \(name)."; return }
        #endif
        Finder.reveal(urls)
    }
    private static func openedStatus(_ name: String) -> String? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return "Test run: would open \(name)." }
        #endif
        return nil
    }
    /// What opens guidance places. A debug test run opens nothing.
    static var appManagedOpener: any GuidanceOpening {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return NothingOpens() }
        #endif
        return WorkspaceGuidanceOpener()
    }
    /// Time Machine local snapshots. A debug test home reads a count from `<home>/.cachedrop-test-snapshots`, never tmutil.
    static var snapshots: any LocalSnapshotListing {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureSnapshotCount(home: home) }
        #endif
        return TmutilSnapshots()
    }
}
