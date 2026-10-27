import AppKit
import Foundation

/// Updater downloads, per-app caches and the user's logs (#103).
public enum AppCaches {
    /// CacheDrop's own folders, and those of Still (its former name), by name and bundle ID, the apps' and the UI-test runners',
    /// never offered under any rule (`Protection`). A folder inside a candidate is matched by exact name, so each is listed (#211);
    /// any other ID of theirs (`.xctrunner`) is caught by `isOwn`'s prefix check, which the inner search applies too.
    static let ownNames = ["CacheDrop", "Still", "com.patrickbourget.CacheDrop", "com.patrickbourget.Still",
                           "com.patrickbourget.CacheDropUITests", "com.patrickbourget.StillUITests"]

    /// Levels searched for a git checkout or other protected name inside a cache or log folder. A path under Caches
    /// doesn't prove a folder is disposable: the field scan found an agent's live checkout two levels down.
    static let liveWorkDepth = 4

    /// A folder name that is an app's bundle identifier: reverse-DNS with at least three parts.
    static func isBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { part in !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
            && parts[0].first?.isLetter == true
    }
    /// macOS's own caches and CacheDrop's (or Still's) are never offered, whoever asks.
    static func isExcluded(_ bundleID: String) -> Bool {
        bundleID.lowercased().hasPrefix("com.apple.") || isOwn(bundleID)
    }
    /// A folder or bundle ID of CacheDrop's or Still's, any of their apps or UI-test runners, by name or ID prefix.
    static func isOwn(_ name: String) -> Bool {
        let id = name.lowercased()
        return ownNames.contains(name) || id.hasPrefix("com.patrickbourget.still") || id.hasPrefix("com.patrickbourget.cachedrop")
    }
    /// A folder of macOS's own, CacheDrop's or Still's, by bundle identifier or name. Never offered under any rule,
    /// so logs and every other location leave them alone as app caches do.
    static func isMacOSOrOwn(_ name: String) -> Bool { isExcluded(name) }
    /// The installed app a folder named by bundle identifier belongs to, or nil when that can't be determined.
    static func installedOwner(_ folder: String, apps: any AppLookup) -> RuleOwner? {
        guard isBundleID(folder), !isExcluded(folder), let app = apps.app(bundleID: folder) else { return nil }
        return RuleOwner(name: app.name, bundleIDs: [folder], paths: [app.path])
    }

    /// Who an updater download belongs to, from how each updater names its folder; nil when that can't be determined.
    /// A process run from inside the download folder (Sparkle's installer) also counts as the owner.
    static func updaterOwner(_ url: URL, apps: any AppLookup) -> RuleOwner? {
        let name = url.lastPathComponent
        // Sparkle: ~/Library/Caches/<host bundle id>/org.sparkle-project.Sparkle. Squirrel.Mac: ~/Library/Caches/<bundle id>.ShipIt.
        let bundleID = name == sparkleFolder ? url.deletingLastPathComponent().lastPathComponent
            : name.hasSuffix(".ShipIt") ? String(name.dropLast(".ShipIt".count)) : nil
        if let bundleID {
            guard isBundleID(bundleID), !isExcluded(bundleID) else { return nil }
            let app = apps.app(bundleID: bundleID)
            // Squirrel's ShipIt is launched with its job label, `<bundle id>.ShipIt`.
            return RuleOwner(name: app?.name ?? bundleID, bundleIDs: [bundleID], arguments: name == sparkleFolder ? [] : [name],
                             paths: [app?.path, url.path].compactMap { $0 })
        }
        // electron-updater: ~/Library/Caches/<updaterCacheDirName>, named in the app's own app-update.yml.
        guard name.hasSuffix("-updater"), let app = apps.app(updaterCacheDirName: name), !isExcluded(app.bundleID) else { return nil }
        return RuleOwner(name: app.name, bundleIDs: [app.bundleID], paths: [app.path, url.path])
    }
    static let sparkleFolder = "org.sparkle-project.Sparkle"

