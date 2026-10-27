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
    public let name: String
    public let locations: [Location]
    /// The owners' bundle IDs, lowercased: a vendor prefix (`com.ableton`) or a whole ID. A vendor's manager (Native
    /// Access, Waves Central) installs content but never owns it.
    let ownerIDs: [String]

    func owns(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased(), !VendorTool.known.contains(where: { $0.bundleID == id }) else { return false }
        return ownerIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    public static let known: [MusicVendor] = [
        // The folder named in #175; its Soundbanks and SharedResources hold the content (6.3 GB on the Mac this was
        // written on). ReWire and REX in the same folder are shared code, not content.
        MusicVendor(name: "Reason Studios", locations: [
            .init(path: "/Library/Application Support/Propellerhead Software/Soundbanks", name: "Sound banks", kind: .installed),
            .init(path: "/Library/Application Support/Propellerhead Software/SharedResources", name: "Shared resources", kind: .installed),
        ], ownerIDs: ["se.propellerheads"]),
        // Defaults from Ableton's Live Browser and User Library articles. The User Library holds the user's own presets
        // and samples. Live's settings can move both; reading them is open until Ableton documents where they live.
        MusicVendor(name: "Ableton", locations: [
            .init(path: "Music/Ableton/Factory Packs", name: "Packs", kind: .installed),
            .init(path: "Music/Ableton/User Library", name: "User Library", kind: .yours),
        ], ownerIDs: ["com.ableton"]),
        // Apple's Logic Pro 12 / MainStage 4 library (relocatable) and the legacy layout, shared by both apps
        // (support.apple.com 111094 and Logic's legacy content guide). The bundle IDs are Logic's and MainStage's own.
        MusicVendor(name: "Apple", locations: [
            .init(path: "Music/Logic Pro Library.bundle", name: "Logic Pro Library", kind: .installed),
            .init(path: "/Library/Application Support/Logic", name: "Logic content", kind: .installed),
            .init(path: "/Library/Audio/Apple Loops/Apple", name: "Apple Loops", kind: .installed),
            .init(path: "/Library/Audio/Impulse Responses/Apple", name: "Impulse responses", kind: .installed),
        ], ownerIDs: ["com.apple.logic10", "com.apple.mainstage3"]),
        // Waves' documented default for its instrument samples; Waves Central can relocate them. Shared by every Waves product.
        MusicVendor(name: "Waves", locations: [
            .init(path: "/Applications/Waves/Data/Instrument Data/Waves Sample Libraries", name: "Sample libraries", kind: .installed),
        ], ownerIDs: ["com.wavesaudio"]),
        // Arturia's default resources folder (presets, samples and other files its products need; binaries live apart).
        // Arturia Software Center can move it; reading that setting is open until Arturia documents where it is kept.
        MusicVendor(name: "Arturia", locations: [
            .init(path: "/Library/Arturia", name: "Resources", kind: .installed),
        ], ownerIDs: ["com.arturia"]),
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
    public enum State: Sendable, Equatable {
        case present(SizeEstimate)
        /// Its volume isn't connected or its target is gone: it is reported, never treated as removed. `volume` is the
        /// volume's name when known.
        case offline(volume: String?)
    }
    public let name: String
    public let vendor: String
    public let url: URL
    public let kind: Kind
    public let state: State
    /// The IDs of every confirmed owner. More than one means it is shared ("Shared with <N> products").
    public let owners: [String]
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
    /// measure its target. A default location with nothing there isn't listed; a configured one is offline.
    public static func scan(owners: [ContentOwner], home: URL, systemRoot: URL = URL(fileURLWithPath: "/"),
                            configured: (MusicVendor) -> [MusicVendor.Configured] = { _ in [] },
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> MusicContent {
        var items: [MusicContentItem] = [], seen = Set<String>()
        for vendor in MusicVendor.known {
            let ownerIDs = owners.filter { vendor.owns($0.bundleID) }.map(\.id)
            let defaults = vendor.locations.map { location in
                (url: location.path.hasPrefix("/") ? systemRoot.appendingPathComponent(String(location.path.dropFirst()))
                                                   : home.appendingPathComponent(location.path), name: location.name, kind: location.kind)
            }
            let found = defaults.map { ($0, false) } + configured(vendor).map { ((url: $0.url, name: $0.url.lastPathComponent, kind: $0.kind), true) }
            for (location, isConfigured) in found {
                let state: MusicContentItem.State, key: String
                switch resolve(location.url) {
                case .missing where isConfigured: (state, key) = (.offline(volume: ApplicationsInventory.volume(of: location.url)), location.url.path)
                case .missing: continue
                case .offline(let target): (state, key) = (.offline(volume: target.flatMap(ApplicationsInventory.volume)), target?.path ?? location.url.path)
                case .at(let real): (state, key) = (.present(Catalog.estimate(sizer.size(URL(fileURLWithPath: real)))), real)
                }
                guard seen.insert(key).inserted else { continue }
                items.append(MusicContentItem(name: location.name, vendor: vendor.name, url: location.url, kind: location.kind, state: state, owners: ownerIDs))
            }
        }
        return MusicContent(items: items)
    }

    enum Resolved: Equatable { case missing, at(String), offline(URL?) }

    /// Where a location really is: through a symbolic link or a Finder alias left where a library was moved from, without
    /// mounting a volume or asking the user. A link or alias whose target is gone is offline, with the target when known.
    static func resolve(_ url: URL) -> Resolved {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .missing }
        if info.st_mode & S_IFMT == S_IFLNK {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return .offline(nil) }
            let target = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            return realPath(url.path).map(Resolved.at) ?? .offline(target)
        }
        if info.st_mode & S_IFMT == S_IFREG, (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true {
            guard let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
                  let real = realPath(resolved.path) else {
                let bookmark = try? URL.bookmarkData(withContentsOf: url)
                let volume = bookmark.flatMap { URL.resourceValues(forKeys: [.volumeURLKey], fromBookmarkData: $0)?.volume }
                return .offline(volume)
            }
            return .at(real)
        }
        return realPath(url.path).map(Resolved.at) ?? .missing
    }
}
