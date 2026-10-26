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
    /// macOS folder names the rule may act inside (`CleanupRule.unprotectedNames`).
    let macOSNamesAllowed: Set<String>

    init(_ rule: CleanupRule) {
        names = Self.names.union(Catalog.neverOffered).union(AppCaches.stillNames).union(rule.protectedNames)
        extensions = Self.extensions.subtracting(rule.unprotectedExtensions).union(rule.protectedExtensions.map { $0.lowercased() })
        macOSNamesAllowed = rule.unprotectedNames
    }

    /// Whether a single file or folder name is protected: by name, by extension, or as macOS's or Still's own folder.
    func protects(_ name: String) -> Bool {
        names.contains(name) || extensions.contains((name as NSString).pathExtension.lowercased()) || (AppCaches.isMacOSOrStill(name) && !macOSNamesAllowed.contains(name))
    }

    /// The first protected component of `url` below `base`, the item itself included.
    func protectedComponent(of url: URL, below base: URL) -> String? {
        url.standardizedFileURL.pathComponents.dropFirst(base.standardizedFileURL.pathComponents.count).first(where: protects)
    }

    /// Whether a `.git` entry sits in a folder holding `url`, from its parent up to and including `top`.
    /// A file inside a git working tree is live work, never a candidate (SPEC section 2). The home folder itself
    /// doesn't count: a dotfiles repository there doesn't make Downloads or a picked folder live work.
    static func insideGitCheckout(_ url: URL, upTo top: URL) -> Bool {
        let topPath = top.standardizedFileURL.path, home = realPath(NSHomeDirectory())
        var folder = url.standardizedFileURL.deletingLastPathComponent()
        while folder.path.hasPrefix(topPath) {
            var info = stat()
            if folder.path != home, lstat(folder.appendingPathComponent(".git").path, &info) == 0 { return true }
            if folder.path == topPath || folder.path == "/" { return false }
            folder = folder.deletingLastPathComponent()
        }
        return false
    }
}
