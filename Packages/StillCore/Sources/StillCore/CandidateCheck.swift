import Foundation
import Darwin

/// Whether a rule's owner is running. `nil` means it could not be determined, which refuses.
public protocol RunningAppChecking: Sendable {
    func isRunning(_ owner: RuleOwner) -> Bool?
}

/// Why a candidate was not acted on. Shown in results and recorded in the journal.
public enum CheckRefusal: Sendable, Equatable {
    case missing, changed, ownerRunning(String), ownerUnknown(String), protected(String), excluded, notPermitted, cloud
    case inUse(String), inUseUnknown(String)
    case keptDownloaded, notUploaded, conflicted, notDownloaded, cloudUnknown
    case guidanceOnly
    public var reason: String {
        switch self {
        case .missing: "No longer exists."
        case .changed: "Changed since the scan."
        case .ownerRunning(let name): "\(name) is running. Quit it, then scan again."
        case .ownerUnknown(let name): "Couldn’t check whether \(name) is running."
        case .protected(let name): "Contains protected data (\(name))."
        case .excluded: "Excluded in Settings."
        case .notPermitted: "Still can’t change it without admin rights."
        case .cloud: "Stored in iCloud."
        case .inUse(let name): "\(name) is using it. It is kept."
        case .inUseUnknown(let name): "Couldn’t check whether \(name) is using it, so it is kept."
        case .keptDownloaded: "Set to Keep Downloaded. Its local copy stays."
        case .notUploaded: "Not fully uploaded to iCloud yet. Its local copy stays."
        case .conflicted: "Has an iCloud conflict to resolve. Its local copy stays."
        case .notDownloaded: "No local copy to remove."
        case .cloudUnknown: "Couldn’t read its iCloud status. Its local copy stays."
        case .guidanceOnly: "Guidance only. Still never changes it; manage it in its own app."
        }
    }
}

/// Spec section 4: the checks run just before acting on each item.
public struct CandidateCheck: Sendable {
    public let catalog: Catalog
    public let running: any RunningAppChecking
    public let exclusions: ExclusionPolicy
    /// Whether a leaked copy is in use now (rules with `copies`).
    public let inUse: any InUseChecking
    /// iCloud state, for evict candidates.
    public let cloud: any UbiquitousItemAccess
    /// The home folder the catalog was scanned under: a picked folder's files are never taken from its protected
    /// folders (`UserFiles`), and a git repository in it doesn't make what it holds live work (`GitCheckout`).
    public let home: URL
    /// At most this many entries are looked at; a deeper search that would need more refuses the folder.
    static let protectedSearchLimit = 200_000

    /// Levels a folder candidate of any rule is searched for a git working tree. A path under a cache folder doesn't
    /// prove a folder is disposable: Cargo's git checkouts and agents' worktrees sit a few levels down.
    static let gitSearchDepth = 4

    /// The first protected entry inside a folder candidate: the rule's protected names to its own depth, and
    /// `.git` to `gitSearchDepth` whatever the rule. Discovery leaves such folders out; the check refuses them.
    static func protectedEntry(in folder: URL, rule: CleanupRule) -> String? {
        if let found = protectedEntry(in: folder, names: Protection(rule).names, depth: rule.protectedDepth) { return found }
        return rule.protectedDepth >= gitSearchDepth ? nil : protectedEntry(in: folder, names: [".git"], depth: gitSearchDepth)
    }