    /// Offline or downloaded content an app can keep in its own `~/Library/Caches/<bundle id>` folder (#171). While any of these
    /// files is anywhere inside the app's folder, "App caches" offers every item but the one holding it (#243) and the check refuses it: it is not a cache
    /// the app rebuilds. Each exception cites the vendor's documentation or an observed layout; an app not listed keeps the rule as is.
    ///
    /// Audit of the apps this rule matches (2026-10-26; folder names seen on a Mac, never file contents):
    /// - Spotify (`com.spotify.client`): exception below. Spotify keeps "downloaded music and podcasts to play offline" apart from
    ///   its cache, and Settings > Storage can move that storage elsewhere
    ///   (https://support.spotify.com/us/article/storage-and-data-information/). Observed: the cache folder holds the streaming cache
    ///   (`Data`) and a web-view profile, while downloads sit in `~/Library/Application Support/Spotify/PersistentCache` as `Storage`
    ///   with `offline.bnk` beside it. Spotify's community reports downloads in `~/Library/Caches/com.spotify.Client/storage` too
    ///   (https://community.spotify.com/t5/Desktop-Mac/Where-are-offline-files-stored-on-Mac/m-p/1367628,
    ///   https://community.spotify.com/t5/Live-Ideas/Let-user-select-where-to-save-files-for-offline-mode/idi-p/7410350),
    ///   and Settings > Storage accepts any folder name, so downloads are recognized by their `offline.bnk` file at any depth (#203).
    /// - Ableton Live (`com.ableton.live`), Pro Tools (`com.avid.ProTools`), Slack (`com.tinyspeck.slackmacgap`), Native Access,
    ///   UA Connect, LANDR, Claude, CleanShot X: observed only the URL loading system's cache (`Cache.db`, `fsCachedData`),
    ///   `WebKit` and crash reporters' folders (`io.sentry`), which are refetched or rewritten. Rebuildable.
    ///   Live's sample decoding cache and Packs live elsewhere (`~/Library/Caches/Ableton`, not a bundle-identifier folder,
    ///   and the User Library), so this rule never reaches them.
    /// - Steam, Microsoft Teams, Adobe apps: not installed on the audited Mac, so no layout to observe. Their folders keep today's
    ///   behavior until one is audited with vendor sources. Browsers have their own rules (`BrowserCaches`).
    static let knownOfflineContent: [String: OfflineContent] = [
        "com.spotify.client": OfflineContent(names: ["offline.bnk"], label: "Spotify’s offline downloads"),
    ]
    static let appCachesRuleID = "app-caches"

    /// Entries that make a folder an embedded web view's profile with the user's sign-in data (#203), as Chromium and
    /// Electron name them (seen in Spotify's cache folder). A folder holding a profile is never offered whole.
    static let signInNames = ["Cookies", "Login Data", "Local Storage"]
    /// Chromium's profile list and browser settings beside its profiles (#243): not sign-in data, but removing it can reset an
    /// app's embedded browser, so it is kept like the sign-in files, wherever it sits in the app's folder.
    static let keptNames = ["Local State"]
    /// A web-view profile's parts that the web view rebuilds, the only parts of a profile ever offered (#203).
    static let webViewCacheParts: Set<String> = ["Cache", "Code Cache", "GPUCache"]

