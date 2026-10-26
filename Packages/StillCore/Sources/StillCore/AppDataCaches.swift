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

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
            vsCode(id: "vscode-cache", name: "Visual Studio Code", nameShort: "Code", bundleID: "com.microsoft.VSCode"),
            vsCode(id: "vscodium-cache", name: "VSCodium", nameShort: "VSCodium", bundleID: "com.vscodium"),
        ]
    }
}
