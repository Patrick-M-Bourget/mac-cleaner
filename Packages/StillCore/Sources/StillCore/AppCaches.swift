import AppKit
import Foundation

/// Updater downloads, per-app caches and the user's logs (#103).
public enum AppCaches {
    /// Still's own folders are never offered, whatever their name.
    static let stillNames = ["Still", "com.patrickbourget.Still", "com.patrickbourget.StillUITests"]

    /// Levels searched for a git checkout or other protected name inside a cache or log folder. A path under Caches
    /// doesn't prove a folder is disposable: the field scan found an agent's live checkout two levels down.
    static let liveWorkDepth = 4

    /// A folder name that is an app's bundle identifier: reverse-DNS with at least three parts.
    static func isBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { part in !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
            && parts[0].first?.isLetter == true
    }
    /// macOS's own caches and Still's are never offered, whoever asks.
    static func isExcluded(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id.hasPrefix("com.apple.") || id.hasPrefix("com.patrickbourget.still")
    }
    /// A folder of macOS's own or of Still's, by bundle identifier or name. Never offered under any rule,
    /// so logs and every other location leave them alone as app caches do.
    static func isMacOSOrStill(_ name: String) -> Bool { isExcluded(name) || stillNames.contains(name) }
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

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
            CleanupRule(id: "updater-downloads", category: .updaters, title: "App update downloads",
                        detail: "Updates apps downloaded through Sparkle, Squirrel or electron-updater, per app.",
                        consequence: "Permanently removed. An update that wasn’t installed yet is downloaded again the next time the app updates. An app must be closed first.",
                        regen: .updaterDownload, action: .delete,
                        locations: ["Library/Caches/*/" + sparkleFolder, "Library/Caches/*.ShipIt", "Library/Caches/*-updater"], owner: nil,
                        protectedNames: stillNames, itemOwner: { updaterOwner($0, apps: apps) }, protectedDepth: liveWorkDepth),
            CleanupRule(id: "app-caches", category: .system, title: "App caches",
                        detail: "Files apps keep in your Library to start and work faster, per app.",
                        consequence: "Permanently removed. Each app rebuilds its cache as you use it, so it may be slower at first. An app must be closed first; Still never quits it for you.",
                        regen: .cache, action: .delete, locations: ["Library/Caches/*"], owner: nil,
                        protectedNames: stillNames, itemOwner: { installedOwner($0.lastPathComponent, apps: apps) }, yieldsToOtherRules: true, protectedDepth: liveWorkDepth),
            // Crash reports first, so ~/Library/Logs/DiagnosticReports is listed once, as crash reports.
            CleanupRule(id: "crash-reports", category: .logs, title: "Crash reports",
                        detail: "Reports macOS wrote when your apps crashed or stopped responding.",
                        consequence: "Permanently removed. They can no longer be sent to a developer; macOS writes new ones if an app crashes again.",
                        regen: .log, action: .delete, locations: ["Library/Logs/DiagnosticReports"], owner: nil,
                        protectedNames: stillNames, protectedDepth: liveWorkDepth),
            CleanupRule(id: "app-logs", category: .logs, title: "App logs",
                        detail: "Logs apps keep in your Library, per app.",
                        consequence: "Permanently removed. Apps write new logs as they run; past logs are no longer available for troubleshooting.",
                        regen: .log, action: .delete, locations: ["Library/Logs/*"], owner: nil,
                        protectedNames: stillNames, yieldsToOtherRules: true, protectedDepth: liveWorkDepth),
        ]
    }
}

/// Finds installed apps. Injected so tests never depend on this Mac's apps.
public protocol AppLookup: Sendable {
    func app(bundleID: String) -> InstalledApp?
    /// The app whose electron-updater keeps its downloads in ~/Library/Caches/<name>, from the `updaterCacheDirName`
    /// in its `app-update.yml`.
    func app(updaterCacheDirName name: String) -> InstalledApp?
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
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"].map { URL(fileURLWithPath: $0) }
        let manager = FileManager.default
        // Apps at the top of each Applications folder, or one folder down (a vendor's folder).
        let apps = roots.flatMap { root in
            ((try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).flatMap { item in
                item.pathExtension == "app" ? [item] : ((try? manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
            }
        }
        for app in apps {
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
