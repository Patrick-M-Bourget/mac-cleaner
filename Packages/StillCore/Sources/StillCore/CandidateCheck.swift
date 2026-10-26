import Foundation
import Darwin

/// Whether a rule's owner is running. `nil` means it could not be determined, which refuses.
public protocol RunningAppChecking: Sendable {
    func isRunning(_ owner: RuleOwner) -> Bool?
}

/// Why a candidate was not acted on. Shown in results and recorded in the journal.
public enum CheckRefusal: Sendable, Equatable {
    case missing, changed, ownerRunning(String), ownerUnknown(String), protected(String), excluded, notPermitted, cloud
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
        }
    }
}

/// Spec section 4: the checks run just before acting on each item.
public struct CandidateCheck: Sendable {
    public let catalog: Catalog
    public let running: any RunningAppChecking
    public let exclusions: ExclusionPolicy
    /// Never candidates, as the item, an ancestor or a top-level entry inside it (git work, Trash, backups).
    static let protectedNames: Set<String> = [".git", ".Trash", "Backups.backupdb"]
    static let protectedExtensions: Set<String> = ["app", "bundle", "framework", "xcarchive", "photoslibrary", "photolibrary", "musiclibrary", "backupbundle", "sparsebundle", "band", "logicx"]
    public init(catalog: Catalog, running: any RunningAppChecking, exclusions: ExclusionPolicy = ExclusionPolicy()) {
        self.catalog = catalog; self.running = running; self.exclusions = exclusions
    }
    public func check(_ candidate: Candidate) -> CheckRefusal? {
        guard let rule = catalog.rule(candidate.ruleID), rule.action == candidate.action else { return .changed }
        if let owner = rule.owner {
            switch running.isRunning(owner) {
            case nil: return .ownerUnknown(owner.name)
            case true?: return .ownerRunning(owner.name)
            case false?: break
            }
        }
        let path = candidate.url.path
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .missing : .notPermitted }
        let type = info.st_mode & S_IFMT
        guard type == (candidate.isDirectory ? S_IFDIR : S_IFREG), "\(info.st_dev):\(info.st_ino)" == candidate.resourceID else { return .changed }
        if !candidate.isDirectory {
            // Files must be byte-for-byte the observed version; cache folders churn, so folders keep identity only.
            guard Int64(info.st_size) == candidate.logicalBytes, Int64(info.st_mtimespec.tv_sec) == candidate.modifiedSeconds,
                  Int64(info.st_mtimespec.tv_nsec) == candidate.modifiedNanoseconds else { return .changed }
        }
        guard info.st_uid == geteuid(),
              info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0,
              access(candidate.url.deletingLastPathComponent().path, W_OK | X_OK) == 0 else { return .notPermitted }
        let values = try? candidate.url.resourceValues(forKeys: [.volumeUUIDStringKey, .isUbiquitousItemKey])
        if values?.isUbiquitousItem == true || info.st_flags & UInt32(SF_DATALESS) != 0 { return .cloud }
        guard let volume = values?.volumeUUIDString, volume == candidate.volumeID else { return .changed }
        let names = Self.protectedNames.union(rule.protectedNames)
        for part in candidate.url.pathComponents {
            if names.contains(part) || Self.protectedExtensions.contains(URL(fileURLWithPath: part).pathExtension.lowercased()) { return .protected(part) }
        }
        if candidate.isDirectory {
            for name in names.sorted() {
                var inner = stat()
                if lstat(candidate.url.appendingPathComponent(name).path, &inner) == 0 { return .protected(name) }
            }
        }
        if exclusions.matches(candidate.url, volumeID: volume) { return .excluded }
        let parts = candidate.url.standardizedFileURL.pathComponents
        if exclusions.rules.contains(where: { $0.volumeID == volume && URL(fileURLWithPath: $0.path).pathComponents.starts(with: parts) }) { return .excluded }
        return nil
    }
}
