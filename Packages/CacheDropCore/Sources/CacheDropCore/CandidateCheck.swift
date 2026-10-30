import Foundation
import Darwin

/// Whether a rule's owner is running. `nil` means it could not be determined, which refuses.
public protocol RunningAppChecking: Sendable {
    func isRunning(_ owner: RuleOwner) -> Bool?
    /// A checker that lists processes once and keeps what it reads, for checking many items together (#261).
    func snapshot() -> any RunningAppChecking
}
extension RunningAppChecking {
    public func snapshot() -> any RunningAppChecking { self }
}

/// Why a candidate was not acted on. Shown in results and recorded in the journal.
public enum CheckRefusal: Sendable, Hashable {
    case missing, changed, ownerRunning(String), ownerUnknown(String), protected(String), excluded, notPermitted, cloud
    case inUse(String), inUseUnknown(String)
    case keptDownloaded, notUploaded, conflicted, notDownloaded, cloudUnknown
    case guidanceOnly
    /// A project's build folder (#157) is kept while the project is being worked on.
    case projectOpen, projectUnchecked, recentlyEdited, uncommittedChanges, trackedByGit
    /// A removed app's leftover whose app is on this Mac again, or can't be shown not to be (#173).
    case appInstalled(String)
    /// A plug-in support item, while any installer record can't be read (#291): unread is never "lists nothing".
    case receiptsUnread
    /// A plug-in support item or vendor content holding a file not of a kind known to be safe (#291, Decision 53).
    case unrecognised(String)
    /// A folder a tool named or its config set that no longer passes the write-scope checks (#201, #205); the reason names the tool.
    case notACache(String)
    public var reason: String {
        switch self {
        case .missing: "No longer exists."
        case .changed: "Changed since the scan."
        case .ownerRunning(let name): "\(name) is running. Quit it, then scan again."
        case .ownerUnknown(let name): "Couldn’t check whether \(name) is running."
        case .protected(let name): "Contains protected data (\(name))."
        case .excluded: "In Protected items, in Locations & access."
        case .notPermitted: "CacheDrop can’t change it without admin rights."
        case .cloud: "Stored in iCloud."
        case .inUse(let name): "\(name) is using it. It is kept."
        case .inUseUnknown(let name): "Couldn’t check whether \(name) is using it, so it is kept."
        case .keptDownloaded: "Set to Keep Downloaded. Its local copy stays."
        case .notUploaded: "Not fully uploaded to iCloud yet. Its local copy stays."
        case .conflicted: "Has an iCloud conflict to resolve. Its local copy stays."
        case .notDownloaded: "No local copy to remove."
        case .cloudUnknown: "Couldn’t read its iCloud status. Its local copy stays."
        case .guidanceOnly: "Guidance only. CacheDrop never changes it; manage it in its own app."
        case .projectOpen: "Its project is open in an app or tool. It is kept."
        case .projectUnchecked: "Couldn’t check whether its project is in use, so it is kept."
        case .recentlyEdited: "Its project changed in the last \(ProjectBuilds.recentDays) days. It is kept."
        case .uncommittedChanges: "Its project has uncommitted changes. It is kept."
        case .trackedByGit: "Git tracks files in it. It is kept."
        case .appInstalled(let name): "\(name) is installed again, or CacheDrop couldn’t check. It is kept."
        case .receiptsUnread: "Couldn’t read every installer receipt, so it is kept."
        case .unrecognised(let name): "Holds files CacheDrop doesn’t recognize (\(name)), so it is kept."
        case .notACache(let reason): reason
        }
    }
}

/// Spec section 4: the checks run just before acting on each item.
public struct CandidateCheck: Sendable {
    public let catalog: Catalog
    public let running: any RunningAppChecking
    public let exclusions: ProtectedItemsPolicy
    /// Whether a leaked copy is in use now (rules with `copies`).
    public let inUse: any InUseChecking
    /// iCloud state, for evict candidates.
    public let cloud: any UbiquitousItemAccess
    /// The home folder the catalog was scanned under: a picked folder's files are never taken from its protected
    /// folders (`UserFiles`), and a git repository in it doesn't make what it holds live work (`GitCheckout`).
    public let home: URL
    /// Which apps are installed, for a removed app's leftovers (#173).
    public let apps: any AppPresence
    /// The installer receipts, read again once per check (a review or a run) when a plug-in support item asks (#291).
    let receipts: LazyReceipts
    /// At most this many entries are looked at; a deeper search that would need more refuses the folder.
    static let protectedSearchLimit = 200_000

