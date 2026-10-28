import Foundation

/// SPEC section 2: what a rule never acts on, as the item, an ancestor below its base, or an entry inside it.
/// Discovery, leaked copies, Downloads files and the check all use this one computation, so a scan never offers
/// what the check would refuse.
struct Protection {
    /// Never acted on by a rule: git work, the Trash, backups (spec section 2). CacheDrop never empties the Trash; it
    /// deletes from it only items it moved there itself, when you ask (Decision 68).
    static let names: Set<String> = [".git", ".Trash", ".Trashes", "Backups.backupdb"]
    /// Packages and libraries that are never acted on, whatever folder holds them.
    static let extensions: Set<String> = ["app", "bundle", "framework", "xcarchive", "photoslibrary", "photolibrary", "musiclibrary", "backupbundle", "sparsebundle", "band", "logicx"]

    /// Protected names for the rule: the global ones, load-bearing caches, CacheDrop's and Still's own folders and the rule's own.
    let names: Set<String>
    /// Protected extensions for the rule: the global ones the rule may not act inside, plus the rule's own.
    let extensions: Set<String>
    /// macOS folder names the rule may act inside (`CleanupRule.unprotectedNames`).
    let macOSNamesAllowed: Set<String>

    init(_ rule: CleanupRule) {
        names = Self.names.union(Catalog.neverOffered).union(AppCaches.ownNames).union(rule.protectedNames)
        extensions = Self.extensions.subtracting(rule.unprotectedExtensions).union(rule.protectedExtensions.map { $0.lowercased() })
        macOSNamesAllowed = rule.unprotectedNames
    }

    /// Whether a single file or folder name is protected: by name, by extension, or as macOS's, CacheDrop's or Still's own folder.
    func protects(_ name: String) -> Bool {
        names.contains(name) || extensions.contains((name as NSString).pathExtension.lowercased()) || (AppCaches.isMacOSOrOwn(name) && !macOSNamesAllowed.contains(name))
    }

    /// The Trash, the user's and a volume's: no rule or check acts on it wherever it lies on the path, the base included,
    /// so a picked `~/.Trash` or a folder inside it offers nothing (#129). The only deletions from the Trash are of items
    /// CacheDrop moved there itself, when you ask (`TrashEmptying`, Decision 68).
    static let trashNames: Set<String> = [".Trash", ".Trashes"]

    /// The first protected component of `url` below `base`, the item itself included; a Trash anywhere on the path.
    func protectedComponent(of url: URL, below base: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        if let trash = components.first(where: Self.trashNames.contains) { return trash }
        return components.dropFirst(base.standardizedFileURL.pathComponents.count).first(where: protects)
    }
}
