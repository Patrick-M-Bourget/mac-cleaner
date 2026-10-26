import Foundation

/// SPEC section 2: what a rule never acts on, as the item, an ancestor below its base, or an entry inside it.
/// Discovery, leaked copies, Downloads files and the check all use this one computation, so a scan never offers
/// what the check would refuse.
struct Protection {
    /// Never acted on: git work, the Trash, backups (spec section 2).
    static let names: Set<String> = [".git", ".Trash", "Backups.backupdb"]
    /// Packages and libraries that are never acted on, whatever folder holds them.
    static let extensions: Set<String> = ["app", "bundle", "framework", "xcarchive", "photoslibrary", "photolibrary", "musiclibrary", "backupbundle", "sparsebundle", "band", "logicx"]

    /// Protected names for the rule: the global ones, load-bearing caches, Still's own folders and the rule's own.
    let names: Set<String>
    /// Protected extensions for the rule: the global ones the rule may not act inside, plus the rule's own.
    let extensions: Set<String>

    init(_ rule: CleanupRule) {
        names = Self.names.union(Catalog.neverOffered).union(AppCaches.stillNames).union(rule.protectedNames)
        extensions = Self.extensions.subtracting(rule.unprotectedExtensions).union(rule.protectedExtensions.map { $0.lowercased() })
    }

    /// Whether a single file or folder name is protected: by name, by extension, or as macOS's or Still's own folder.
    func protects(_ name: String) -> Bool {
        names.contains(name) || extensions.contains((name as NSString).pathExtension.lowercased()) || AppCaches.isMacOSOrStill(name)
    }

    /// The first protected component of `url` below `base`, the item itself included.
    func protectedComponent(of url: URL, below base: URL) -> String? {
        url.standardizedFileURL.pathComponents.dropFirst(base.standardizedFileURL.pathComponents.count).first(where: protects)
    }
}
