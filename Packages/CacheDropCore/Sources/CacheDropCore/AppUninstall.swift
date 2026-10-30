import Foundation
import Darwin

/// Uninstalling an installed app with its files (#177, Decisions 41, 50, 51): the app bundle plus what `RemovedAppLeftovers`
/// would find once the app is gone, by the same matching (bundle ID or installer receipt; name-only = possibly related,
/// ticked one by one). Only what macOS lets the user move to the Trash without a password is offered, checked at the scan
/// and again before acting (`CandidateCheck`). Everything goes to the Trash, so Put back works.
public enum AppUninstall {
    static let appRuleID = "uninstall-app"
    static let filesRuleID = "uninstall-app-files"
    static let possiblyRelatedRuleID = "uninstall-app-possibly-related"
    static let consequence = ""
    static let appRule = CleanupRule(id: appRuleID, category: .apps, title: "App", detail: "The app itself.", consequence: consequence, regen: .userFile,
        action: .trash, locations: [], owner: nil, unprotectedExtensions: ["app"], family: .appUninstall)
    static let filesRule = CleanupRule(id: filesRuleID, category: .apps, title: "Its files",
        detail: "Settings, caches and data tied to the app by its bundle ID or installer receipt.",
        consequence: consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth, family: .appUninstall)
    static let possiblyRelatedRule = CleanupRule(id: possiblyRelatedRuleID, category: .apps, title: "Possibly related",
        detail: "Folders named like the app or its maker. Nothing ties them to it for sure, so check each one.",
        consequence: consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth,
        itemByItem: true, family: .appUninstall)
    public static let rules: [CleanupRule] = [appRule, filesRule, possiblyRelatedRule]

    /// The app or plug-in product an item is uninstalled with.
    public struct Target: Sendable, Hashable {
        public let name: String
        public let bundleID: String
        /// The Applications page's row id: the app bundle's standardized path, or a plug-in product's ID.
        public let path: String
        /// Its login items, helpers and XPC services' bundle IDs (#281).
        public var helpers: [String] = []
        /// Its files that stay whatever is ticked: those that need a password, and those the Cleanup plan already offers (#281).
        public var needsPassword = 0
        public var inPlan = 0
        /// The rules that already offer its files in the Cleanup plan, for "Clean in the Cleanup plan" (#354).
        public var inPlanRuleIDs: [String] = []
        /// What only a plug-in product has (#176); nil for an app.
        public var plugIn: PlugIn? = nil
        /// The vendor's tool, for "Needs <tool> or your password" (Decision 50).
        public var tool: String? { plugIn?.tool }
        /// Its files that need a password: a plug-in product's row lists them as staying (#288), the review reveals them (#354).
        public var passwordPaths: [String] = []
        /// A plug-in product's support files weren't offered: an installer record couldn't be read (#291).
        public var receiptsUnread = false
        /// A plug-in product's files that stay because CacheDrop doesn't recognize their kind (#291, Decision 53).
        public var unrecognised = 0
        /// The app must be closed first (Decision 29): its bundle ID, its helpers' and any process run from inside it (#281).
        public var owner: RuleOwner { RuleOwner(name: name, bundleIDs: ([bundleID] + helpers).filter { !$0.isEmpty }, paths: [path] + (plugIn?.otherPaths ?? [])) }

