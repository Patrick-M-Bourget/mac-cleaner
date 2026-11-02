import Foundation

/// What a run changed on the Applications page, so the rescan after it reads again only that (Decision 134, #647): the Apps
/// and Plug-ins rows whose items it acted on, or that list something it acted on, and the files from deleted apps of their
/// makers and of the leftovers it acted on. Every other row keeps what the last full scan found.
public struct TouchedApplications: Sendable, Equatable {
    /// The rows read again, by id (`AppUninstall.Target.path`): an app's path, or a plug-in product's ID.
    public internal(set) var rows: Set<String> = []
    /// The makers (`com.maker`) whose files from deleted apps are read again: those of the touched rows, whose files may
    /// now be a deleted app's, and of the leftovers the run acted on.
    var leftoverMakers: Set<String> = []
    /// The installer receipts whose files from deleted apps are read again: those of the leftovers the run acted on.
    var leftoverReceipts: Set<String> = []

    /// Whether the rescan reads files from deleted apps again.
    public var readsLeftovers: Bool { !leftoverMakers.isEmpty || !leftoverReceipts.isEmpty }
    /// Whether the leftover `tie` is read again: its maker's, or its receipt's, or a receipt's that installed a touched app.
    func includes(_ tie: LeftoverTie, receipts: [InstallerReceipt]) -> Bool {
        if leftoverMakers.contains(tie.vendor) { return true }
        guard case .receipt(let id) = tie.evidence else { return false }
        return leftoverReceipts.contains(id) || receipts.contains { $0.id == id && !rows.isDisjoint(with: $0.apps) }
    }

    /// Whether `item` is uninstalled with a row read again: its own, or one it is shared with. Its row's rescan replaces it.
    public func touches(_ item: Candidate) -> Bool { rows.contains { item.isUninstalled(with: $0) } }
}

extension CatalogExecutionResult {
    /// The Applications rows the run touched, among those `shown` (every row the pages listed when it started). Nil when an
    /// item it acted on can't be tied to a row shown, or to a product of `plugIns` (the last full scan's inventory), so the
    /// rescan is a full scan, as when in doubt. A dry run touched nothing.
    public func touchedApplications(shown: [Candidate], plugIns: PlugInInventory?) -> TouchedApplications? {
        var touched = TouchedApplications()
        let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let acted = dryRun ? [] : records.filter { $0.state != .skipped && $0.state != .pending }
        func touch(_ item: Candidate) {
            touched.rows.insert(item.uninstall?.path ?? ""); touched.rows.formUnion(item.sharedBy.filter { !$0.hasPrefix("receipt:") })
            if let id = item.uninstall?.bundleID, !id.isEmpty { touched.leftoverMakers.insert(RemovedAppLeftovers.vendor(of: id)) }
        }
        func touchLeftover(_ item: Candidate) -> Bool {
            guard let tie = item.leftover else { return false }
            if case .receipt(let id) = tie.evidence { touched.leftoverReceipts.insert(id) } else { touched.leftoverMakers.insert(tie.vendor) }
            return true
        }
        for record in acted {
            switch record.ruleID.flatMap(AppRuleFamily.of(ruleID:)) {
            case .appUninstall?, .plugInUninstall?:
                guard let item = byID[record.candidateID], item.uninstall != nil else { return nil }
                touch(item)
            case .removedAppLeftovers?:
                guard let item = byID[record.candidateID], touchLeftover(item) else { return nil }
            case nil: break
            }
        }
        // Any other item at, inside or holding one a row lists (an app in Downloads, a container the plan offered too).
        let paths = acted.map { $0.originalURL.resolvingSymlinksInPath().standardizedFileURL.path }
        for item in shown where Self.overlaps(item.url.resolvingSymlinksInPath().standardizedFileURL.path, paths) {
            if item.uninstall != nil { touch(item) } else if AppRuleFamily.of(ruleID: item.ruleID) == .removedAppLeftovers, !touchLeftover(item) { return nil }
        }
        // A product is read again against the inventory it was found in.
        let products = Set(shown.compactMap { $0.uninstall?.plugIn == nil ? nil : $0.uninstall?.path } + shown.flatMap(\.sharedBy))
        guard touched.rows.intersection(products).isSubset(of: Set(plugIns?.products.map(\.id) ?? [])) else { return nil }
        return touched
    }
}

