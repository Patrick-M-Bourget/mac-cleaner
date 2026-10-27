import Foundation

/// Whether macOS lets the user move an item to the Trash without a password (Decision 50, #268): its folder is writable
/// and, for a folder item (an app or plug-in bundle), the item itself is writable. Read from permissions, never by trying.
public enum Removability {
    public static func canMoveToTrash(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, access(url.deletingLastPathComponent().path, W_OK | X_OK) == 0 else { return false }
        return info.st_mode & S_IFMT != S_IFDIR || access(url.path, W_OK) == 0
    }
}

/// One app or plug-in product on the Applications page (Decision 51), with the files it is made of. Read-only so far.
public struct InventoryEntry: Sendable, Equatable, Identifiable {
    public struct Part: Sendable, Equatable {
        /// What the part is: the app bundle's name, or a plug-in's format.
        public let name: String
        public let url: URL
        public let size: SizeEstimate
        public let removable: Bool
        public init(name: String, url: URL, size: SizeEstimate, removable: Bool) {
            self.name = name; self.url = url; self.size = size; self.removable = removable
        }
    }
    public let id: String
    public let name: String
    public let maker: String?
    /// The volume's name when it isn't the startup disk.
    public let volume: String?
    public let parts: [Part]
    public init(id: String, name: String, maker: String?, volume: String?, parts: [Part]) {
        self.id = id; self.name = name; self.maker = maker; self.volume = volume; self.parts = parts
    }
    /// Each part counted once.
    public var size: SizeEstimate { SizeEstimate(sum: parts.map(\.size)) }
    /// Nothing in it can go to the Trash without a password (Decision 50). A partly removable product offers what it can.
    public var needsPassword: Bool { !parts.isEmpty && parts.allSatisfy { !$0.removable } }
}

/// What the Applications page lists (Decision 51): apps and plug-in products, largest first. Nothing is called unused (42).
public enum ApplicationsInventory {
    /// The apps in an Applications folder (at its top or one folder down) on any volume, from `installed` (`AppPresence`):
    /// never Apple's, one in `/System`, one inside another bundle, CacheDrop itself, or one no longer on disk.
    public static func apps(_ installed: [InstalledApp], excluding ownBundleID: String?, sizer: KnownLocationSizer = KnownLocationSizer()) -> [InventoryEntry] {
        var seen = Set<String>()
        let entries = installed.compactMap { app -> InventoryEntry? in
            let url = URL(fileURLWithPath: app.path).standardizedFileURL
            guard seen.insert(url.path).inserted, isInApplicationsFolder(url), !app.bundleID.lowercased().hasPrefix("com.apple."),
                  app.bundleID != ownBundleID, FileManager.default.fileExists(atPath: url.path) else { return nil }
            let maker = PlugInInventory.info(url).flatMap(PlugInInventory.copyrightHolder) ?? app.maker
            return InventoryEntry(id: url.path, name: app.name, maker: maker, volume: volume(of: url),
                                  parts: [.init(name: url.lastPathComponent, url: url, size: Catalog.estimate(sizer.size(url)), removable: Removability.canMoveToTrash(url))])
        }
        return largestFirst(entries)
    }

    /// Plug-in products (Decision 42), each format a part, except Apple's own.
    public static func plugIns(_ inventory: PlugInInventory) -> [InventoryEntry] {
        largestFirst(inventory.products.filter { !$0.isApple }.map { product in
            InventoryEntry(id: product.id, name: product.name, maker: product.maker, volume: product.files.lazy.compactMap { volume(of: $0.url) }.first,
                           parts: product.files.map { .init(name: $0.format.rawValue, url: $0.url, size: $0.size, removable: Removability.canMoveToTrash($0.url)) })
        })
    }

    /// The managers vendors ship to install and remove their products (Decision 41), by the maker name they start with.
    static let vendorTools: [(maker: String, tool: String)] = [("Native Instruments", "Native Access"), ("Waves", "Waves Central"),
                                                               ("Arturia", "Arturia Software Center"), ("Softube", "Softube Central"),
                                                               ("Universal Audio", "UA Connect")]
    /// The maker's own tool, when it is among `apps`.
    public static func vendorTool(forMaker maker: String?, among apps: [InventoryEntry]) -> InventoryEntry? {
        guard let maker, let tool = vendorTools.first(where: { maker.lowercased().hasPrefix($0.maker.lowercased()) })?.tool else { return nil }
        return apps.first { $0.name == tool }
    }

    /// The volume a path is on, when it isn't the startup disk: "/Volumes/Studio/…" reads "Studio".
    static func volume(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        return parts.count > 2 && parts[1] == "Volumes" ? parts[2] : nil
    }

    static func isInApplicationsFolder(_ url: URL) -> Bool {
        let parts = url.pathComponents.dropLast()
        guard url.pathExtension == "app", parts.count > 1, parts[1] != "System", !parts.contains(where: { $0.hasSuffix(".app") }) else { return false }
        return parts.last == "Applications" || parts.dropLast().last == "Applications"
    }

    static func largestFirst(_ entries: [InventoryEntry]) -> [InventoryEntry] {
        func bytes(_ size: SizeEstimate) -> Int64 {
            switch size { case .measured(let b), .atLeast(let b), .about(let b): b; case .unknown: 0 }
        }
        return entries.sorted { (bytes($0.size), $1.name) > (bytes($1.size), $0.name) }
    }
}
