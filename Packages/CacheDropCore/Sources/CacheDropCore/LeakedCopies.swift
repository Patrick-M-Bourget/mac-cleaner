import Foundation
import Darwin

/// Copies of an app it leaves behind, such as Chrome's code-sign clones. Each folder directly inside
/// the rule's location is one copy. The copy the owner's processes use and the newest copies are kept.
public struct LeakedCopies: Sendable {
    /// Whose processes may have a copy open or run from it.
    public let owner: RuleOwner
    /// How many of the newest copies (by creation date) are always kept.
    public let keepNewest: Int
    public init(owner: RuleOwner, keepNewest: Int = 1) { self.owner = owner; self.keepNewest = keepNewest }
}

/// Which folders a running app uses: a process runs from inside one, or has a file in one open or mapped.
public protocol InUseChecking: Sendable {
    /// The paths of `folders` in use by `owner`'s processes, or nil when that can't be determined.
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>?
    /// A checker that lists processes once and keeps what it reads, for one discovery or one cleanup run.
    func snapshot() -> any InUseChecking
}
extension InUseChecking {
    public func snapshot() -> any InUseChecking { self }
}

extension CleanupRule {
    /// Copies share disk blocks (APFS clones), so the sized total is an upper bound on what deleting them frees (SPEC section 6).
    public var estimateIsUpperBound: Bool { copies != nil }
}

extension Catalog {
    /// The current user's own folder under `/private/var/folders`, found without admin rights
    /// from the per-user temp folder (`T`) that `confstr` reports. Nil if macOS reports none.
    public static func currentUserFolder() -> URL? {
        for name in [_CS_DARWIN_USER_TEMP_DIR, _CS_DARWIN_USER_CACHE_DIR] {
            let length = confstr(name, nil, 0)
            guard length > 0 else { continue }
            var buffer = [CChar](repeating: 0, count: length)
            guard confstr(name, &buffer, length) > 0, let folder = userFolder(holding: String(cString: buffer)) else { continue }
            return folder
        }
        return nil
    }

    /// The folder holding the per-user `T` or `C` folder at `leaf`, by real path, when the current user owns it.
    static func userFolder(holding leaf: String) -> URL? {
        guard let leaf = realPath(leaf) else { return nil }
        let folder = URL(fileURLWithPath: leaf, isDirectory: true).deletingLastPathComponent()
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return folder
    }

    /// Every copy inside `root` except the ones in use and the newest. When in-use status can't be
    /// determined, nothing is offered and the note says why.
    func leakedCopies(_ rule: CleanupRule, _ copies: LeakedCopies, in root: URL, sizer: KnownLocationSizer, inUse checker: any InUseChecking) -> ([Candidate], CatalogNote?) {
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR, rootInfo.st_uid == geteuid() else { return ([], nil) }
        let protection = Protection(rule)
        let found = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).compactMap { name -> (URL, stat)? in
            var info = stat()
            let url = root.appendingPathComponent(name)
            guard !name.hasPrefix("."), !protection.protects(name),
                  lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else { return nil }
            return (url, info)
        }
        guard !found.isEmpty, case .mustNotUse(let owner) = Self.ownership(of: root, under: rule) else { return ([], nil) }
        guard let used = checker.inUse(found.map(\.0), by: owner) else {
            let count = found.count == 1 ? "its copy" : "all \(found.count) copies"
            return ([], CatalogNote(ruleID: rule.id, text: "\(rule.title): kept \(count), because CacheDrop couldn’t tell which one \(owner.name) is using."))
        }
        func created(_ info: stat) -> (Int, Int) { (info.st_birthtimespec.tv_sec, info.st_birthtimespec.tv_nsec) }
        let newest = Set(found.sorted { created($0.1) > created($1.1) }.prefix(copies.keepNewest).map(\.0.path))
        return (found.filter { !used.contains($0.0.path) && !newest.contains($0.0.path) }.map { url, info in
            let size = sizer.size(url)
            return candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
        }, nil)
    }
}