        /// A plug-in product's own parts of its target (#176).
        public struct PlugIn: Sendable, Hashable {
            /// Its AUv3 formats, which go with the app they are in.
            public var insideApp = 0
            /// More folders any process run from inside of counts as it running: its formats and standalone app.
            public var otherPaths: [String] = []
            /// Apps that must be closed too: plug-in hosts (Decision 51).
            public var hosts: [RuleOwner] = []
            /// The vendor's tool (Decision 50).
            public var tool: String? = nil
        }
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
                            leftovers: [Candidate], offered: [Candidate] = [], exclusions: ProtectedItemsPolicy = ProtectedItemsPolicy(),
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let url = URL(fileURLWithPath: app.path).standardizedFileURL
        var info = stat()
        guard ApplicationsInventory.isListed(app, excluding: ownBundleID, home: home), Removability.canMoveToTrash(url), lstat(url.path, &info) == 0,
              // An excluded app is never offered, nor its files (SPEC section 2).
              let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(url, volumeID: volume) else { return [] }
        let catalog = Catalog(rules: rules), size = sizer.size(url)
        var bundle = catalog.candidate(appRule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
        bundle = bundle.found(under: url.deletingLastPathComponent())
        let skipped = Set(leftovers.map(\.url.path))
        // The app being uninstalled proves its own and its helpers' bundle IDs were an app's (#301): files named for them are its
        // files, without the container or saved state a removed app's would need (#251).
        let helpers = helperIDs(of: url), ownIDs = Set(([app.bundleID] + helpers).map { $0.lowercased() })
        let gone = Without(app: app, url: url, in: apps, own: ownIDs)
        let found = RemovedAppLeftovers.scan(home: home, apps: gone, receipts: receipts, exclusions: exclusions, sizer: sizer, skipping: skipped)
            .map { confirmingOwn($0, ids: ownIDs) }
            .filter { item in item.leftover.map { gone.isOwn(item.url, tie: $0) } ?? false }
        let notInPlan = RemovedAppLeftovers.notOffered(by: offered, found), removable = notInPlan.filter { Removability.canMoveToTrash($0.url) }
        var target = Target(name: app.name, bundleID: app.bundleID, path: url.path, helpers: helpers,
                            needsPassword: notInPlan.count - removable.count, inPlan: found.count - notInPlan.count)
        target.passwordPaths = notInPlan.filter { !Removability.canMoveToTrash($0.url) }.map(\.url.path)
        target.inPlanRuleIDs = planRuleIDs(offering: found, among: offered)
        let files = removable.map { $0.uninstalled(with: target, ruleID: $0.ruleID == RemovedAppLeftovers.ruleID ? filesRuleID : possiblyRelatedRuleID) }
        bundle.uninstall = target
        // Its own uninstaller, when macOS lets the user move it to the Trash and it isn't excluded.
        var tool = uninstaller.map { URL(fileURLWithPath: $0.path).standardizedFileURL }.flatMap { tool -> Candidate? in
            var info = stat()
            guard Removability.canMoveToTrash(tool), lstat(tool.path, &info) == 0,
                  let volume = try? tool.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(tool, volumeID: volume) else { return nil }
            let size = sizer.size(tool)
            return catalog.candidate(appRule, tool, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
                .found(under: tool.deletingLastPathComponent())
        }
        tool?.uninstall = target
        return [bundle] + (tool.map { [$0] } ?? []) + files
    }

    /// A possibly related item named for one of `ids` (lowercased), the app's own or its helpers', as one of its files (#301).
    /// A group container stays an exact match on the evidence rule: the maker's apps share it.
    static func confirmingOwn(_ item: Candidate, ids: Set<String>) -> Candidate {
        guard let tie = item.leftover, tie.isNameOnly, !RemovedAppLeftovers.isGroupContainer(item.url),
              let id = RemovedAppLeftovers.bundleID(inName: item.url.lastPathComponent), ids.contains(id.lowercased()) else { return item }
        var confirmed = item
        confirmed.ruleID = RemovedAppLeftovers.ruleID
        confirmed.leftover = LeftoverTie(app: tie.app, bundleID: id, vendor: tie.vendor, evidence: .bundleID)
        return confirmed
    }

    /// The check just before acting: never macOS's, CacheDrop's or license data, and only what macOS still lets the user move to
    /// the Trash without a password, whatever changed since the scan (Decision 50).
    /// An app's files keep the before-acting checks of a removed app's leftovers (#281), as if the app were gone: the tie still
    /// holds, a group container is still an exact match, and no second copy of it appeared. Only what is still its own by
    /// `Without.isOwn` passes, so another app of its maker appearing keeps only what may be that app's (#305).
    static func refusal(for candidate: Candidate, rule: CleanupRule, below root: URL, apps: any AppPresence, receipts: LazyReceipts) -> CheckRefusal? {
        let url = candidate.url
        guard let app = candidate.uninstall else { return .changed }
        if rule.family == .plugInUninstall { return PlugInUninstall.refusal(for: candidate, receipts: receipts) }
        if rule.id != appRule.id {
            guard let tie = candidate.leftover else { return .changed }
            let ids = Set(([app.bundleID] + app.helpers).map { $0.lowercased() })
            let gone = Without(app: InstalledApp(name: app.name, bundleID: app.bundleID, path: app.path), url: URL(fileURLWithPath: app.path), in: apps, own: ids)
            // Only what is still the app's own, whatever a stale scan tied it to (#305).
            guard gone.isOwn(url, tie: tie) else { return .changed }
            // The app goes in the same run, so its own and its helpers' bundle IDs stand as the proof they were an app's (#301).
            let own = tie.bundleID.map { ids.contains($0.lowercased()) } ?? false
            if let refusal = RemovedAppLeftovers.refusal(for: url, tie: tie, below: root, apps: gone, appKnown: own) { return refusal }
        }
        if let part = RemovedAppLeftovers.neverOfferedPart(of: url, below: root) { return .protected(part) }
        return Removability.canMoveToTrash(url) ? nil : .notPermitted
    }

    /// The rules of `offered` that hold any of `items`, in first-seen order: the plan's own items stay there (#354).
    static func planRuleIDs(offering items: [Candidate], among offered: [Candidate]) -> [String] {
        let paths = items.map { $0.url.standardizedFileURL.path }
        var ids: [String] = []
        for item in offered where !ids.contains(item.ruleID) {
            let path = item.url.standardizedFileURL.path
            if paths.contains(where: { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }) { ids.append(item.ruleID) }
        }
        return ids
    }

    /// One line of the review's "what stays and why" (Decision 51, #354): what stays, why and what to do, one per app and reason.
    public struct Staying: Sendable, Equatable, Identifiable {
        public let id: String
        public let text: String
        /// Where it can be cleaned, when CacheDrop can lead there.
        public var link: Link? = nil
        public enum Link: Sendable, Equatable {
            /// The Cleanup plan, with these rules' categories revealed.
            case cleanupPlan(ruleIDs: [String])
            /// Finder, with these items selected.
            case finder(paths: [String])
            public var title: String {
                switch self {
                case .cleanupPlan: "Clean in the Cleanup plan"
                case .finder: "Reveal in Finder"
                }
            }
        }
    }
    /// For each app being uninstalled: its items left unticked, those that need a password, and those the plan offers.
    public static func staying(chosen: [Candidate], offered: [Candidate]) -> [Staying] {
        let ids = Set(chosen.map(\.id))
        var apps: [Target] = []
        // The products being uninstalled: a shared item ticked with one names that one, never the sharer it was found with (#288).
        let own = chosen.filter(\.sharedBy.isEmpty)
        for item in own.isEmpty ? chosen : own { if let app = item.uninstall, !apps.contains(where: { $0.path == app.path }) { apps.append(app) } }
        return apps.flatMap { app in
            let unticked = offered.filter { $0.isUninstalled(with: app.path) && !ids.contains($0.id) }.count
            // One line per reason, singular or plural: what stays, why, and what to do about it.
            func line(_ reason: String, _ count: Int, _ one: String, _ many: String, link: Staying.Link? = nil) -> Staying? {
                guard count > 0 else { return nil }
                return Staying(id: app.path + "-" + reason, text: count == 1 ? one : many, link: link)
            }
            let name = app.name, n = app.needsPassword
            let password = app.tool.map { "\($0) or your password" } ?? "your password"
            let removeWith = app.tool.map { "with \($0) or in Finder" } ?? "in Finder"
            let inside = app.plugIn?.insideApp ?? 0, unknown = app.unrecognised, plan = app.inPlan
            return [
                line("unticked", unticked, "\(name): 1 item you didn’t tick stays. Go back and tick it to remove it too.",
                     "\(name): \(unticked) items you didn’t tick stay. Go back and tick them to remove them too."),
                line("password", n, "\(name): 1 file needs \(password) to remove, so it stays. Remove it \(removeWith) if you want it gone.",
                     "\(name): \(n) files need \(password) to remove, so they stay. Remove them \(removeWith) if you want them gone.",
                     link: app.passwordPaths.isEmpty ? nil : .finder(paths: app.passwordPaths)),
                line("inside", inside, "\(name): 1 plug-in lives inside its app and goes when you uninstall that app.",
                     "\(name): \(inside) plug-ins live inside their app and go when you uninstall that app."),
                line("unrecognised", unknown, "\(name): 1 file is kept to be safe because CacheDrop doesn’t know what it is. You don’t need to do anything.",
                     "\(name): \(unknown) files are kept to be safe because CacheDrop doesn’t know what they are. You don’t need to do anything."),
                // The count says it isn't all of its files: the rest go with the app.
                line("plan", plan, "1 of \(name)’s files isn’t removed here; clean it in the Cleanup plan.",
                     "\(plan) of \(name)’s files aren’t removed here; clean them in the Cleanup plan.",
                     link: app.inPlanRuleIDs.isEmpty ? nil : .cleanupPlan(ruleIDs: app.inPlanRuleIDs)),
            ].compactMap { $0 }
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
    /// The maker's other apps are hidden too, so the app's own files are found although they keep the maker installed (#305);
    /// `isOwn` then keeps only what is tied to the app's `own` bundle IDs, so nothing of theirs is ever offered with it.
    struct Without: AppPresence {
        let app: InstalledApp
        let url: URL
        let base: any AppPresence
        /// The app's own and its helpers' bundle IDs, lowercased.
        let own: Set<String>
        let vendor: String
        init(app: InstalledApp, url: URL, in base: any AppPresence, own: Set<String>) {
            self.app = app; self.url = url.standardizedFileURL; self.base = base; self.own = own
            vendor = RemovedAppLeftovers.vendor(of: app.bundleID)
        }
        /// Another app of the maker: not this one, nor a copy of it or of its helpers.
        func isOtherOfMaker(_ bundleID: String) -> Bool {
            !own.contains(bundleID.lowercased()) && RemovedAppLeftovers.vendor(of: bundleID) == vendor
        }
        func installedApps() -> [InstalledApp]? {
            base.installedApps()?.filter { URL(fileURLWithPath: $0.path).standardizedFileURL.path != url.path && !isOtherOfMaker($0.bundleID) }
        }
        func isRegistered(bundleID: String) -> Bool {
            if isOtherOfMaker(bundleID) { return false }
            guard bundleID.lowercased() == app.bundleID.lowercased() else { return base.isRegistered(bundleID: bundleID) }
            return installedApps()?.contains { $0.bundleID.lowercased() == bundleID.lowercased() } ?? true
        }
        /// Decision 41 as an allow-list (#305): an item goes with the app only when it is tied to one of the app's own bundle IDs,
        /// and its name names no other. One named only like the app or its maker, and a group container, stay when anything
        /// else installed, the maker's other apps included, goes by that name or maker. Anything else, a receipt's item included,
        /// stays; so does everything when the installed apps can't be listed.
        func isOwn(_ item: URL, tie: LeftoverTie) -> Bool {
            guard let id = tie.bundleID?.lowercased(), own.contains(id), let installed = base.installedApps() else { return false }
            let others = InstalledMakers(installed.filter { URL(fileURLWithPath: $0.path).standardizedFileURL.path != url.path && !own.contains($0.bundleID.lowercased()) })
            let name = item.lastPathComponent
            if let named = RemovedAppLeftovers.bundleID(inName: name) {
                guard own.contains(named.lowercased()) else { return false }
            } else if others.goesBy(RemovedAppLeftovers.token(name)) { return false }
            return !RemovedAppLeftovers.isGroupContainer(item) || !others.makes(tie.vendor)
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
    /// The scan's one read of the receipts (#318): the app bundles each installed and what it put in the user's Library.
    public init(_ listings: ReceiptListings, home: URL) {
        let library = home.resolvingSymlinksInPath().path + "/Library/"
        all = listings.listed.map { receipt in
            var apps = Set<String>()
            for path in receipt.paths {
                if let app = path.range(of: ".app/").map({ String(path[..<$0.lowerBound]) + ".app" }) ?? (path.hasSuffix(".app") ? path : nil) { apps.insert(app) }
            }
            return InstallerReceipt(id: receipt.id, apps: apps.sorted(), paths: receipt.paths.filter { $0.hasPrefix(library) })
        }
    }
    public func receipts() -> [InstallerReceipt] { all }
}