extension TouchedApplications {
    /// The Applications items after the rescan: the touched rows' items as a full scan finds them now, against the last full
    /// scan's plug-in inventory; every other row's as `shown`. An app read again comes from `apps`, as installed now, so an
    /// uninstalled app's row leaves even while Spotlight still lists it. `leftovers` and `offered` (the catalog's rows) stay
    /// theirs, as in a full scan.
    public func rescanning(_ shown: [Candidate], home: URL, systemRoot: URL, apps: any AppPresence, receipts: ReceiptListings, plugIns: PlugInInventory?,
                           excluding own: String?, leftovers: [Candidate], offered: [Candidate],
                           exclusions: ProtectedItemsPolicy = ProtectedItemsPolicy()) -> [Candidate] {
        let kept = shown.filter { !touches($0) }
        guard !rows.isEmpty else { return kept }
        let installed = apps.installedApps() ?? [], read = ReadReceipts(receipts, home: home)
        let products = Set(plugIns?.products.map(\.id) ?? []).intersection(rows)
        let appItems = ApplicationsInventory.withUninstallers(installed, excluding: own, home: home)
            .filter { rows.contains(URL(fileURLWithPath: $0.app.path).standardizedFileURL.path) }
            .flatMap { app, uninstaller in
                AppUninstall.scan(app, uninstaller: uninstaller, excluding: own, home: home, apps: apps, receipts: read, leftovers: leftovers, offered: offered,
                                  exclusions: exclusions)
            }
        let plugInItems = plugIns.map { inventory in
            products.isEmpty ? [] : PlugInUninstall.scan(inventory, home: home, systemRoot: systemRoot, installed: installed, receipts: receipts,
                                                         offered: offered + leftovers + kept.filter { $0.uninstall?.plugIn == nil } + appItems,
                                                         exclusions: exclusions, only: products)
        } ?? []
        return kept + appItems + plugInItems
    }
}

extension PlugInUninstall {
    /// Products' items with the vendor content tied to them (Decision 52), as the catalog scan offers them: never what `offered`
    /// holds. `only` reads just those products (Decision 134).
    public static func scan(_ inventory: PlugInInventory, home: URL, systemRoot: URL, installed: [InstalledApp], receipts: ReceiptListings, offered: [Candidate],
                            exclusions: ProtectedItemsPolicy, only: Set<String>? = nil) -> [Candidate] {
        let owners = ApplicationsInventory.plugIns(inventory).map { ContentOwner($0) } + installed.map { ContentOwner($0) }
        let content = MusicContent.scan(owners: owners, home: home, systemRoot: systemRoot).items
        return scan(inventory, apps: installed, receipts: receipts, content: content, systemRoot: systemRoot, offered: offered, exclusions: exclusions, only: only)
    }
}

extension TouchedApplications {
    /// The touched rows nothing is left of, which the page stops listing: an app whose bundle is gone, or a product of
    /// `plugIns` none of whose formats `exists`. One with anything left stays, read again.
    public func gone(in plugIns: PlugInInventory?, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Set<String> {
        rows.filter { row in
            if let product = plugIns?.products.first(where: { $0.id == row }) { return !product.files.contains { exists($0.url.path) } }
            return !exists(row)
        }
    }
}

extension TouchedApplications {
    /// Files from deleted apps after the rescan: those of the makers and receipts read again as a full scan finds them now,
    /// with `apps` as installed now, so a file an uninstalled app left appears; every other one as `shown`. The catalog's
    /// rows still take what they offer (`Catalog.merging`).
    public func rescanningLeftovers(_ shown: [Candidate], home: URL, apps: any AppPresence, receipts: any InstallerReceiptReading,
                                    exclusions: ProtectedItemsPolicy = ProtectedItemsPolicy()) -> [Candidate] {
        guard readsLeftovers else { return shown }
        let listed = receipts.receipts()
        let kept = shown.filter { item in item.leftover.map { !includes($0, receipts: listed) } ?? true }
        return kept + RemovedAppLeftovers.scan(home: home, apps: apps, receipts: receipts, exclusions: exclusions) { includes($0, receipts: listed) }
    }
}