    /// The app's folder right below `~/Library/Caches` that `url` is or is inside; nil when it is in none.
    static func appFolder(of url: URL) -> URL? {
        let parts = url.standardizedFileURL.pathComponents
        guard let caches = parts.indices.dropLast().last(where: { parts[$0] == "Library" && parts[$0 + 1] == "Caches" }), caches + 2 < parts.count else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(parts[...(caches + 2)])), isDirectory: true)
    }

    /// Whether `folder` directly holds sign-in data: a web-view profile.
    static func isWebViewProfile(_ folder: URL) -> Bool {
        signInNames.contains { name in
            var info = stat()
            return lstat(folder.appendingPathComponent(name).path, &info) == 0
        }
    }

    /// The paths of the folders that directly hold an entry named in `names`, up to `depth` levels inside `folder`;
    /// nil when it can't be fully searched.
    static func folders(holding names: Set<String>, in folder: URL, depth: Int) -> Set<String>? {
        entries(named: names, in: folder, depth: depth).map { Set($0.map { ($0 as NSString).deletingLastPathComponent }) }
    }

    /// The paths of the entries named in `names`, up to `depth` levels inside `folder`; nil when it can't be fully searched.
    static func entries(named names: Set<String>, in folder: URL, depth: Int) -> Set<String>? {
        var found = Set<String>(), seen = 0, complete = true
        let opened = FileTree.walk(folder) { entry in
            let level = Int(entry.pointee.fts_level), kind = Int32(entry.pointee.fts_info)
            guard level > 0, kind != FTS_DP else { return .continue }
            seen += 1
            if seen > CandidateCheck.protectedSearchLimit || kind == FTS_DNR || kind == FTS_ERR { complete = false; return .stop }
            let path = String(cString: entry.pointee.fts_path)
            if names.contains((path as NSString).lastPathComponent) { found.insert(path) }
            return kind == FTS_D && level >= depth ? .skip : .continue
        }
        return opened && complete ? found : nil
    }

    /// Whether one of two paths is or is inside the other.
    static func overlaps(_ a: String, _ b: String) -> Bool { a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/") }

    /// What "App caches" offers from an app's folder: the folder itself, or, when it holds web-view profiles with sign-in data or a
    /// `Local State` within `liveWorkDepth` levels, or the app's offline content (`offlineContent`) at any depth, every item in it
    /// except those, and of each profile only its `Cache`, `Code Cache` and `GPUCache` (#203, #241, #243). A folder on the way to a
    /// profile or a `Local State` is not offered whole; its items are. An item that is or holds the offline content, or sits in a
    /// folder holding it, is left out whole.
    /// A folder that can't be fully searched comes back whole, and the protected-entry search then leaves it out.
    static func offeredFolders(in appFolder: URL, offlineContent: [String: OfflineContent]) -> [URL] {
        guard Catalog.isFolder(appFolder), let found = entries(named: Set(signInNames + keptNames), in: appFolder, depth: liveWorkDepth)
        else { return [appFolder] }
        let kept = found.filter { keptNames.contains(($0 as NSString).lastPathComponent) }
        let profiles = Set(found.subtracting(kept).map { ($0 as NSString).deletingLastPathComponent })
        var offline = Set<String>()
        if let content = offlineContent[appFolder.lastPathComponent.lowercased()] {
            guard let holders = folders(holding: content.names, in: appFolder, depth: .max) else { return [appFolder] }
            offline = holders
        }
        guard !profiles.isEmpty || !kept.isEmpty || !offline.isEmpty else { return [appFolder] }
        // Folders between the app's folder and a profile or a kept file, the app's folder included.
        var onTheWay = Set<String>()
        for item in profiles.union(kept) {
            var folder = (item as NSString).deletingLastPathComponent
            while folder.count >= appFolder.path.count, onTheWay.insert(folder).inserted { folder = (folder as NSString).deletingLastPathComponent }
        }
        var offered: [String] = []
        func visit(_ folder: String) {
            let isProfile = profiles.contains(folder)
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted() {
                let item = folder + "/" + name
                if kept.contains(item) { continue }
                if profiles.contains(item) || onTheWay.contains(item) { visit(item) }
                else if !isProfile || webViewCacheParts.contains(name) && Catalog.isFolder(URL(fileURLWithPath: item)) { offered.append(item) }
            }
        }
        visit(appFolder.path)
        return offered.filter { item in !offline.contains { overlaps($0, item) } }.map { URL(fileURLWithPath: $0) }
    }

    /// Whether an "App caches" item is what the rule offers now (#203, #241): an app's whole folder, or one of the items
    /// `offeredFolders` finds in it. Anything else, such as a part whose folder no longer holds sign-in data, has changed since the scan.
    static func isOfferedItem(_ url: URL, offlineContent: [String: OfflineContent]) -> Bool {
        guard let app = appFolder(of: url) else { return false }
        let path = url.standardizedFileURL.path
        return path == app.path || offeredFolders(in: app, offlineContent: offlineContent).contains { $0.path == path }
    }

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
            CleanupRule(id: "updater-downloads", category: .updaters, title: "App update downloads",
                        detail: "Updates apps downloaded through Sparkle, Squirrel or electron-updater, per app.",
                        consequence: "Permanently removed. An update that wasn’t installed yet is downloaded again the next time the app updates. An app must be closed first.",
                        regen: .updaterDownload, action: .delete,
                        locations: ["Library/Caches/*/" + sparkleFolder, "Library/Caches/*.ShipIt", "Library/Caches/*-updater"], owner: nil,
                        itemOwner: { updaterOwner($0, apps: apps) }, protectedDepth: liveWorkDepth),
            CleanupRule(id: appCachesRuleID, category: .system, title: "App caches",
                        detail: "Files apps keep in your Library to start and work faster, per app.",
                        consequence: "Permanently removed. Each app rebuilds its cache as you use it, so it may be slower at first. An app must be closed first; CacheDrop never quits it for you.",
                        regen: .cache, action: .delete, locations: ["Library/Caches/*"], owner: nil,
                        protectedNames: signInNames + keptNames,
                        // A web-view profile's cache part belongs to the app whose folder holds it (#203).
                        itemOwner: { installedOwner((appFolder(of: $0) ?? $0).lastPathComponent, apps: apps) }, yieldsToOtherRules: true, protectedDepth: liveWorkDepth,
                        offlineContent: knownOfflineContent),
            // Crash reports first, so ~/Library/Logs/DiagnosticReports is listed once, as crash reports.
            CleanupRule(id: "crash-reports", category: .logs, title: "Crash reports",
                        detail: "Reports macOS wrote when your apps crashed or stopped responding.",
                        consequence: "Permanently removed. They can no longer be sent to a developer; macOS writes new ones if an app crashes again.",
                        regen: .log, action: .delete, locations: ["Library/Logs/DiagnosticReports"], owner: nil,
                        protectedDepth: liveWorkDepth),
            CleanupRule(id: "app-logs", category: .logs, title: "App logs",
                        detail: "Logs apps keep in your Library, per app.",
                        consequence: "Permanently removed. Apps write new logs as they run; past logs are no longer available for troubleshooting.",
                        regen: .log, action: .delete, locations: ["Library/Logs/*"], owner: nil,
                        yieldsToOtherRules: true, protectedDepth: liveWorkDepth),
        ]
    }
}

