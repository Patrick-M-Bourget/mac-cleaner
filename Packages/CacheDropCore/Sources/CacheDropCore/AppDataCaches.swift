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

    /// The Adobe video apps that share the media cache; nothing Adobe keeps for them is touched while one runs.
    static let adobeVideoApps = RuleOwner(name: "Adobe video apps",
                                          executables: ["Adobe Premiere*", "After Effects", "Adobe After Effects*", "Adobe Media Encoder*", "Adobe Audition*",
                                                        "Adobe Character Animator*", "Adobe Prelude*", "dynamiclinkmanager"])

    /// Adobe's video apps share one media cache, by default in ~/Library/Application Support/Adobe/Common (Adobe Help,
    /// "Delete media cache files manually": quit the app, then delete the files there): conformed audio and index files in
    /// `Media Cache Files`, the database that links them in `Media Cache`, and peak files in `Peak Files` (Adobe Help, "Manage
    /// media cache"). A cache moved in Settings › Media Cache is found from Adobe's settings (`AdobeMediaCache`, #730); the rest
    /// of Common (Motion Graphics Templates, LUTs, Team Projects) is never a location.
    static let adobeMediaCache = CleanupRule(
        id: AdobeMediaCache.ruleID, category: .photoVideo, title: "Adobe media cache",
        detail: "Conformed audio, peak and index files Premiere, After Effects and Media Encoder made from your media.",
        consequence: "Your projects and media are kept, and Adobe apps rebuild these files when you open a project.",
        regen: .cache, action: .delete,
        locations: AdobeMediaCache.cacheFolders.map { AdobeMediaCache.defaultFolder + "/" + $0 },
        owner: adobeVideoApps)

    /// Premiere Pro's own cache for each version, ~/Library/Caches/Adobe/Premiere Pro/<version> (observed on 26.0, #730: its
    /// type support cache and crash reporter's database). Its settings (~/Library/Preferences/Adobe) and projects and
    /// auto-saves (~/Documents/Adobe) are never locations.
    static let premiereProCache = CleanupRule(
        id: "premiere-pro-cache", category: .photoVideo, title: "Premiere Pro cache",
        detail: "Files Premiere Pro keeps to start and work faster, per version.",
        consequence: "Your projects, settings and media are kept, and Premiere Pro rebuilds these files as you use it.",
        regen: .cache, action: .delete, locations: ["Library/Caches/Adobe/Premiere Pro/*"], owner: adobeVideoApps,
        itemName: { "Premiere Pro " + $0 })

    /// After Effects' cache for each version, ~/Library/Caches/Adobe/After Effects/<version>, where its disk cache is kept by
    /// default (#400, Decision 165). Adobe Help ("Memory and storage") documents the disk cache, "up to 100 GB" by default,
    /// kept after quitting and separate per version, but not its macOS folder; that folder is from secondary sources
    /// (freevisuals.net, MacKeeper, an Adobe community bug report on old versions' disk caches), not observed. Anything in
    /// ~/Library/Caches is rebuilt by its app, so a folder named otherwise is simply not found. A disk cache moved in Settings ›
    /// Disk isn't offered: where After Effects records it isn't documented, and CacheDrop doesn't guess. Real check: #736.
    static let afterEffectsCache = CleanupRule(
        id: "after-effects-cache", category: .photoVideo, title: "After Effects cache",
        detail: "Frames After Effects saved to preview faster, per version.",
        consequence: "Your projects, settings and media are kept, and After Effects saves frames again as you preview.",
        regen: .cache, action: .delete, locations: ["Library/Caches/Adobe/After Effects/*"], owner: adobeVideoApps,
        itemName: { "After Effects " + $0 })

    // MARK: Audio production (#139)

    /// Ableton Live's cache folder, by default ~/Library/Caches/Ableton/Cache (Ableton Help, "The file could not be read.
    /// It may be corrupt or not licensed", help.ableton.com/hc/en-us/articles/209774325). Live keeps the WAV files it
    /// decodes from compressed samples in its Decoding subfolder and decodes them again when needed (Live 12 manual,
    /// "Managing Files and Sets": Decoding Cache). A cache folder moved in Settings > File & Folder isn't found. The
    /// bundle identifier and executable are from Live 12's Info.plist (`com.ableton.live`, `Live`).
    static let abletonCache = CleanupRule(
        id: "ableton-cache", category: .audio, title: "Ableton Live cache",
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
            // A category is listed where its first rule is, so App caches' first rule here comes before the field categories:
            // App caches, Audio software, then Photo and video (Decision 164).
            sandboxedCaches(apps: apps),
            abletonCache,
            adobeMediaCache,
            premiereProCache,
            afterEffectsCache,
            vsCode(id: "vscode-cache", name: "Visual Studio Code", nameShort: "Code", bundleID: "com.microsoft.VSCode"),
            vsCode(id: "vscodium-cache", name: "VSCodium", nameShort: "VSCodium", bundleID: "com.vscodium"),
            vsCode(id: "cursor-cache", name: "Cursor", nameShort: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
            vsCode(id: "windsurf-cache", name: "Windsurf", nameShort: "Windsurf", bundleID: "com.exafunction.windsurf"),
        ]
    }
}
