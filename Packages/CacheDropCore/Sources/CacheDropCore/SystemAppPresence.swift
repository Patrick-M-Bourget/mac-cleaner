import AppKit
import CoreServices
import Foundation

/// The apps on this Mac (#173): every application bundle Spotlight indexes on any mounted volume, plus the bundles at the top
/// of (or one folder down in) each volume's Applications folders, for volumes Spotlight doesn't index. Launch Services is asked
/// about each bundle ID too. When Spotlight's query can't run, the list is unknown and nothing is offered. Plug-ins and other
/// installed bundles (`InstalledBundles`, #251) count too, so a plug-in's maker is never taken for a removed app.
public struct SystemAppPresence: AppPresence {
    public init() {}
    public func isRegistered(bundleID: String) -> Bool { !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).isEmpty }
    public func installedApps() -> [InstalledApp]? {
        guard let indexed = Self.spotlightApps() else { return nil }
        return indexed + Self.applicationFolders().flatMap(Self.bundles).compactMap(Self.app)
            + InstalledBundles.scan(home: URL(fileURLWithPath: NSHomeDirectory()))
    }
    /// Spotlight is queried once; Launch Services still answers each bundle ID as it is asked.
    public func snapshot() -> any AppPresence { FixedAppPresence(apps: installedApps(), registered: isRegistered) }

    static func spotlightApps() -> [InstalledApp]? {
        guard let query = MDQueryCreate(kCFAllocatorDefault, "kMDItemContentType == 'com.apple.application-bundle'" as CFString, nil, nil) else { return nil }
        MDQuerySetSearchScope(query, [kMDQueryScopeComputer] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return nil }
        defer { MDQueryStop(query) }
        return (0..<MDQueryGetResultCount(query)).compactMap { index -> InstalledApp? in
            guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let id = MDItemCopyAttribute(item, kMDItemCFBundleIdentifier) as? String, let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { return nil }
            let name = (MDItemCopyAttribute(item, kMDItemDisplayName) as? String).map { ($0 as NSString).deletingPathExtension } ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return InstalledApp(name: name, bundleID: id, path: path)
        }
    }
    /// `/Applications`, `~/Applications` and each other volume's `Applications`.
    static func applicationFolders() -> [URL] {
        let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        return (["/Applications", NSHomeDirectory() + "/Applications"] + volumes.map { "/Volumes/\($0)/Applications" }).map { URL(fileURLWithPath: $0) }
    }
    static func bundles(in folder: URL) -> [URL] {
        let manager = FileManager.default
        return ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).flatMap { item in
            item.pathExtension == "app" ? [item] : ((try? manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
        }
    }
    static func app(_ bundle: URL) -> InstalledApp? {
        guard let id = Bundle(url: bundle)?.bundleIdentifier else { return nil }
        return InstalledApp(name: bundle.deletingPathExtension().lastPathComponent, bundleID: id, path: bundle.path)
    }
}

/// One reading of the installed apps, with Launch Services still asked per bundle ID.
struct FixedAppPresence: AppPresence {
    let apps: [InstalledApp]?
    let registered: @Sendable (String) -> Bool
    func installedApps() -> [InstalledApp]? { apps }
    func isRegistered(bundleID: String) -> Bool { registered(bundleID) }
}

/// The installer receipts in `/var/db/receipts` (what `pkgutil` reads), except Apple's, each listed with `lsbom`: the app
/// bundles it installed and what it put in the user's Library. A receipt that can't be read is skipped.
public struct SystemInstallerReceipts: InstallerReceiptReading {
    let home: URL
    public init(home: URL) { self.home = home.resolvingSymlinksInPath() }
    public func receipts() -> [InstallerReceipt] {
        let folder = URL(fileURLWithPath: "/var/db/receipts"), lsbom = URL(fileURLWithPath: "/usr/bin/lsbom"), library = home.path + "/Library/"
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().compactMap { name -> InstallerReceipt? in
            guard name.hasSuffix(".plist"), !name.hasPrefix("com.apple."), let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = info["PackageIdentifier"] as? String, let prefix = info["InstallPrefixPath"] as? String,
                  let listing = try? BoundedTool.run(executable: lsbom, arguments: ["-s", folder.appendingPathComponent(String(name.dropLast(6)) + ".bom").path],
                                                     timeout: 5, outputLimit: 8 << 20) else { return nil }
            let base = URL(fileURLWithPath: "/" + prefix.drop { $0 == "/" })
            var apps = Set<String>(), paths = Set<String>()
            for line in listing.split(separator: "\n") {
                let relative = line.hasPrefix("./") ? String(line.dropFirst(2)) : String(line)
                let path = base.appendingPathComponent(relative).standardizedFileURL.path
                if let app = path.range(of: ".app/").map({ String(path[..<$0.lowerBound]) + ".app" }) ?? (path.hasSuffix(".app") ? path : nil) { apps.insert(app) }
                if path.hasPrefix(library) { paths.insert(path) }
            }
            return InstallerReceipt(id: id, apps: apps.sorted(), paths: paths)
        }
    }
}
