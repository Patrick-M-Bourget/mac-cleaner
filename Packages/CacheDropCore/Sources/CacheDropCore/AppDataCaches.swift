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
    /// Cursor and Windsurf are VS Code forks with the same layout (#140): ~/Library/Application Support/Cursor
    /// (Cursor docs, where `User/settings.json` lives; bundle identifier "com.todesktop.230313mzl4w4u92") and
    /// ~/Library/Application Support/Windsurf (bundle identifier "com.exafunction.windsurf").
    static func vsCode(id: String, name: String, nameShort: String, bundleID: String) -> CleanupRule {
        CleanupRule(id: id, category: .developer, title: name + " caches",
                    detail: "Cached code, graphics and extension downloads.",
                    consequence: "Settings, extensions and unsaved work are kept, and \(name) rebuilds its caches.",
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
    /// The bundle identifier of each product's app, as in its Info.plist; an EAP build adds "-EAP".
    static let jetBrainsBundleIDs: [String: String] = [
        "com.jetbrains.intellij": "IntelliJIdea", "com.jetbrains.intellij.ce": "IdeaIC", "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.pycharm.ce": "PyCharmCE", "com.jetbrains.WebStorm": "WebStorm", "com.jetbrains.PhpStorm": "PhpStorm",
        "com.jetbrains.goland": "GoLand", "com.jetbrains.CLion": "CLion", "com.jetbrains.rider": "Rider", "com.jetbrains.rubymine": "RubyMine",
        "com.jetbrains.datagrip": "DataGrip", "com.jetbrains.rustrover": "RustRover", "com.jetbrains.dataspell": "DataSpell",
    ]
    static func jetBrainsProduct(bundleID: String) -> String? {
        let id = bundleID.hasSuffix("-EAP") ? String(bundleID.dropLast(4)) : bundleID
        return jetBrainsBundleIDs.first { $0.key.caseInsensitiveCompare(id) == .orderedSame }?.value
    }
    /// "2025.2.1" (or "2025.2 EAP") as [2025, 2], the release its cache folder is named after; nil otherwise.
    static func jetBrainsReleaseVersion(_ text: String) -> [Int]? {
        let parts = (text.split(separator: " ").first ?? "").split(separator: ".").prefix(2).map { Int($0) }
        guard parts.count == 2, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }
    /// The IDE an older version's folder belongs to. Never offered: the folder of any installed version, every folder
    /// of a product installed in a version CacheDrop can't read, the newest folder of each product (an install CacheDrop didn't
    /// find may use it), and a product CacheDrop doesn't know.
    static func jetBrainsOwner(_ url: URL, apps: any AppLookup) -> RuleOwner? {
        guard let (product, version) = jetBrainsVersion(url.lastPathComponent), let ide = jetBrainsProducts[product],
              let siblings = try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) else { return nil }
        let installed = apps.jetBrainsIDEs().filter { $0.product == product }
        guard installed.allSatisfy({ $0.version != nil && $0.version != version }) else { return nil }
        let newer = siblings.contains { name in
            guard let other = jetBrainsVersion(name), other.product == product else { return false }
            return version.lexicographicallyPrecedes(other.version)
        }
        return newer ? RuleOwner(name: ide.name, executables: [ide.executable]) : nil
    }
    static func jetBrains(apps: any AppLookup) -> CleanupRule {
        CleanupRule(id: "jetbrains-caches", category: .developer, title: "Old JetBrains IDE caches",
                    detail: "Caches and indexes of older IDE versions. The versions you have installed, and the newest of each IDE, are kept.",
                    consequence: "That version’s local history goes too; newer versions keep their own.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/JetBrains/*"], owner: nil,
                    itemOwner: { jetBrainsOwner($0, apps: apps) }, protectedDepth: AppCaches.liveWorkDepth, itemByItem: true)
    }

    // MARK: Adobe

    /// Adobe's video apps share one media cache, by default in ~/Library/Application Support/Adobe/Common (Adobe Help,
    /// "Delete media cache files manually": quit the app, then delete the files there): conformed audio, peak and
    /// index files in `Media Cache Files`, and the database that links them in `Media Cache`. A cache moved in
    /// Preferences > Media Cache isn't found; what stays in the default folder is still cache.
    static let adobeMediaCache = CleanupRule(
        id: "adobe-media-cache", category: .system, title: "Adobe media cache",
        detail: "Conformed audio, peak and index files Premiere, After Effects and Media Encoder made from your media.",
        consequence: "Your projects and media are kept, and Adobe apps rebuild these files when you open a project.",
        regen: .cache, action: .delete,
        locations: ["Library/Application Support/Adobe/Common/Media Cache Files", "Library/Application Support/Adobe/Common/Media Cache"],
        owner: RuleOwner(name: "Adobe video apps",
                         executables: ["Adobe Premiere*", "After Effects", "Adobe After Effects*", "Adobe Media Encoder*", "Adobe Audition*",
                                       "Adobe Character Animator*", "Adobe Prelude*", "dynamiclinkmanager"]))

    // MARK: Audio production (#139)

    /// Ableton Live's cache folder, by default ~/Library/Caches/Ableton/Cache (Ableton Help, "The file could not be read.
    /// It may be corrupt or not licensed", help.ableton.com/hc/en-us/articles/209774325). Live keeps the WAV files it
    /// decodes from compressed samples in its Decoding subfolder and decodes them again when needed (Live 12 manual,
    /// "Managing Files and Sets": Decoding Cache). A cache folder moved in Settings > File & Folder isn't found. The
    /// bundle identifier and executable are from Live 12's Info.plist (`com.ableton.live`, `Live`).
    static let abletonCache = CleanupRule(
        id: "ableton-cache", category: .system, title: "Ableton Live cache",
        detail: "WAV files Live decoded from your MP3, AAC and other compressed samples.",
        consequence: "Your Sets, samples and Packs are kept, and Live decodes samples again when it next plays them.",
        regen: .cache, action: .delete, locations: ["Library/Caches/Ableton/Cache"],
        owner: RuleOwner(name: "Ableton Live", bundleIDs: ["com.ableton.live"], executables: ["Live"]))

    // MARK: Sandboxed apps

    /// A sandboxed app's caches folder, `~/Library/Containers/<bundle id>/Data/Library/Caches`: its own ~/Library/Caches
    /// (Apple, File System Programming Guide: a sandboxed app's container). The rest of the container is the app's data
    /// and is never a location; nor are group containers, which several apps share.
    static let containerCaches = "Library/Containers/*/Data/Library/Caches"
    /// The installed app whose container holds the caches folder; nil for macOS's, CacheDrop's and Still's own, or an app that isn't installed.
    static func containerOwner(_ url: URL, apps: any AppLookup) -> RuleOwner? {
        let parts = url.pathComponents
        guard parts.count > 5, Array(parts.suffix(3)) == ["Data", "Library", "Caches"], parts[parts.count - 5] == "Containers" else { return nil }
        return AppCaches.installedOwner(parts[parts.count - 4], apps: apps)
    }
    /// Reading another app's container can make macOS ask the user for access, so the rule is read only with Full Disk
    /// Access; without it the row says not accessible (`FullDiskAccessProbe` never opens a container for the same reason).
    static func sandboxedCaches(apps: any AppLookup) -> CleanupRule {
        CleanupRule(id: "container-caches", category: .system, title: "Sandboxed app caches",
                    detail: "Files sandboxed apps keep to start and work faster, per app.",
                    consequence: "Only each app’s caches folder goes; its documents, settings and other data are kept.",
                    regen: .cache, action: .delete, locations: [containerCaches], owner: nil,
                    itemOwner: { containerOwner($0, apps: apps) }, protectedDepth: AppCaches.liveWorkDepth, requiresFullDiskAccess: true)
    }

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
            jetBrains(apps: apps),
            adobeMediaCache,
            abletonCache,
            sandboxedCaches(apps: apps),
            vsCode(id: "vscode-cache", name: "Visual Studio Code", nameShort: "Code", bundleID: "com.microsoft.VSCode"),
            vsCode(id: "vscodium-cache", name: "VSCodium", nameShort: "VSCodium", bundleID: "com.vscodium"),
            vsCode(id: "cursor-cache", name: "Cursor", nameShort: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
            vsCode(id: "windsurf-cache", name: "Windsurf", nameShort: "Windsurf", bundleID: "com.exafunction.windsurf"),
        ]
    }
}
