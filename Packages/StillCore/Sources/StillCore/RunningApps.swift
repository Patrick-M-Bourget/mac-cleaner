import AppKit
import Darwin
import Foundation

extension RuleOwner {
    /// Whether a process command line (argv) belongs to this owner: its executable is one of
    /// `executables`, or the script it runs (first non-option argument) is one of `scripts`.
    public func matches(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        if executables.contains(URL(fileURLWithPath: first).lastPathComponent) { return true }
        guard !scripts.isEmpty, let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return false }
        return scripts.contains(URL(fileURLWithPath: script).lastPathComponent)
    }
}

/// Apps by bundle identifier; command-line tools by the current user's process command lines.
public struct SystemRunningAppChecker: RunningAppChecking {
    public init() {}
    public func isRunning(_ owner: RuleOwner) -> Bool? {
        if owner.bundleIDs.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) { return true }
        guard !owner.executables.isEmpty || !owner.scripts.isEmpty else { return false }
        guard let commands = Self.userCommandLines() else { return nil }
        return commands.contains { owner.matches($0) }
    }

    /// argv of every process the current user owns, or nil when the list can't be read.
    static func userCommandLines() -> [[String]]? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) < pids.count else { return nil }
        let uid = getuid()
        return pids.prefix(Int(count)).compactMap { pid -> [String]? in
            guard pid > 0 else { return nil }
            var details = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size, details.pbi_uid == uid else { return nil }
            return arguments(pid)
        }
    }

    /// KERN_PROCARGS2 layout: argc (Int32), executable path, NUL padding, then argc NUL-terminated strings.
    private static func arguments(_ pid: pid_t) -> [String]? {
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
}
