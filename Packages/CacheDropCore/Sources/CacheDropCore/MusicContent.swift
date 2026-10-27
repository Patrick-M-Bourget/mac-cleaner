import Foundation

/// An installed app or plug-in product that content can belong to (Decision 51). Ownership comes from its bundle ID only,
/// never its name (Decision 41).
public struct ContentOwner: Sendable, Equatable {
    public let id: String
    public let name: String
    public let bundleID: String?
    public init(id: String, name: String, bundleID: String?) { self.id = id; self.name = name; self.bundleID = bundleID }
    /// An app or plug-in product on the Applications page.
    public init(_ entry: InventoryEntry) { self.init(id: entry.id, name: entry.name, bundleID: entry.bundleID) }
    /// An installed app, Apple's included (Logic Pro and MainStage own content but aren't listed on the Applications page).
    public init(_ app: InstalledApp) { self.init(id: app.path, name: app.name, bundleID: app.bundleID) }
}

/// A music vendor whose content CacheDrop knows where to find (#175). Every location is the vendor's documented one (see
/// `cachedrop-expansion-research.md` on `product-notes`), never guessed.
public struct MusicVendor: Sendable, Equatable {
    public struct Location: Sendable, Equatable {
        /// Under the system root when it starts with `/`, else under the home folder.
        public let path: String
        public let name: String
        public let kind: MusicContentItem.Kind
    }
    /// A location the vendor's own settings name, beyond its defaults: a library moved to another folder or drive.
    public struct Configured: Sendable, Equatable {
        public let url: URL
        public let kind: MusicContentItem.Kind
        public init(url: URL, kind: MusicContentItem.Kind) { self.url = url; self.kind = kind }
    }
    /// Who owns a vendor's content.
    public enum Owners: Sendable, Equatable {
        /// Every installed product of the vendor, by the bundle ID's vendor part (`com.arturia`), lowercased: content no
        /// receipt or bundle ID ties to one product belongs to the vendor (Decision 52). The one place a vendor match ties.
        case vendorProducts(String)
        /// The apps with exactly these bundle IDs, lowercased: a bundle-ID tie (Decision 41).
        case apps([String])
        var tie: MusicContentItem.Tie { if case .apps = self { .bundleID } else { .vendor } }
    }
    public let name: String
    public let locations: [Location]
    public let owners: Owners

    /// A vendor's manager (Native Access, Waves Central) installs content but never owns it.
    func owns(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased(), !VendorTool.known.contains(where: { $0.bundleID == id }) else { return false }
        switch owners {
        case .vendorProducts(let vendor): return RemovedAppLeftovers.vendor(of: id) == vendor
        case .apps(let ids): return ids.contains(id)
        }
    }

