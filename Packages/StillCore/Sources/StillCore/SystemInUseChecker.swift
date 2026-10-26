import Foundation
import Darwin

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
        while proc_pidinfo(pid, regionFlavor, address, &region, regionSize) == regionSize {
            let mapped = path(region.prp_vip.vip_path)
            if !mapped.isEmpty { paths.append(mapped) }
            let next = region.prp_prinfo.pri_address &+ region.prp_prinfo.pri_size
            guard next > address else { break }
            address = next
        }
        return paths
    }

    /// libproc's flavor that walks only file-backed regions, as `lsof` does (`PROC_PIDREGIONPATHINFO2`, not in the public header).
    /// Every region takes about 2 seconds for all of the user's processes; file-backed ones about 0.2. It is used only when it
    /// reports this process's own mapped executable, so a macOS without it falls back to walking every region.
    static let regionFlavor: Int32 = {
        let fileBackedOnly: Int32 = 22
        var region = proc_regionwithpathinfo()
        let regionSize = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        guard proc_pidinfo(getpid(), fileBackedOnly, 0, &region, regionSize) == regionSize, !path(region.prp_vip.vip_path).isEmpty else { return PROC_PIDREGIONPATHINFO }
        return fileBackedOnly
    }()

    private static func path<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}
