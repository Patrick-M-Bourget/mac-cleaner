import Foundation

/// Whether macOS lets the user move an item to the Trash without a password (Decision 50, #268): its folder is writable
/// and, for a folder item (an app or plug-in bundle), the item itself is writable; in a folder with the sticky bit, the user
/// must also own the item or the folder (#271). Read from permissions, never by trying.
public enum Removability {
    /// `user` stands in for the current user's ID, so a test can ask as someone who owns nothing.
    public static func canMoveToTrash(_ url: URL, asUser user: uid_t = getuid()) -> Bool {
        var info = stat(), folder = stat()
        let parent = url.deletingLastPathComponent().path
        guard lstat(url.path, &info) == 0, stat(parent, &folder) == 0, access(parent, W_OK | X_OK) == 0 else { return false }
        if folder.st_mode & S_ISVTX != 0, !stickyFolderAllows(user: user, itemOwner: info.st_uid, folderOwner: folder.st_uid) { return false }
        return info.st_mode & S_IFMT != S_IFDIR || access(url.path, W_OK) == 0
    }
    /// In a sticky folder, only the item's owner, the folder's owner or root may move an item.
    static func stickyFolderAllows(user: uid_t, itemOwner: uid_t, folderOwner: uid_t) -> Bool {
        user == 0 || user == itemOwner || user == folderOwner
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
    /// The app's bundle ID, or a plug-in product's first: what ties it to its vendor (Decision 41).
    public let bundleID: String?
    public init(id: String, name: String, maker: String?, volume: String?, parts: [Part], bundleID: String? = nil) {
        self.id = id; self.name = name; self.maker = maker; self.volume = volume; self.parts = parts; self.bundleID = bundleID
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
            guard seen.insert(url.path).inserted, isListed(app, excluding: ownBundleID) else { return nil }
            let maker = PlugInInventory.info(url).flatMap(PlugInInventory.copyrightHolder) ?? app.maker
            return InventoryEntry(id: url.path, name: app.name, maker: maker, volume: volume(of: url),
                                  parts: [.init(name: url.lastPathComponent, url: url, size: Catalog.estimate(sizer.size(url)), removable: Removability.canMoveToTrash(url))],
                                  bundleID: app.bundleID)
        }
        return largestFirst(entries)
    }

    /// Whether the page lists an app: in an Applications folder, still on disk, never Apple's, a system app or CacheDrop itself.
    public static func isListed(_ app: InstalledApp, excluding ownBundleID: String?) -> Bool {
        let url = URL(fileURLWithPath: app.path).standardizedFileURL
        return isInApplicationsFolder(url) && !app.bundleID.lowercased().hasPrefix("com.apple.") && app.bundleID != ownBundleID
            && FileManager.default.fileExists(atPath: url.path)
    }

    /// Plug-in products (Decision 42), each format a part, except Apple's own.
    public static func plugIns(_ inventory: PlugInInventory) -> [InventoryEntry] {
        largestFirst(inventory.products.filter { !$0.isApple }.map { product in
            InventoryEntry(id: product.id, name: product.name, maker: product.maker, volume: product.files.lazy.compactMap { volume(of: $0.url) }.first,
                           parts: product.files.map { .init(name: $0.format.rawValue, url: $0.url, size: $0.size, removable: Removability.canMoveToTrash($0.url)) },
                           bundleID: product.files.lazy.compactMap(\.bundleID).first)
        })
    }

    /// The maker's own tool, when it is among `apps` (Decision 41): tied to the entry by its bundle ID's vendor, never by name.
    public static func vendorTool(for entry: InventoryEntry, among apps: [InventoryEntry]) -> InventoryEntry? {
        guard let tool = VendorTool.known.first(where: { $0.makes(entry.bundleID) }) else { return nil }
        return apps.first { $0 != entry && $0.bundleID?.lowercased() == tool.bundleID }
    }

    /// The app's own uninstaller, or its maker's tool (Decision 41, #177): an app named "Uninstall…" in the app's own folder
    /// (not the Applications folder itself) or named for the app, else `vendorTool(for:among:)`.
    public static func uninstaller(for entry: InventoryEntry, among apps: [InventoryEntry]) -> InventoryEntry? {
        let folder = URL(fileURLWithPath: entry.id).deletingLastPathComponent(), name = RemovedAppLeftovers.token(entry.name)
        let own = apps.first { app in
            let token = RemovedAppLeftovers.token(app.name)
            guard app != entry, token.contains("uninstall") else { return false }
            return (URL(fileURLWithPath: app.id).deletingLastPathComponent() == folder && folder.lastPathComponent != "Applications")
                || (name.count >= 3 && token.contains(name))
        }
        return own ?? vendorTool(for: entry, among: apps)
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

/// A manager a vendor ships to install and remove its products (Decision 41), such as Native Access.
public struct VendorTool: Sendable, Equatable {
    /// The vendor's part of a bundle ID, lowercased: `com.native-instruments` for `com.native-instruments.kontakt-8.vst3`.
    public let vendor: String
    /// The tool app's own bundle ID, lowercased: the tool is the installed app with exactly this ID.
    public let bundleID: String

    public static let known = [VendorTool(vendor: "com.native-instruments", bundleID: "com.native-instruments.nativeaccess2"),  // checked on this Mac
                               VendorTool(vendor: "com.uaudio", bundleID: "com.uaudio.ua-connect"),                            // checked on this Mac
                               // Not checked: none of these is installed on the Mac this was written on.
                               VendorTool(vendor: "com.wavesaudio", bundleID: "com.wavesaudio.wavescentral"),
                               VendorTool(vendor: "com.arturia", bundleID: "com.arturia.arturiasoftwarecenter"),
                               VendorTool(vendor: "com.softube", bundleID: "com.softube.softubecentral")]

    /// Whether a bundle ID is this vendor's.
    func makes(_ bundleID: String?) -> Bool { bundleID.map { RemovedAppLeftovers.vendor(of: $0) == vendor } ?? false }
}