/// Finds installed apps. Injected so tests never depend on this Mac's apps.
public protocol AppLookup: Sendable {
    func app(bundleID: String) -> InstalledApp?
    /// The app whose electron-updater keeps its downloads in ~/Library/Caches/<name>, from the `updaterCacheDirName`
    /// in its `app-update.yml`.
    func app(updaterCacheDirName name: String) -> InstalledApp?
    /// The JetBrains IDEs installed on this Mac, each with the version whose cache folder it uses (#145).
    func jetBrainsIDEs() -> [JetBrainsInstall]
}

extension AppLookup {
    /// No JetBrains IDE is installed unless a lookup says so.
    public func jetBrainsIDEs() -> [JetBrainsInstall] { [] }
}

/// An installed JetBrains IDE: the product its cache folders are named after ("IntelliJIdea"), and the version of the
/// folder it uses ([2025, 2] for IntelliJIdea2025.2); nil when the app's version can't be read.
public struct JetBrainsInstall: Sendable, Hashable {
    public let product: String
    public let version: [Int]?
    public init(product: String, version: [Int]?) { self.product = product; self.version = version }
}

/// The apps LaunchServices knows on this Mac.
public struct SystemAppLookup: AppLookup {
    public init() {}
    public func app(bundleID: String) -> InstalledApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return InstalledApp(name: name, bundleID: bundleID, path: url.resolvingSymlinksInPath().path)
    }
    public func app(updaterCacheDirName name: String) -> InstalledApp? {
        for app in Self.applicationBundles() {
            let config = app.appendingPathComponent("Contents/Resources/app-update.yml")
            guard let size = try? config.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64_000,
                  let text = try? String(contentsOf: config, encoding: .utf8),
                  text.split(separator: "\n").contains(where: { Self.yamlValue($0, key: "updaterCacheDirName") == name }),
                  let bundleID = Bundle(url: app)?.bundleIdentifier else { continue }
            return self.app(bundleID: bundleID).map { InstalledApp(name: $0.name, bundleID: bundleID, path: app.resolvingSymlinksInPath().path) }
                ?? InstalledApp(name: app.deletingPathExtension().lastPathComponent, bundleID: bundleID, path: app.resolvingSymlinksInPath().path)
        }
        return nil
    }
    /// Apps at the top of each Applications folder, or one folder down (a vendor's folder).
    static func applicationBundles() -> [URL] {
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"].map { URL(fileURLWithPath: $0) }
        let manager = FileManager.default
        return roots.flatMap { root in
            ((try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).flatMap { item in
                item.pathExtension == "app" ? [item] : ((try? manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
            }
        }
    }
    /// JetBrains IDEs in the Applications folders (where Toolbox installs them too) and every copy LaunchServices knows.
    public func jetBrainsIDEs() -> [JetBrainsInstall] {
        let registered = AppDataCaches.jetBrainsBundleIDs.keys.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
        let bundles = Set((Self.applicationBundles() + registered).map { $0.resolvingSymlinksInPath().standardizedFileURL })
        return bundles.compactMap(Self.jetBrainsInstall)
    }
    /// The IDE in an app bundle. Its folder name is `dataDirectoryName` in Contents/Resources/product-info.json, which
    /// the IDE itself uses for its cache folder; without that file, the product comes from the bundle identifier and the
    /// version from `CFBundleShortVersionString` ("2025.2.1" uses 2025.2). Nil for an app that isn't a JetBrains IDE.
    static func jetBrainsInstall(_ app: URL) -> JetBrainsInstall? {
        let info = app.appendingPathComponent("Contents/Resources/product-info.json")
        if let size = try? info.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 1_000_000,
           let json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: info))) as? [String: Any],
           let folder = json["dataDirectoryName"] as? String, let (product, version) = AppDataCaches.jetBrainsVersion(folder),
           AppDataCaches.jetBrainsProducts[product] != nil {
            return JetBrainsInstall(product: product, version: version)
        }
        guard let bundle = Bundle(url: app), let id = bundle.bundleIdentifier, let product = AppDataCaches.jetBrainsProduct(bundleID: id) else { return nil }
        return JetBrainsInstall(product: product, version: (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppDataCaches.jetBrainsReleaseVersion))
    }
    /// `key: value` on one line, with optional quotes.
    static func yamlValue(_ line: Substring, key: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key + ":") else { return nil }
        return trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

