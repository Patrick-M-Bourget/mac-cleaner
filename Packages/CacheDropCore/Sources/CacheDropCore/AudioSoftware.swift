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

    /// The guidance rules Applications › Audio software lists instead of App-managed storage (Decision 151): plug-ins, Rack
    /// Extensions and the sound libraries.
    public static let guidanceRuleIDs: Set<String> = ["audio-plug-ins", "rack-extensions", "logic-sound-library", "ableton-packs", "splice-samples"]

    /// Where macOS loads audio (Core Audio HAL) and MIDI drivers from, under both the system root and the home.
    static let driverPlaces = ["Library/Audio/Plug-Ins/HAL", "Library/Audio/MIDI Drivers"]

    /// Every audio and MIDI driver but Apple's, largest first, with its maker from its bundle and its size. One in a folder only
    /// an administrator can change can't go to the Trash (Decision 4: never prompt for admin), so it needs a password, like an app
    /// (Decision 50). Only Info.plists are read; no driver is loaded. `only` reads just those rows (#716).
    public static func drivers(home: URL, systemRoot: URL = URL(fileURLWithPath: "/"), only: Set<String>? = nil,
                               sizer: KnownLocationSizer = KnownLocationSizer()) -> [InventoryEntry] {
        // Each folder once: the system's and the home's are the same folder when a test home stands in for both.
        var seen = Set<String>()
        let urls = driverPlaces.flatMap { [systemRoot.appendingPathComponent($0), home.appendingPathComponent($0)] }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .flatMap { InstalledBundles.bundles(in: $0, depth: 1) }.filter { only?.contains($0.path) ?? true }
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

    /// Reason 13's additional devices (Humana, Pangea, Klang, Radical Piano), one folder each, per user (Reason Studios Help,
    /// "Installing Additional Content in Reason 13", help.reasonstudios.com/hc/en-us/articles/19526087405074). Reason Companion
    /// installs them again at any time; Reason Studios' own Reason 12 article has users delete these folders by hand
    /// (help.reasonstudios.com/hc/en-us/articles/4403131409170).
    public static let optionalDevices = "Library/Application Support/Propellerhead Software/Optional REs"
    /// Shop Rack Extensions: read-only, managed in Reason Companion. Where Reason keeps their licenses isn't documented, so
    /// CacheDrop never offers them (#701).
    public static let rackExtensions = "Library/Application Support/Propellerhead Software/RackExtensions"
    /// What must be closed before a Reason device goes: Reason, and Reason Companion, which installs them. Companion's bundle
    /// ID has no primary source yet (#704), so it is matched by its executable's name, as Cubase is.
    public static let reasonHosts: [RuleOwner] = PlugInUninstall.hosts.filter { $0.name == "Reason" }
        + [RuleOwner(name: "Reason Companion", executables: ["Reason Companion"])]

    /// Reason's additional devices, largest first, each a row of its own. `only` reads just those rows (#716).
    public static func optionalDevices(home: URL, only: Set<String>? = nil, sizer: KnownLocationSizer = KnownLocationSizer()) -> [InventoryEntry] {
        let folder = home.appendingPathComponent(optionalDevices)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
        let entries = names.compactMap { name -> InventoryEntry? in
            let url = folder.appendingPathComponent(name).standardizedFileURL
            guard only?.contains(url.path) ?? true else { return nil }
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
            let part = InventoryEntry.Part(name: name, url: url, size: Catalog.estimate(sizer.size(url)), removable: Removability.canMoveToTrash(url))
            return InventoryEntry(id: url.path, name: name, maker: "Reason Studios", volume: nil, parts: [part])
        }
        return ApplicationsInventory.largestFirst(entries)
    }

    /// The items of the drivers and Reason devices the user can move, as the catalog scan offers them; `only` reads just those
    /// rows again, for the rescan after a run that uninstalled one (#716, Decision 159).
    public static func uninstallItems(home: URL, systemRoot: URL, exclusions: ProtectedItemsPolicy, only: Set<String>? = nil) -> [Candidate] {
        uninstallItems(drivers(home: home, systemRoot: systemRoot, only: only), hosts: [], exclusions: exclusions)
            + uninstallItems(optionalDevices(home: home, only: only), hosts: reasonHosts, exclusions: exclusions)
    }
    /// Whether the row `id` is one of Reason's additional devices: read again here, never against the plug-in inventory (#716).
    static func isDevice(_ id: String) -> Bool { URL(fileURLWithPath: id).deletingLastPathComponent().path.hasSuffix("/" + optionalDevices) }

    /// The items that uninstall `entries` (drivers, Reason devices): each one the user can move to the Trash, as an app is
    /// (Decision 50), its own row's item; `hosts` must be closed first. Nothing for one that needs a password.
    public static func uninstallItems(_ entries: [InventoryEntry], hosts: [RuleOwner], exclusions: ProtectedItemsPolicy = ProtectedItemsPolicy(),
                                      sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let catalog = Catalog(rules: AppUninstall.rules)
        return entries.compactMap { entry -> Candidate? in
            // Never license files or macOS's own (Decision 41), checked at the scan as at the click.
            guard entry.parts.count == 1, let url = entry.parts.first?.url, Removability.canMoveToTrash(url),
                  RemovedAppLeftovers.neverOfferedPart(of: url, below: url.deletingLastPathComponent()) == nil else { return nil }
            var info = stat()
            // A protected item is never offered (SPEC section 2).
            guard lstat(url.path, &info) == 0, let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
                  !exclusions.covers(url, volumeID: volume) else { return nil }
            let size = sizer.size(url)
            var item = catalog.candidate(AppUninstall.appRule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
                .found(under: url.deletingLastPathComponent())
            var target = AppUninstall.Target(name: entry.name, bundleID: entry.bundleID ?? "", path: entry.id)
            if !hosts.isEmpty { target.plugIn = AppUninstall.Target.PlugIn(hosts: hosts) }
            item.uninstall = target
            return item
        }
    }

    /// Splice's default sounds folder (Splice Support, "Where is my Splice folder?"), as the Splice guidance reads it.
    static let spliceSounds = "Splice"

    /// Sounds and samples (Decision 151): the vendor libraries `MusicContent` knows, Splice's sounds and the shop Rack Extensions,
    /// largest first, each with who it is from; read-only (#705 decides removing them). One on a drive that isn't connected
    /// names that drive and has no size.
    public static func sounds(home: URL, systemRoot: URL = URL(fileURLWithPath: "/"), sizer: KnownLocationSizer = KnownLocationSizer()) -> [InventoryEntry] {
        let content = MusicContent.scan(owners: [], home: home, systemRoot: systemRoot, sizer: sizer).items.map(sound)
        let others = [("Splice sounds", "Splice", spliceSounds), ("Rack Extensions", "Reason Studios", rackExtensions)].compactMap { name, maker, path -> InventoryEntry? in
            let url = home.appendingPathComponent(path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return InventoryEntry(id: url.path, name: name, maker: maker, volume: nil,
                                  parts: [.init(name: name, url: url, size: Catalog.estimate(sizer.size(url)), removable: false)])
        }
        return ApplicationsInventory.largestFirst(content + others)
    }

    /// One vendor library's row: who it is from, the user's own marked "Yours" (Decision 151), and the managers that installed it.
    static func sound(_ item: MusicContentItem) -> InventoryEntry {
        let (size, volume): (SizeEstimate, String?) = switch item.state {
        case .present(let size): (size, nil)
        case .offline(let drive): (.unknown, drive)
        }
        let from = item.vendors.joined(separator: ", ") + (item.kind == .yours ? " · Yours" : "")
        var entry = InventoryEntry(id: item.url.path, name: item.name, maker: from, volume: volume,
                                   parts: [.init(name: item.name, url: item.url, size: size, removable: false)])
        // The user's own content isn't the manager's to remove or move (#714).
        if item.kind == .installed { entry.managers = item.vendors.compactMap { name in MusicVendor.known.first { $0.name == name }?.tool } }
        return entry
    }

    /// The installed app that manages a sound library (#714): its vendor's manager, when it is among `apps`, by bundle ID only (41).
    public static func manager(of sound: InventoryEntry, among apps: [InventoryEntry]) -> InventoryEntry? {
        sound.managers.lazy.compactMap { tool in apps.first { $0.bundleID?.lowercased() == tool.bundleID } }.first
    }
}
