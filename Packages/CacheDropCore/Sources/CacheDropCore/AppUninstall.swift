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
    /// Every uninstall rule's ID, an app's and a plug-in product's (#176): their items are chosen on the Applications page.
    public static let ruleIDs: Set<String> = Set((rules + PlugInUninstall.rules).map(\.id))

    /// The app an item is uninstalled with.
    public struct Target: Sendable, Hashable {
        public let name: String
        public let bundleID: String
        /// The app bundle's standardized path: the Applications page's row id.
        public let path: String
        /// Its login items, helpers and XPC services' bundle IDs (#281).
        public var helpers: [String] = []
        /// Its files that stay whatever is ticked: those that need a password, and those the Cleanup plan already offers (#281).
        public var needsPassword = 0
        public var inPlan = 0
        /// A plug-in product's AUv3 formats, which go with the app they are in (#176).
        public var insideApp = 0
        /// More folders any process run from inside of counts as it running: a plug-in product's formats and standalone app (#176).
        public var otherPaths: [String] = []
        /// Apps that must be closed too: plug-in hosts (#176, Decision 51).
        public var hosts: [RuleOwner] = []
        /// The vendor's tool, for "Needs <tool> or your password" (Decision 50).
        public var tool: String? = nil
        /// The app must be closed first (Decision 29): its bundle ID, its helpers' and any process run from inside it (#281).
        public var owner: RuleOwner { RuleOwner(name: name, bundleIDs: ([bundleID] + helpers).filter { !$0.isEmpty }, paths: [path] + otherPaths) }
    }

    /// The bundle IDs of what an app runs besides itself: `Contents/Library/LoginItems`, `Contents/Helpers`, `Contents/XPCServices`.
    static func helperIDs(of app: URL) -> [String] {
        ["Contents/Library/LoginItems", "Contents/Helpers", "Contents/XPCServices"].flatMap { place -> [String] in
            let folder = app.appendingPathComponent(place)
            return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().compactMap { name in
                PlugInInventory.info(folder.appendingPathComponent(name))?["CFBundleIdentifier"] as? String
            }
        }
    }

    /// The app and its files, ready to tick; nothing when the app isn't offered or needs a password to remove (Decision 50).
    /// `leftovers` are what the scan already finds with the app installed: they belong to removed apps, not to this one.
    /// What the Cleanup plan `offered` stays there, so no space is offered twice.
    /// Its own `uninstaller` (`ApplicationsInventory.withUninstallers`) goes with it, in its App group (#285).
    public static func scan(_ app: InstalledApp, uninstaller: InstalledApp? = nil, excluding ownBundleID: String?, home: URL, apps: any AppPresence, receipts: any InstallerReceiptReading,
                            leftovers: [Candidate], offered: [Candidate] = [], exclusions: ExclusionPolicy = ExclusionPolicy(),
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let url = URL(fileURLWithPath: app.path).standardizedFileURL
        var info = stat()
        guard ApplicationsInventory.isListed(app, excluding: ownBundleID), Removability.canMoveToTrash(url), lstat(url.path, &info) == 0,
              // An excluded app is never offered, nor its files (SPEC section 2).
              let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(url, volumeID: volume) else { return [] }
        let catalog = Catalog(rules: rules), size = sizer.size(url)
        var bundle = catalog.candidate(rules[0], url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
        bundle = bundle.found(under: url.deletingLastPathComponent())
        let skipped = Set(leftovers.map(\.url.path))
        let found = RemovedAppLeftovers.scan(home: home, apps: Without(app: app, url: url, in: apps), receipts: receipts, exclusions: exclusions,
                                             sizer: sizer, skipping: skipped)
        let notInPlan = RemovedAppLeftovers.notOffered(by: offered, found), removable = notInPlan.filter { Removability.canMoveToTrash($0.url) }
        let target = Target(name: app.name, bundleID: app.bundleID, path: url.path, helpers: helperIDs(of: url),
                            needsPassword: notInPlan.count - removable.count, inPlan: found.count - notInPlan.count)
        let files = removable.map { $0.uninstalled(with: target, ruleID: $0.ruleID == RemovedAppLeftovers.ruleID ? filesRuleID : possiblyRelatedRuleID) }
        bundle.uninstall = target
        // Its own uninstaller, when macOS lets the user move it to the Trash and it isn't excluded.
        var tool = uninstaller.map { URL(fileURLWithPath: $0.path).standardizedFileURL }.flatMap { tool -> Candidate? in
            var info = stat()
            guard Removability.canMoveToTrash(tool), lstat(tool.path, &info) == 0,
                  let volume = try? tool.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(tool, volumeID: volume) else { return nil }
            let size = sizer.size(tool)
            return catalog.candidate(rules[0], tool, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
                .found(under: tool.deletingLastPathComponent())
        }
        tool?.uninstall = target
        return [bundle] + (tool.map { [$0] } ?? []) + files
    }

    /// The check just before acting: never macOS's, CacheDrop's or license data, and only what macOS still lets the user move to
    /// the Trash without a password, whatever changed since the scan (Decision 50).
    /// An app's files keep the before-acting checks of a removed app's leftovers (#281), as if the app were gone: the tie still
    /// holds, a group container is still an exact match, and no other app of the maker, or second copy of this one, appeared.
    static func refusal(for candidate: Candidate, below root: URL, apps: any AppPresence) -> CheckRefusal? {
        let url = candidate.url
        guard let app = candidate.uninstall else { return .changed }
        if PlugInUninstall.rules.contains(where: { $0.id == candidate.ruleID }) { return PlugInUninstall.refusal(for: candidate) }
        if candidate.ruleID != appRuleID {
            guard let tie = candidate.leftover else { return .changed }
            let gone = Without(app: InstalledApp(name: app.name, bundleID: app.bundleID, path: app.path), url: URL(fileURLWithPath: app.path), in: apps)
            // The app's own container goes in the same run, so its bundle ID stands as the proof it was an app's.
            let own = tie.bundleID?.lowercased() == app.bundleID.lowercased()
            if let refusal = RemovedAppLeftovers.refusal(for: url, tie: tie, below: root, apps: gone, appKnown: own) { return refusal }
        }
        if let part = url.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count).first(where: RemovedAppLeftovers.isNeverOffered) {
            return .protected(part)
        }
        return Removability.canMoveToTrash(url) ? nil : .notPermitted
    }

    /// One line of the review's "what stays and why" (Decision 51: "<N> parts stay"), one per app and reason.
    public struct Staying: Sendable, Equatable, Identifiable {
        public let id: String
        public let text: String
    }
    /// For each app being uninstalled: its items left unticked, those that need a password, and those the plan offers.
    public static func staying(chosen: [Candidate], offered: [Candidate]) -> [Staying] {
        let ids = Set(chosen.map(\.id))
        var apps: [Target] = []
        for item in chosen { if let app = item.uninstall, !apps.contains(app) { apps.append(app) } }
        return apps.flatMap { app in
            let unticked = offered.filter { $0.isUninstalled(with: app.path) && !ids.contains($0.id) }.count
            let password: String = app.tool.map { "Needs \($0) or your password" } ?? "Needs your password"
            let reasons: [(String, Int, String)] = [("unticked", unticked, "Not ticked"), ("password", app.needsPassword, password),
                                                    ("inside", app.insideApp, "Goes with the app it is in"), ("plan", app.inPlan, "In the Cleanup plan")]
            return reasons
                .filter { $0.1 > 0 }
                .map { Staying(id: app.path + "-" + $0.0, text: "\(app.name): " + ($0.1 == 1 ? "1 part stays" : "\($0.1) parts stay") + " · " + $0.2) }
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
    /// A removed app's leftover found with the app hidden, as one of the app's own files to uninstall with it. A copy, so every
    /// field carries over, a new one included.
    func uninstalled(with app: AppUninstall.Target, ruleID: String) -> Candidate {
        var item = self
        item.ruleID = ruleID; item.appName = app.name; item.uninstall = app
        // The app is installed, so a possibly related item says only what ties it: "Named like Synth", never "no longer installed" (#285).
        if let tie = leftover, let reason = tie.reason {
            let tied = reason.components(separatedBy: " (")[0].components(separatedBy: ", ")[0]
            item.leftover = LeftoverTie(app: tie.app, bundleID: tie.bundleID, vendor: tie.vendor, evidence: .nameOnly(tied))
        }
        return item
    }
}

/// Installer receipts read once, for scanning many apps together.
public struct ReadReceipts: InstallerReceiptReading {
    let all: [InstallerReceipt]
    public init(_ all: [InstallerReceipt]) { self.all = all }
    public func receipts() -> [InstallerReceipt] { all }
}