    /// Levels a folder candidate of any rule is searched for a git working tree. A path under a cache folder doesn't
    /// prove a folder is disposable: Cargo's git checkouts and agents' worktrees sit a few levels down.
    static let gitSearchDepth = 4

    /// The first protected entry inside a folder candidate: the rule's protected names to its own depth, and
    /// `.git` to `gitSearchDepth` whatever the rule. Discovery leaves such folders out; the check refuses them.
    static func protectedEntry(in folder: URL, rule: CleanupRule) -> String? {
        if let found = protectedEntry(in: folder, names: Protection(rule).names, depth: rule.protectedDepth, alsoProtected: AppCaches.isOwn) { return found }
        if let offline = rule.offlineContentLabel(in: folder) { return offline }
        if rule.protectedDepth >= gitSearchDepth { return nil }
        // A package manager's own clones in its build folder are rebuilt, not live work (#160): only those `.git` folders are passed over.
        let clones = ProjectBuilds.managedClonesFolder(in: folder).map { $0.path + "/" }
        return protectedEntry(in: folder, names: [".git"], depth: gitSearchDepth, allowed: { path, level, isFolder in
            guard let clones, isFolder, level == 3, path.hasPrefix(clones) else { return false }
            return path.dropFirst(clones.count).split(separator: "/").count == 2
        })
    }