    public static let known: [MusicVendor] = [
        // The folder named in #175; its Soundbanks and SharedResources hold the content (6.3 GB on the Mac this was
        // written on). ReWire and REX in the same folder are shared code, not content.
        MusicVendor(name: "Reason Studios", locations: [
            .init(path: "/Library/Application Support/Propellerhead Software/Soundbanks", name: "Sound banks", kind: .installed),
            .init(path: "/Library/Application Support/Propellerhead Software/SharedResources", name: "Shared resources", kind: .installed),
        ], owners: .vendorProducts("se.propellerheads")),
        // Defaults from Ableton's Live Browser and User Library articles. The User Library holds the user's own presets
        // and samples. Live's settings can move both; reading them is open until Ableton documents where they live.
        MusicVendor(name: "Ableton", locations: [
            .init(path: "Music/Ableton/Factory Packs", name: "Packs", kind: .installed),
            .init(path: "Music/Ableton/User Library", name: "User Library", kind: .yours),
        ], owners: .vendorProducts("com.ableton")),
        // Apple's Logic Pro 12 / MainStage 4 library (relocatable) and the legacy layout, shared by both apps
        // (support.apple.com 111094 and Logic's legacy content guide). The bundle IDs are Logic's and MainStage's own.
        MusicVendor(name: "Apple", locations: [
            .init(path: "Music/Logic Pro Library.bundle", name: "Logic Pro Library", kind: .installed),
            .init(path: "/Library/Application Support/Logic", name: "Logic content", kind: .installed),
            .init(path: "/Library/Audio/Apple Loops/Apple", name: "Apple Loops", kind: .installed),
            .init(path: "/Library/Audio/Impulse Responses/Apple", name: "Impulse responses", kind: .installed),
        ], owners: .apps(["com.apple.logic10", "com.apple.mainstage3"])),
        // Waves' documented default for its instrument samples; Waves Central can relocate them. Shared by every Waves product.
        MusicVendor(name: "Waves", locations: [
            .init(path: "/Applications/Waves/Data/Instrument Data/Waves Sample Libraries", name: "Sample libraries", kind: .installed),
        ], owners: .vendorProducts("com.wavesaudio")),
        // Arturia's default resources folder (presets, samples and other files its products need; binaries live apart).
        // Arturia Software Center can move it; reading that setting is open until Arturia documents where it is kept.
        MusicVendor(name: "Arturia", locations: [
            .init(path: "/Library/Arturia", name: "Resources", kind: .installed),
        ], owners: .vendorProducts("com.arturia")),
    ]
}

/// One piece of a vendor's content: a sample library, sound pack or preset folder. Read-only: nothing is removed (#175).
public struct MusicContentItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Installed by the vendor or its manager, and reinstalled the same way.
        case installed
        /// Made by the user (Ableton's User Library, user presets): labelled as theirs, never grouped as installed content.
        case yours
    }
    /// What ties it to its owners.
    public enum Tie: Sendable, Equatable {
        /// The vendor (Decision 52): shared by every installed product of the vendor, "Shared by <Vendor> products",
        /// ticked one by one only and counted once.
        case vendor
        /// The owners' bundle IDs (Decision 41).
        case bundleID
    }
    public enum State: Sendable, Equatable {
        case present(SizeEstimate)
        /// On a drive that isn't connected: reported, never treated as removed. Content missing from a connected drive or
        /// the startup disk is gone and isn't listed.
        case offline(volume: String)
    }
    public let name: String
    /// The vendors whose locations reach it: one, unless two vendors' locations lead to the same folder.
    public internal(set) var vendors: [String]
    public let url: URL
    public let kind: Kind
    public let state: State
    /// The IDs of every confirmed owner. More than one means it is shared ("Shared with <N> products").
    public internal(set) var owners: [String]
    public internal(set) var tie: Tie
    public var id: String { url.path }
    public var isShared: Bool { owners.count > 1 }
}

/// Every music vendor's content found on this Mac, each item once with all its confirmed owners (#175).
public struct MusicContent: Sendable, Equatable {
    public let items: [MusicContentItem]

    /// Every item found counted once; offline items aren't on this Mac and count nothing.
    public var size: SizeEstimate {
        SizeEstimate(sum: items.compactMap { if case .present(let size) = $0.state { size } else { nil } })
    }
    /// Content the vendors installed.
    public var installed: [MusicContentItem] { items.filter { $0.kind == .installed } }
    /// Content the user made, kept apart from installed content.
    public var yours: [MusicContentItem] { items.filter { $0.kind == .yours } }

    /// The content a product owns, shared content included.
    public func items(for ownerID: String) -> [MusicContentItem] { items.filter { $0.owners.contains(ownerID) } }

