import Foundation
import Darwin

/// Reads the current user's processes with libproc, as `lsof` does, without admin rights.
public struct SystemInUseChecker: InUseChecking {
    /// When set, only this process is read (tests), so other processes coming and going can't change the answer.
    let onlyProcess: pid_t?
    public init() { onlyProcess = nil }
    init(onlyProcess: pid_t) { self.onlyProcess = onlyProcess }
    /// Reads the process table afresh for this one question.
    public func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? { snapshot().inUse(folders, by: owner) }
    /// One reading shared by every question until it is dropped: a discovery asks once per rule, a cleanup run once per item.
    public func snapshot() -> any InUseChecking { SystemInUseSnapshot(onlyProcess: onlyProcess) }
}

/// The current user's processes, listed once. Each process's open and mapped files are read the first time a question
/// needs them and then kept, so asking about many items reads each process at most once.
final class SystemInUseSnapshot: InUseChecking, @unchecked Sendable {
    private let lock = NSLock()
    /// Nil when the process list can't be read.
    private let processes: [(pid: pid_t, executable: String)]?
    /// Each process's paths once read; an inner nil means they couldn't be read.
    private var paths: [pid_t: [String]?] = [:]

    init(onlyProcess: pid_t? = nil) { processes = Self.userProcesses()?.filter { onlyProcess == nil || $0.pid == onlyProcess } }

    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? {
        guard let processes else { return nil }
        // The kernel reports canonical paths (/private/var/...), so compare against each folder's real path.
        let roots = folders.map { realPath($0.path) ?? $0.path }
        func folder(holding path: String) -> String? {
            zip(folders, roots).first { path == $0.1 || path.hasPrefix($0.1 + "/") }?.0.path
        }
        var used = Set<String>()
        for (pid, executable) in processes {
            if let hit = folder(holding: executable) { used.insert(hit); continue }
            guard owner.matches([executable]) else { continue }
            // One of the owner's processes: an unreadable file list means in-use status is unknown.
            guard let paths = cachedPaths(pid) else {
                if kill(pid, 0) != 0, errno == ESRCH { continue }
                return nil
            }
            used.formUnion(paths.compactMap(folder(holding:)))
        }
        return used
    }

    private func cachedPaths(_ pid: pid_t) -> [String]? {
        lock.lock(); defer { lock.unlock() }
        if let known = paths[pid] { return known }
        let read = Self.openAndMappedPaths(pid)
        paths[pid] = .some(read)
        return read
    }

    /// The pid and executable of each process the current user owns; nil when the list can't be read.
    private static func userProcesses() -> [(pid: pid_t, executable: String)]? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) < pids.count else { return nil }
        let uid = getuid()
        return pids.prefix(Int(count)).compactMap { pid in
            var details = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size, details.pbi_uid == uid,
                  let executable = executablePath(pid) else { return nil }
            return (pid, executable)
        }
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
