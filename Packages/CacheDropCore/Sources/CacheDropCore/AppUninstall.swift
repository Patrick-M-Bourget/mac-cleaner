import Foundation
import Darwin

/// Uninstalling an installed app with its files (#177, Decisions 41, 50, 51): the app bundle plus what `RemovedAppLeftovers`
/// would find once the app is gone, by the same matching (bundle ID or installer receipt; name-only = possibly related,
/// ticked one by one). Only what macOS lets the user move to the Trash without a password is offered, checked at the scan
/// and again before acting (`CandidateCheck`). Everything goes to the Trash, so Put back works.
public enum AppUninstall {
    public static let appRuleID = "uninstall-app"
    public static let filesRuleID = "uninstall-app-files"
    public static let possiblyRelatedRuleID = "uninstall-app-possibly-related"
    static let consequence = "Moved to Trash. You can put them back from History, or restore them from the Trash in Finder."
    public static let rules: [CleanupRule] = [
        CleanupRule(id: appRuleID, category: .apps, title: "App", detail: "The app itself.", consequence: consequence, regen: .userFile, action: .trash,
                    locations: [], owner: nil, unprotectedExtensions: ["app"]),
        CleanupRule(id: filesRuleID, category: .apps, title: "Its files",
                    detail: "Settings, caches and data tied to the app by its bundle ID or installer receipt.",
                    consequence: consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth),
        CleanupRule(id: possiblyRelatedRuleID, category: .apps, title: "Possibly related",
                    detail: "Folders named like the app or its maker. Nothing ties them to it for sure, so check each one.",
                    consequence: consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth,
                    itemByItem: true),
    ]
    public static let ruleIDs: Set<String> = Set(rules.map(\.id))

    /// The app an item is uninstalled with.
    public struct Target: Sendable, Hashable {
        public let name: String
        public let bundleID: String
        /// The app bundle's standardized path: the Applications page's row id.
        public let path: String
        /// The app must be closed first (Decision 29), by its bundle ID.
        public var owner: RuleOwner { RuleOwner(name: name, bundleIDs: [bundleID]) }
    }

    /// The app and its files, ready to tick; nothing when the app isn't offered or needs a password to remove (Decision 50).
    /// `leftovers` are what the scan already finds with the app installed: they belong to removed apps, not to this one.
    public static func scan(_ app: InstalledApp, excluding ownBundleID: String?, home: URL, apps: any AppPresence, receipts: any InstallerReceiptReading,
                            leftovers: [Candidate], exclusions: ExclusionPolicy = ExclusionPolicy(), sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let url = URL(fileURLWithPath: app.path).standardizedFileURL
        var info = stat()
        guard ApplicationsInventory.isListed(app, excluding: ownBundleID), Removability.canMoveToTrash(url), lstat(url.path, &info) == 0,
              // An excluded app is never offered, nor its files (SPEC section 2).
              let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(url, volumeID: volume) else { return [] }
        let target = Target(name: app.name, bundleID: app.bundleID, path: url.path)
        let catalog = Catalog(rules: rules), size = sizer.size(url)
        var bundle = catalog.candidate(rules[0], url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
        bundle = bundle.found(under: url.deletingLastPathComponent())
        let skipped = Set(leftovers.map(\.url.path))
        let files = RemovedAppLeftovers.scan(home: home, apps: Without(app: app, url: url, in: apps), receipts: receipts, exclusions: exclusions,
                                             sizer: sizer, skipping: skipped)
            .filter { Removability.canMoveToTrash($0.url) }
            .map { $0.uninstalled(with: target, ruleID: $0.ruleID == RemovedAppLeftovers.ruleID ? filesRuleID : possiblyRelatedRuleID) }
        bundle.uninstall = target
        return [bundle] + files
    }

    /// The check just before acting: never macOS's, CacheDrop's or license data, and only what macOS still lets the user move to
    /// the Trash without a password, whatever changed since the scan (Decision 50).
    static func refusal(for url: URL, below root: URL) -> CheckRefusal? {
        if let part = url.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count).first(where: RemovedAppLeftovers.isNeverOffered) {
            return .protected(part)
        }
        return Removability.canMoveToTrash(url) ? nil : .notPermitted
    }

    /// The review's "what stays and why": for each app being uninstalled, its offered items left unticked.
    public static func staying(chosen: [Candidate], offered: [Candidate]) -> [String] {
        let ids = Set(chosen.map(\.id))
        var apps: [Target] = []
        for item in chosen { if let app = item.uninstall, !apps.contains(app) { apps.append(app) } }
        return apps.compactMap { app in
            let left = offered.filter { $0.uninstall == app && !ids.contains($0.id) }
            guard !left.isEmpty else { return nil }
            let related = left.filter { $0.ruleID == possiblyRelatedRuleID }.count
            let what = left.count == 1 ? "1 item" : "\(left.count) items"
            return "\(what) of \(app.name) stay because you didn’t tick them" + (related > 0 ? " (\(related) possibly related)." : ".")
        }
    }

    /// Items grouped by the folder they are in, in first-seen order, for the review (#177: grouped by place).
    public static func byPlace(_ items: [Candidate]) -> [(place: URL, items: [Candidate])] {
        var groups: [(place: URL, items: [Candidate])] = []
        for item in items {
            let place = item.url.deletingLastPathComponent()
            if let index = groups.firstIndex(where: { $0.place == place }) { groups[index].items.append(item) } else { groups.append((place, [item])) }
        }
        return groups
    }

    /// The installed apps as they would be with `app` gone: this copy is hidden; another copy of it still counts.
    struct Without: AppPresence {
        let app: InstalledApp
        let url: URL
        let base: any AppPresence
        init(app: InstalledApp, url: URL, in base: any AppPresence) { self.app = app; self.url = url; self.base = base }
        func installedApps() -> [InstalledApp]? {
            base.installedApps()?.filter { URL(fileURLWithPath: $0.path).standardizedFileURL.path != url.path }
        }
        func isRegistered(bundleID: String) -> Bool {
            guard bundleID.lowercased() == app.bundleID.lowercased() else { return base.isRegistered(bundleID: bundleID) }
            return installedApps()?.contains { $0.bundleID.lowercased() == bundleID.lowercased() } ?? true
        }
    }
}

extension Candidate {
    /// A removed app's leftover found with the app hidden, as one of the app's own files to uninstall with it.
    func uninstalled(with app: AppUninstall.Target, ruleID: String) -> Candidate {
        var item = Candidate(ruleID: ruleID, action: action, url: url, resourceID: resourceID, isDirectory: isDirectory, toolURL: nil, volumeID: volumeID,
                             modifiedSeconds: modifiedSeconds, modifiedNanoseconds: modifiedNanoseconds, logicalBytes: logicalBytes, allocatedBytes: allocatedBytes,
                             sizeComplete: sizeComplete, lastUsed: lastUsed, observedAt: observedAt, profile: nil)
        item.appName = app.name; item.leftover = leftover; item.scopeRoot = scopeRoot; item.uninstall = app
        return item
    }
}

/// Installer receipts read once, for scanning many apps together.
public struct ReadReceipts: InstallerReceiptReading {
    let all: [InstallerReceipt]
    public init(_ all: [InstallerReceipt]) { self.all = all }
    public func receipts() -> [InstallerReceipt] { all }
}