    /// Looks in each vendor's documented locations, plus the locations `configured` reads from the vendor's own settings,
    /// and attaches what it finds to `owners`. Reads metadata and sizes only; follows a link or alias at a location only to
    /// measure its target. Content whose drive isn't connected is offline; missing anywhere else, it isn't listed.
    /// `volumes` is where drives are mounted, `/Volumes` outside tests.
    public static func scan(owners: [ContentOwner], home: URL, systemRoot: URL = URL(fileURLWithPath: "/"),
                            volumes: URL = URL(fileURLWithPath: "/Volumes"),
                            configured: (MusicVendor) -> [MusicVendor.Configured] = { _ in [] },
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> MusicContent {
        var items: [MusicContentItem] = [], index: [String: Int] = [:]
        for vendor in MusicVendor.known {
            let ownerIDs = owners.filter { vendor.owns($0.bundleID) }.map(\.id)
            let defaults = vendor.locations.map { location in
                (url: location.path.hasPrefix("/") ? systemRoot.appendingPathComponent(String(location.path.dropFirst()))
                                                   : home.appendingPathComponent(location.path), name: location.name, kind: location.kind)
            }
            let found = defaults.map { ($0, false) } + configured(vendor).map { ((url: $0.url, name: $0.url.lastPathComponent, kind: $0.kind), true) }
            for (location, isConfigured) in found {
                let resolved = resolve(location.url), state: MusicContentItem.State, key: String
                if case .at(let real) = resolved {
                    (state, key) = (.present(Catalog.estimate(sizer.size(URL(fileURLWithPath: real)))), real)
                } else {
                    if resolved == .missing, !isConfigured { continue }
                    let target: URL? = if case .leadsNowhere(let destination) = resolved { destination } else { location.url }
                    // Only a drive that isn't connected makes it offline; missing anywhere else, it is gone.
                    guard let target, let drive = volume(of: target, under: volumes),
                          !FileManager.default.fileExists(atPath: volumes.appendingPathComponent(drive).path) else { continue }
                    (state, key) = (.offline(volume: drive), target.standardizedFileURL.path)
                }
                if let seen = index[key] {
                    // Reached again, through another vendor's location: one item, with every vendor's owners.
                    if !items[seen].vendors.contains(vendor.name) { items[seen].vendors.append(vendor.name) }
                    items[seen].owners += ownerIDs.filter { !items[seen].owners.contains($0) }
                    if vendor.owners.tie == .vendor { items[seen].tie = .vendor }
                    continue
                }
                index[key] = items.count
                items.append(MusicContentItem(name: location.name, vendors: [vendor.name], url: location.url, kind: location.kind, state: state, owners: ownerIDs,
                                              tie: vendor.owners.tie))
            }
        }
        return MusicContent(items: items)
    }

    /// The drive a path is on, when it is under `volumes`: "<volumes>/Studio/…" reads "Studio".
    static func volume(of url: URL, under volumes: URL) -> String? {
        // An alias records the real path ("/private/var/…" for "/var/…"), so the volumes folder is matched both ways.
        let path = url.standardizedFileURL.path
        for root in [volumes.standardizedFileURL.path, realPath(volumes.path)].compactMap({ $0 }) where path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1).prefix { $0 != "/" })
        }
        return nil
    }

    /// Nothing at the location; the real path it leads to; or a link or alias whose target isn't there (when known).
    enum Resolved: Equatable { case missing, at(String), leadsNowhere(URL?) }

    /// Where a location really is: through a symbolic link or a Finder alias left where a library was moved from, without
    /// mounting a volume or asking the user.
    static func resolve(_ url: URL) -> Resolved {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .missing }
        if info.st_mode & S_IFMT == S_IFLNK {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return .leadsNowhere(nil) }
            let target = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            return realPath(url.path).map(Resolved.at) ?? .leadsNowhere(target)
        }
        if info.st_mode & S_IFMT == S_IFREG, (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true {
            guard let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
                  let real = realPath(resolved.path) else {
                let bookmark = try? URL.bookmarkData(withContentsOf: url)
                let path = bookmark.flatMap { URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: $0)?.path }
                return .leadsNowhere(path.map { URL(fileURLWithPath: $0) })
            }
            return .at(real)
        }
        return realPath(url.path).map(Resolved.at) ?? .missing
    }
}