    /// The first protected name among the entries up to `depth` levels inside `folder`, never following symlinks or crossing volumes.
    /// A folder that can't be fully searched answers with the reason, so it is refused rather than guessed at.
    static func protectedEntry(in folder: URL, names: Set<String>, depth: Int) -> String? {
        if depth <= 1 {
            return names.sorted().first { name in
                var inner = stat()
                return lstat(folder.appendingPathComponent(name).path, &inner) == 0
            }
        }
        var seen = 0, found: String?
        let opened = FileTree.walk(folder) { entry in
            let level = Int(entry.pointee.fts_level), kind = Int32(entry.pointee.fts_info)
            guard level > 0, kind != FTS_DP else { return .continue }
            seen += 1
            if seen > protectedSearchLimit { found = "too many items to check"; return .stop }
            let name = String(cString: entry.pointee.fts_path).split(separator: "/").last.map(String.init) ?? ""
            if names.contains(name) { found = name; return .stop }
            if kind == FTS_DNR || kind == FTS_ERR { found = "unreadable folder"; return .stop }
            return kind == FTS_D && level >= depth ? .skip : .continue
        }
        return opened ? found : "unreadable folder"
    }
    public init(catalog: Catalog, running: any RunningAppChecking, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = SystemInUseChecker(),
                cloud: any UbiquitousItemAccess = SystemUbiquitousItems(), home: URL) {
        self.catalog = catalog; self.running = running; self.exclusions = exclusions; self.inUse = inUse; self.cloud = cloud; self.home = home
    }
    /// This check with one reading of the process table, for checking many items together (a review or a cleanup run).
    public func snapshotted() -> CandidateCheck {
        CandidateCheck(catalog: catalog, running: running, exclusions: exclusions, inUse: inUse.snapshot(), cloud: cloud, home: home)
    }
    public func check(_ candidate: Candidate) -> CheckRefusal? {
        // Guidance-only data is never acted on, whatever the candidate or its rule says (SPEC section 3).
        if candidate.action == .guidance || catalog.rule(candidate.ruleID)?.action == .guidance { return .guidanceOnly }
        guard let rule = catalog.rule(candidate.ruleID),
              rule.action == candidate.action || (candidate.isLeftover && rule.deletesItems && candidate.action == .delete) else { return .changed }
        // A per-item command's argument is never an option, whatever the item says (#134).
        if candidate.action == .tool, rule.tool?.itemPlaceholder != nil, candidate.toolArgument.map({ $0.isEmpty || $0.hasPrefix("-") }) ?? true { return .changed }
        let ownership = Catalog.ownership(of: candidate.url, under: rule)
        switch ownership {
        // An item whose own owner can't be found any more (the app was removed) is refused, never guessed.
        case .unknown: return .ownerUnknown(candidate.appName ?? candidate.url.lastPathComponent)
        case .mustBeClosed(let owner):
            switch running.isRunning(owner) {
            case nil: return .ownerUnknown(owner.name)
            case true?: return .ownerRunning(owner.name)
            case false?: break
            }
        case .mustNotUse, .none: break
        }
        let path = candidate.url.path
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .missing : .notPermitted }
        let type = info.st_mode & S_IFMT
        guard type == (candidate.isDirectory ? S_IFDIR : S_IFREG), info.resourceID == candidate.resourceID else { return .changed }
        // The same folder moved out of scope and reached through a symlink keeps its identity, so containment is checked too.
        guard let root = candidate.scopeRoot, ScopeContainment.contains(candidate.url, in: root) else { return .changed }
        if let part = Protection(rule).protectedComponent(of: candidate.url, below: root) { return .protected(part) }
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
        // A system image a virtual device started using since the scan is kept (#134).
        if rule.items == .androidSystemImages, AndroidSDK.referencedImages(home: home).map({ $0.contains(AndroidSDK.key(candidate.url)) }) ?? true {
            return .inUse("An Android virtual device")
        }
        // A simulator booted, or a runtime a device started using, since the scan is kept (#143).
        if rule.items == .simulatorDevices || rule.items == .simulatorRuntimes, let items = rule.items,
           let refusal = SimulatorInventory.refusal(for: candidate, items: items) { return refusal }
        // An old temporary item that anything inside changed in since the scan is in use again (`TemporaryFiles`).
        if rule.unused != nil, !candidate.isLeftover, Catalog.lastChange(in: candidate.url).map({ $0 > candidate.observedAt }) ?? true { return .changed }
        guard info.st_uid == geteuid(),
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
