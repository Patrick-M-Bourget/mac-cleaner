import Foundation

/// Caches apps keep outside ~/Library/Caches (#133): in their Application Support folder, or in a sandboxed app's
/// container. Each rule allowlists cache folders only; the app's own data around them is never a location, and its
/// names are protected in case a cache folder ever holds one.
public enum AppDataCaches {
    // MARK: VS Code

    /// What a VS Code profile keeps besides its caches: settings, extensions, unsaved work and state.
    static let vsCodeData = ["User", "extensions", "Backups", "globalStorage", "workspaceStorage", "History", "snippets", "storage.json"]

    /// VS Code keeps its data in ~/Library/Application Support/<product.nameShort> (vscode source,
    /// `getDefaultUserDataPath` in src/vs/platform/environment/node/userDataPath.ts). Inside it, `Cache`, `Code Cache` and
    /// `GPUCache` are Electron's (Chromium's) caches, `CachedData` is VS Code's compiled-code cache, and
    /// `CachedExtensionVSIXs` holds extension downloads. The app's executable is named after nameShort too.
    /// VSCodium sets nameShort "VSCodium" and bundle identifier "com.vscodium" (VSCodium's prepare_vscode.sh).
    /// Cursor isn't listed: its layout isn't documented.
    static func vsCode(id: String, name: String, nameShort: String, bundleID: String) -> CleanupRule {
        CleanupRule(id: id, category: .developer, title: name + " caches",
                    detail: "Cached code, graphics and extension downloads.",
                    consequence: "Permanently removed. Settings, extensions and unsaved work are kept. \(name) rebuilds its caches; it may start more slowly at first.",
                    regen: .cache, action: .delete,
                    locations: ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache"].map { "Library/Application Support/\(nameShort)/\($0)" },
                    owner: RuleOwner(name: name, bundleIDs: [bundleID], executables: [nameShort, nameShort + " Helper*"]),
                    protectedNames: vsCodeData)
    }

    // MARK: JetBrains

    /// JetBrains IDEs keep caches, indexes and local history in ~/Library/Caches/JetBrains/<product><version>
    /// (JetBrains, "Directories used by the IDE": `~/Library/Caches/JetBrains/IntelliJIdea2026.2`). Each product's
    /// folder name, with the name and launcher (Contents/MacOS) of the IDE that uses it.
    static let jetBrainsProducts: [String: (name: String, executable: String)] = [
        "IntelliJIdea": ("IntelliJ IDEA", "idea"), "IdeaIC": ("IntelliJ IDEA", "idea"), "PyCharm": ("PyCharm", "pycharm"),
        "PyCharmCE": ("PyCharm", "pycharm"), "WebStorm": ("WebStorm", "webstorm"), "PhpStorm": ("PhpStorm", "phpstorm"),
        "GoLand": ("GoLand", "goland"), "CLion": ("CLion", "clion"), "Rider": ("Rider", "rider"), "RubyMine": ("RubyMine", "rubymine"),
        "DataGrip": ("DataGrip", "datagrip"), "RustRover": ("RustRover", "rustrover"), "DataSpell": ("DataSpell", "dataspell"),
    ]
    /// "IntelliJIdea2024.2" as ("IntelliJIdea", [2024, 2]); nil for a name without a version.
    static func jetBrainsVersion(_ name: String) -> (product: String, version: [Int])? {
        guard let start = name.firstIndex(where: \.isNumber), start != name.startIndex else { return nil }
        let parts = name[start...].split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.contains(nil) else { return nil }
        return (String(name[..<start]), parts.compactMap { $0 })
    }
    /// The IDE an older version's folder belongs to. The newest version of each product is the one the installed IDE
    /// uses, so it has no owner Still can close and is never offered; nor is a product Still doesn't know.
    static func jetBrainsOwner(_ url: URL) -> RuleOwner? {
        guard let (product, version) = jetBrainsVersion(url.lastPathComponent), let ide = jetBrainsProducts[product],
              let siblings = try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) else { return nil }
        let newer = siblings.contains { name in
            guard let other = jetBrainsVersion(name), other.product == product else { return false }
            return version.lexicographicallyPrecedes(other.version)
        }
        return newer ? RuleOwner(name: ide.name, executables: [ide.executable]) : nil
    }
    static let jetBrains = CleanupRule(id: "jetbrains-caches", category: .developer, title: "Old JetBrains IDE caches",
                                       detail: "Caches and indexes of older IDE versions. The newest version of each IDE is kept.",
                                       consequence: "Permanently removed, with that version’s local history. Newer versions keep their own caches and history.",
                                       regen: .cache, action: .delete, locations: ["Library/Caches/JetBrains/*"], owner: nil,
                                       itemOwner: jetBrainsOwner, protectedDepth: AppCaches.liveWorkDepth)

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
            jetBrains,
            vsCode(id: "vscode-cache", name: "Visual Studio Code", nameShort: "Code", bundleID: "com.microsoft.VSCode"),
            vsCode(id: "vscodium-cache", name: "VSCodium", nameShort: "VSCodium", bundleID: "com.vscodium"),
        ]
    }
}
