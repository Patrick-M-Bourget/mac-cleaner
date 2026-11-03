import Foundation

/// Applications › Audio software (Decision 151): the audio apps that leave Apps, and the audio and MIDI drivers.
/// Plug-in products come from `ApplicationsInventory.plugIns`, and sounds and samples from `MusicContent`.
public enum AudioSoftware {
    /// The listed apps split into the ones Apps keeps and the audio apps: a plug-in host, a vendor's manager, or a plug-in
    /// product's own standalone app (#176: the app an AUv3 of it is in, or an app of the same bundle-ID vendor named like it).
    /// Hosts and managers match their exact bundle IDs (Decision 41); no app is recognised by its name alone. Order is kept.
    public static func split(_ apps: [InventoryEntry], plugIns: PlugInInventory) -> (apps: [InventoryEntry], audio: [InventoryEntry]) {
        let known = Set(PlugInUninstall.hosts.flatMap(\.bundleIDs).map { $0.lowercased() } + VendorTool.known.map(\.bundleID))
        let installed = apps.compactMap { entry in entry.bundleID.map { InstalledApp(name: entry.name, bundleID: $0, path: entry.id) } }
        let standalone = Set(plugIns.products.filter { !$0.isApple }.compactMap { PlugInUninstall.ownApp(of: $0, among: installed)?.path })
        let isAudio = { (entry: InventoryEntry) in known.contains(entry.bundleID?.lowercased() ?? "") || standalone.contains(entry.id) }
        return (apps.filter { !isAudio($0) }, apps.filter(isAudio))
    }

    /// Where macOS loads audio (Core Audio HAL) and MIDI drivers from, under both the system root and the home.
    static let driverPlaces = ["Library/Audio/Plug-Ins/HAL", "Library/Audio/MIDI Drivers"]

    /// Every audio and MIDI driver but Apple's, largest first, with its maker from its bundle and its size. One in a folder only
    /// an administrator can change can't go to the Trash (Decision 4: never prompt for admin), so it needs a password, like an app
    /// (Decision 50). Only Info.plists are read; no driver is loaded.
    public static func drivers(home: URL, systemRoot: URL = URL(fileURLWithPath: "/"), sizer: KnownLocationSizer = KnownLocationSizer()) -> [InventoryEntry] {
        let urls = driverPlaces.flatMap { [systemRoot.appendingPathComponent($0), home.appendingPathComponent($0)] }
            .flatMap { InstalledBundles.bundles(in: $0, depth: 1) }
        let entries = urls.compactMap { url -> InventoryEntry? in
            let info = PlugInInventory.info(url), bundleID = info?["CFBundleIdentifier"] as? String
            guard bundleID?.lowercased().hasPrefix("com.apple.") != true else { return nil }
            let part = InventoryEntry.Part(name: url.lastPathComponent, url: url, size: Catalog.estimate(sizer.size(url)), removable: Removability.canMoveToTrash(url))
            return InventoryEntry(id: url.path, name: url.deletingPathExtension().lastPathComponent, maker: info.flatMap(PlugInInventory.copyrightHolder),
                                  volume: nil, parts: [part], bundleID: bundleID)
        }
        return ApplicationsInventory.largestFirst(entries)
    }

    /// Plug-in products by maker (Decision 151): each maker once, ordered by `sort` (by size, the maker's products added up),
    /// products with no maker last as Other makers (nil). Products keep the order they came in.
    public static func byMaker(_ products: [InventoryEntry], sort: ListSort, bytes: (InventoryEntry) -> Int64)
        -> [(maker: String?, products: [InventoryEntry])] {
        var makers: [String] = [], groups: [String: [InventoryEntry]] = [:], others: [InventoryEntry] = []
        for product in products {
            guard let maker = product.maker else { others.append(product); continue }
            if groups[maker] == nil { makers.append(maker) }
            groups[maker, default: []].append(product)
        }
        let ordered = sort.ordered(makers, name: { $0 }, bytes: { groups[$0]!.reduce(0) { $0 + max(bytes($1), 0) } })
        return ordered.map { (maker: Optional($0), products: groups[$0]!) } + (others.isEmpty ? [] : [(maker: nil, products: others)])
    }
}
