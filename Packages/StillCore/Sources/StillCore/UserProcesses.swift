import AppKit
import Darwin
import Foundation

/// The one way Still lists what is running: the current user's processes through the documented libproc calls
/// (`proc_listallpids`, `proc_pidinfo`, `proc_pidpath`), and open apps by bundle identifier through `NSRunningApplication`.
/// The running-app check, the in-use check and the app quitter all read from here.
enum UserProcesses {
    /// The pid of each process the current user owns; nil when the list can't be read.
    static func pids() -> [pid_t]? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) < pids.count else { return nil }
        let uid = getuid()
        return pids.prefix(Int(count)).filter { pid in
            var details = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            return pid > 0 && proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size && details.pbi_uid == uid
        }
    }

    /// The process's executable; nil when it can't be read.
    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// The process's command line (argv); nil when it can't be read.
    /// KERN_PROCARGS2 layout: argc (Int32), executable path, NUL padding, then argc NUL-terminated strings.
    static func arguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var length = 0
        guard sysctl(&mib, 3, nil, &length, nil, 0) == 0, length > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 3, &buffer, &length, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < length, buffer[index] != 0 { index += 1 }
        while index < length, buffer[index] == 0 { index += 1 }
        var result: [String] = []
        while result.count < argc, index < length {
            let start = index
            while index < length, buffer[index] != 0 { index += 1 }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }

    /// Every running instance of an app with one of these bundle identifiers.
    static func apps(_ bundleIDs: [String]) -> [NSRunningApplication] {
        bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }
}