    /// The first protected name among the entries up to `depth` levels inside `folder`, never following symlinks or crossing volumes.
    /// A folder that can't be fully searched answers with the reason, so it is refused rather than guessed at.
    /// `alsoProtected` matches names beyond `names` (CacheDrop's and Still's IDs by prefix, as `isExcluded` does).
    /// `allowed` passes over a found entry (by path, level and whether it is a folder) without looking inside it.
    static func protectedEntry(in folder: URL, names: Set<String>, depth: Int, alsoProtected: ((String) -> Bool)? = nil,
                               allowed: (_ path: String, _ level: Int, _ isFolder: Bool) -> Bool = { _, _, _ in false }) -> String? {
        if depth <= 1 {
            let named = names.sorted().first { name in
                var inner = stat()
                return lstat(folder.appendingPathComponent(name).path, &inner) == 0
            }
            // An unreadable folder is answered as the exact-name lookups above answer it: it couldn't be cleaned either.
            guard named == nil, let alsoProtected else { return named }
            return (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted().first(where: alsoProtected)
        }
        var seen = 0, found: String?
        let opened = FileTree.walk(folder) { entry in
            let level = Int(entry.pointee.fts_level), kind = Int32(entry.pointee.fts_info)
            guard level > 0, kind != FTS_DP else { return .continue }
            seen += 1
            if seen > protectedSearchLimit { found = "too many items to check"; return .stop }
            let path = String(cString: entry.pointee.fts_path), name = path.split(separator: "/").last.map(String.init) ?? ""
            if names.contains(name) || alsoProtected?(name) == true {
                if allowed(path, level, kind == FTS_D) { return .skip }
                found = name; return .stop
            }
            if kind == FTS_DNR || kind == FTS_ERR { found = "unreadable folder"; return .stop }
            return kind == FTS_D && level >= depth ? .skip : .continue
        }
        return opened ? found : "unreadable folder"
    }
    public init(catalog: Catalog, running: any RunningAppChecking, exclusions: ProtectedItemsPolicy = ProtectedItemsPolicy(), inUse: any InUseChecking = SystemInUseChecker(),
                cloud: any UbiquitousItemAccess = SystemUbiquitousItems(), home: URL, apps: any AppPresence = SystemAppPresence(),
                systemRoot: URL = URL(fileURLWithPath: "/")) {
        self.catalog = catalog; self.running = running; self.exclusions = exclusions; self.inUse = inUse; self.cloud = cloud; self.home = home; self.apps = apps
        receipts = LazyReceipts(systemRoot)
    }
    /// This check with one reading of the process table, for checking many items together (a review or a cleanup run).
    public func snapshotted() -> CandidateCheck {
        CandidateCheck(catalog: catalog, running: running.snapshot(), exclusions: exclusions, inUse: inUse.snapshot(), cloud: cloud, home: home, apps: apps.snapshot(),
                       systemRoot: receipts.systemRoot)
    }
    /// Whether checking this candidate asks what processes have open: leaked copies and old temporary items.
    public func needsInUseCheck(_ candidate: Candidate) -> Bool {
        guard let rule = catalog.rule(candidate.ruleID) else { return false }
        return rule.copies != nil || rule.unused != nil || rule.id == ProjectBuilds.ruleID || rule.family == .removedAppLeftovers
    }
    /// Each refused candidate's reason, by candidate id; one that passes has no entry. The review reads it when it opens and
    /// again after an app quits (#377).
    public func refusals(of candidates: [Candidate]) -> [String: CheckRefusal] {
        Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in check(candidate).map { (candidate.id, $0) } })
    }
    /// Revalidates an item against its rule and current safety checks; nil means it may be acted on now.
    public func check(_ candidate: Candidate) -> CheckRefusal? {
        // Guidance-only data is never acted on, whatever the candidate or its rule says (SPEC section 3).
        if candidate.action == .guidance || catalog.rule(candidate.ruleID)?.action == .guidance { return .guidanceOnly }
        guard let rule = catalog.rule(candidate.ruleID),
              rule.action == candidate.action || (candidate.isDeletionRemnant && rule.deletesItems && candidate.action == .delete) else { return .changed }
        // A per-item command's argument is never an option, whatever the item says (#134).
        if candidate.action == .tool, rule.tool?.itemPlaceholder != nil, candidate.toolArgument.map({ $0.isEmpty || $0.hasPrefix("-") }) ?? true { return .changed }
        let ownership = Catalog.ownership(of: candidate, under: rule)
        func runningRefusal(_ owner: RuleOwner) -> CheckRefusal? {
            switch running.isRunning(owner) {
            case nil: .ownerUnknown(owner.name)
            case true?: .ownerRunning(owner.name)
            case false?: nil
            }
        }
        switch ownership {
        // An item whose own owner can't be found any more (the app was removed) is refused, never guessed.
        case .unknown: return .ownerUnknown(candidate.appName ?? candidate.url.lastPathComponent)
        case .mustBeClosed(let owner): if let refusal = runningRefusal(owner) { return refusal }
        case .mustNotUse, .none: break
        }
        // A plug-in product waits for every plug-in host to close too (#176, Decision 51).
        for host in candidate.uninstall?.plugIn?.hosts ?? [] { if let refusal = runningRefusal(host) { return refusal } }
        let path = candidate.url.path
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .missing : .notPermitted }
        let type = info.st_mode & S_IFMT
        guard type == (candidate.isDirectory ? S_IFDIR : S_IFREG), info.resourceID == candidate.resourceID else { return .changed }
        // The same folder moved out of scope and reached through a symlink keeps its identity, so containment is checked too.
        guard let root = candidate.scopeRoot, ScopeContainment.contains(candidate.url, in: root) else { return .changed }
        if let part = Protection(rule).protectedComponent(of: candidate.url, below: root) { return .protected(part) }
        // An app cache item is the app's whole folder or an item the rule offers from it now (#203, #241); one that became a
        // web-view profile or gained offline content says so.
        if rule.id == AppCaches.appCachesRuleID, !candidate.isDeletionRemnant, !AppCaches.isOfferedItem(candidate.url, offlineContent: rule.offlineContent) {
            return (candidate.isDirectory ? Self.protectedEntry(in: candidate.url, rule: rule) : nil).map(CheckRefusal.protected) ?? .changed
        }
        if let refusal = catalog.notACacheRefusal(candidate, rule: rule, base: root) { return refusal }
        let picked = rule.fromPickedFolders
        if picked, let folder = UserFiles.protectedFolder(of: candidate.url, home: home) { return .protected(folder) }
        // A picked folder's file is looked at above the folder too, as the explorer does when it lists it.
        if !candidate.isDirectory, GitCheckout.encloses(candidate.url, upTo: picked ? nil : root, home: home) { return .protected(".git") }
        if !candidate.isDirectory {
            // Files must be byte-for-byte the observed version; cache folders churn, so folders keep identity only.
            guard Int64(info.st_size) == candidate.fileBytes ?? candidate.logicalBytes, Int64(info.st_mtimespec.tv_sec) == candidate.modifiedSeconds,
                  Int64(info.st_mtimespec.tv_nsec) == candidate.modifiedNanoseconds else { return .changed }
        }
        if case .mustNotUse(let owner) = ownership {
            guard let used = inUse.inUse([candidate.url], by: owner) else { return .inUseUnknown(owner.name) }
            if !used.isEmpty { return .inUse(owner.name) }
        }
        // An old temporary item with an app of its own must also not be open in any process.
        if rule.unused != nil, rule.itemOwner != nil {
            guard let used = inUse.inUse([candidate.url], by: .anyApp) else { return .inUseUnknown(RuleOwner.anyApp.name) }
            if !used.isEmpty { return .inUse(RuleOwner.anyApp.name) }
        }
        // A removed app's leftover: never license or macOS data, and kept once its app is back (#173).
        let uninstalling = rule.family?.isUninstall == true
        if !uninstalling, let tie = candidate.leftover, let refusal = RemovedAppLeftovers.refusal(for: candidate.url, tie: tie, below: root, apps: apps) { return refusal }
        // An app and its files (#177): removable without a password now, whoever owns them (Decision 50).
        if uninstalling, let refusal = AppUninstall.refusal(for: candidate, rule: rule, below: root, apps: apps, receipts: receipts) { return refusal }
        // A project being worked on keeps its build folders (#157), unless the user ticked one the scan showed held by a policy
        // guard (#374); one shown only as open still meets every guard.
        if rule.id == ProjectBuilds.ruleID,
           let refusal = ProjectBuilds.refusal(for: candidate.url, inUse: inUse, home: home,
                                               overridingPolicy: candidate.hold.map { ProjectBuilds.policyReasons.contains($0.refusal) } == true) { return refusal }
        // A system image a virtual device started using since the scan is kept (#134).
        if rule.items == .androidSystemImages, AndroidSDK.referencedImages(home: home).map({ $0.contains(AndroidSDK.key(candidate.url)) }) ?? true {
            return .inUse("An Android virtual device")
        }
        // A simulator booted, or a runtime a device started using, since the scan is kept (#143).
        if rule.items == .simulatorDevices || rule.items == .simulatorRuntimes, let items = rule.items,
           let refusal = SimulatorInventory.refusal(for: candidate, items: items) { return refusal }
        // An old temporary item that anything inside changed in since the scan is in use again (`TemporaryFiles`).
        if rule.unused != nil, !candidate.isDeletionRemnant, Catalog.lastChange(in: candidate.url).map({ $0 > candidate.observedAt }) ?? true { return .changed }
        guard uninstalling || info.st_uid == geteuid(),
              info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0,
              access(candidate.url.deletingLastPathComponent().path, W_OK | X_OK) == 0 else { return .notPermitted }
        let values = try? candidate.url.resourceValues(forKeys: [.volumeUUIDStringKey, .isUbiquitousItemKey, .isPackageKey])
        if candidate.action == .evict { return evictionRefusal(candidate, rule: rule, info: info, values: values) }
        if values?.isUbiquitousItem == true || info.st_flags & UInt32(SF_DATALESS) != 0 { return .cloud }
        guard let volume = values?.volumeUUIDString, volume == candidate.volumeID else { return .changed }
        if candidate.isDirectory, let name = Self.protectedEntry(in: candidate.url, rule: rule) { return .protected(name) }
        if exclusions.covers(candidate.url, volumeID: volume) { return .excluded }
        return nil
    }

    /// An iCloud item keeps its local copy unless one can be removed now: a file or package by its own state,
    /// a folder when at least one file inside qualifies. Reads metadata only, with downloads blocked.
    private func evictionRefusal(_ candidate: Candidate, rule: CleanupRule, info: stat, values: URLResourceValues?) -> CheckRefusal? {
        if info.st_flags & UInt32(SF_DATALESS) != 0 { return .notDownloaded }
        guard let volume = values?.volumeUUIDString, volume == candidate.volumeID else { return .changed }
        if exclusions.covers(candidate.url, volumeID: volume) { return .excluded }
        if !candidate.isDirectory || values?.isPackage == true {
            return Catalog.withoutDownloads { cloud.metadata(candidate.url).evictionRefusal }
        }
        let copies = Catalog.cloudCopies(in: candidate.url, rule: rule, cloud: cloud, exclusions: exclusions, volumeID: volume)
        return copies.units.isEmpty ? .notDownloaded : nil
    }
}

/// Installer receipts read on first use, then kept for this check (#291): one read per review or run, none without plug-in items.
final class LazyReceipts: @unchecked Sendable {
    let systemRoot: URL
    private let lock = NSLock()
    private var read: ReceiptListings?
    init(_ systemRoot: URL) { self.systemRoot = systemRoot }
    var value: ReceiptListings {
        lock.lock(); defer { lock.unlock() }
        if let read { return read }
        let fresh = ReceiptListings.read(under: systemRoot)
        read = fresh
        return fresh
    }
}