/// An installed app, as LaunchServices reports it.
public struct InstalledApp: Sendable, Hashable {
    public let name: String
    public let bundleID: String
    /// The app bundle's path; a process run from inside it counts as the app.
    public let path: String
    public init(name: String, bundleID: String, path: String) { self.name = name; self.bundleID = bundleID; self.path = path }
}

/// Content an app keeps offline in its cache folder (#171): any of `names` anywhere inside the folder keeps it (#203), and `label` says why.
public struct OfflineContent: Sendable, Hashable {
    public let names: Set<String>
    public let label: String
    public init(names: Set<String>, label: String) { self.names = names; self.label = label }
}

extension CleanupRule {
    /// What offline content an app keeps in the app folder `folder` is or is inside, if any (`offlineContent`, keyed in lowercase
    /// as LaunchServices matches bundle identifiers), found anywhere in the app's folder: `folder` is refused when it holds that
    /// content or sits in a folder holding it (#241). An app folder that can't be fully searched counts as holding it.
    /// Nil for rules with none and for every other app.
    func offlineContentLabel(in folder: URL) -> String? {
        guard !offlineContent.isEmpty else { return nil }
        let app = AppCaches.appFolder(of: folder) ?? folder
        guard let content = offlineContent[app.lastPathComponent.lowercased()] else { return nil }
        // An item is the offline content's when it holds it or sits in a folder holding it (#241).
        guard let holders = AppCaches.folders(holding: content.names, in: app, depth: .max) else { return content.label }
        let item = folder.standardizedFileURL.path
        return holders.contains { AppCaches.overlaps($0, item) } ? content.label : nil
    }
}
