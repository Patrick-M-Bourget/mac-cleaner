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
    /// Spotlight is queried once, when first needed; Launch Services still answers each bundle ID as it is asked.
    public func snapshot() -> any AppPresence { FixedAppPresence(reading: installedApps, registered: isRegistered) }

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
    public static func bundles(in folder: URL) -> [URL] {
        let manager = FileManager.default
        return ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).flatMap { item in
            item.pathExtension == "app" ? [item] : ((try? manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
        }
    }
    public static func app(_ bundle: URL) -> InstalledApp? {
        guard let id = Bundle(url: bundle)?.bundleIdentifier else { return nil }
        return InstalledApp(name: bundle.deletingPathExtension().lastPathComponent, bundleID: id, path: bundle.path)
    }
}

/// One reading of the installed apps, taken on first use so a run with no leftovers never queries Spotlight (#265), with
/// Launch Services still asked per bundle ID.
struct FixedAppPresence: AppPresence {
    private final class Reading: @unchecked Sendable {
        private let lock = NSLock()
        private let read: @Sendable () -> [InstalledApp]?
        private var apps: [InstalledApp]??
        init(_ read: @escaping @Sendable () -> [InstalledApp]?) { self.read = read }
        func value() -> [InstalledApp]? {
            lock.lock(); defer { lock.unlock() }
            if let apps { return apps }
            let found = read()
            apps = .some(found)
            return found
        }
    }
    private let reading: Reading
    let registered: @Sendable (String) -> Bool
    init(reading: @escaping @Sendable () -> [InstalledApp]?, registered: @escaping @Sendable (String) -> Bool) {
        self.reading = Reading(reading); self.registered = registered
    }
    init(apps: [InstalledApp]?, registered: @escaping @Sendable (String) -> Bool) { self.init(reading: { apps }, registered: registered) }
    func installedApps() -> [InstalledApp]? { reading.value() }
    func isRegistered(bundleID: String) -> Bool { registered(bundleID) }
}
