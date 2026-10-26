import Foundation
import Darwin

/// Where a rule's locations are relative to.
public enum LocationBase: Sendable {
    /// The user's home folder.
    case home
    /// The user's own `/private/var/folders/<xx>/<id>` folder, which holds `T` (temp), `C` (cache) and `X`.
    case userFolder
}

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
}

/// Something discovery wants the user to know about a rule, such as why it offered nothing.
public struct CatalogNote: Sendable, Equatable {
    public let ruleID: String
    public let text: String
    public init(ruleID: String, text: String) { self.ruleID = ruleID; self.text = text }
}

public struct CatalogDiscovery: Sendable {
    public let candidates: [Candidate]
    public let notes: [CatalogNote]
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
        let protectedExtensions = CandidateCheck.protectedExtensions.union(rule.protectedExtensions)
        let found = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).compactMap { name -> (URL, stat)? in
            var info = stat()
            let url = root.appendingPathComponent(name)
            guard !name.hasPrefix("."), !protectedExtensions.contains(url.pathExtension.lowercased()),
                  lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else { return nil }
            return (url, info)
        }
        guard !found.isEmpty else { return ([], nil) }
        guard let used = checker.inUse(found.map(\.0), by: copies.owner) else {
            let count = found.count == 1 ? "its copy" : "all \(found.count) copies"
            return ([], CatalogNote(ruleID: rule.id, text: "\(rule.title): kept \(count), because Still couldn’t tell which one \(copies.owner.name) is using."))
        }
        func created(_ info: stat) -> (Int, Int) { (info.st_birthtimespec.tv_sec, info.st_birthtimespec.tv_nsec) }
        let newest = Set(found.sorted { created($0.1) > created($1.1) }.prefix(copies.keepNewest).map(\.0.path))
        return (found.filter { !used.contains($0.0.path) && !newest.contains($0.0.path) }.map { url, info in
            let size = sizer.size(url)
            return candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
        }, nil)
    }
}

/// Reads the current user's processes with libproc, as `lsof` does, without admin rights.
public struct SystemInUseChecker: InUseChecking {
    public init() {}
    public func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? {
        // The kernel reports canonical paths (/private/var/...), so compare against each folder's real path.
        let roots = folders.map { realPath($0.path) ?? $0.path }
        func folder(holding path: String) -> String? {
            zip(folders, roots).first { path == $0.1 || path.hasPrefix($0.1 + "/") }?.0.path
        }
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) < pids.count else { return nil }
        let uid = getuid()
        var used = Set<String>()
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var details = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size, details.pbi_uid == uid else { continue }
            guard let executable = Self.executablePath(pid) else { continue }
            if let hit = folder(holding: executable) { used.insert(hit); continue }
            guard owner.matches([executable]) else { continue }
            // One of the owner's processes: an unreadable file list means in-use status is unknown.
            guard let paths = Self.openAndMappedPaths(pid) else {
                if kill(pid, 0) != 0, errno == ESRCH { continue }
                return nil
            }
            used.formUnion(paths.compactMap(folder(holding:)))
        }
        return used
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// The current folder, open files and mapped files of one process; nil if they can't be read.
    private static func openAndMappedPaths(_ pid: pid_t) -> [String]? {
        var paths: [String] = []
        var vnode = proc_vnodepathinfo()
        let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vnodeSize) == vnodeSize else { return nil }
        paths.append(path(vnode.pvi_cdir.vip_path))
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return nil }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(listSize) / MemoryLayout<proc_fdinfo>.stride + 32)
        let filled = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return nil }
        for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            if proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, infoSize) == infoSize { paths.append(path(info.pvip.vip_path)) }
        }
        // Mapped files, such as a framework loaded from a copy, hold no descriptor.
        var address: UInt64 = 0
        var region = proc_regionwithpathinfo()
        let regionSize = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        while proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &region, regionSize) == regionSize {
            let mapped = path(region.prp_vip.vip_path)
            if !mapped.isEmpty { paths.append(mapped) }
            let next = region.prp_prinfo.pri_address &+ region.prp_prinfo.pri_size
            guard next > address else { break }
            address = next
        }
        return paths
    }

    private static func path<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}

/// The canonical path, as the kernel reports it; Foundation's `resolvingSymlinksInPath` drops `/private`.
func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}
