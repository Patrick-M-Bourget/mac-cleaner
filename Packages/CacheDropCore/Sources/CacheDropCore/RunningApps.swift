import AppKit
import Darwin
import Foundation

extension RuleOwner {
    /// Whether a process command line (argv) belongs to this owner: its executable is one of
    /// `executables`, it runs from inside one of `paths`, a later argument is one of `arguments`, or the script it runs (first non-option argument) is one of `scripts`.
    public func matches(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        func matches(_ patterns: [String], _ value: String) -> Bool { patterns.contains { fnmatch($0, value, 0) == 0 } }
        if matches(executables, URL(fileURLWithPath: first).lastPathComponent) { return true }
        if paths.contains(where: { first.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) { return true }
        if arguments.dropFirst().contains(where: { matches(self.arguments, $0) }) { return true }
        guard !scripts.isEmpty, let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return false }
        return matches(scripts, URL(fileURLWithPath: script).lastPathComponent)
    }
}

/// Apps by bundle identifier; command-line tools by the current user's process command lines.
/// A maker (`bundleIDPrefixes`) by every running process, background helpers included (#240), listed through `processes`.
public struct SystemRunningAppChecker: RunningAppChecking {
    let processes: any ProcessListing
    private let makers = RunningMakerCache()
    public init(processes: any ProcessListing = SystemProcessListing()) { self.processes = processes }
    public func isRunning(_ owner: RuleOwner) -> Bool? {
        if !UserProcesses.apps(owner.bundleIDs).isEmpty { return true }
        if !owner.bundleIDPrefixes.isEmpty {
            guard let running = processes.processes() else { return nil }
            if RunningMakers(running, resolve: makers.products).runs(owner) { return true }
        }
        // An app's helpers and login items: any process, background ones included, by bundle ID or run from inside the app (#281).
        let listed = owner.paths.isEmpty ? nil : processes.processes()
        if let listed, listed.contains(where: { process in
            process.bundleID.map(owner.bundleIDs.contains) == true || owner.paths.contains { process.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }) { return true }
        // Every process's executable was listed, so a folder owner needs no command lines.
        guard !owner.executables.isEmpty || !owner.scripts.isEmpty || !owner.arguments.isEmpty || (!owner.paths.isEmpty && listed == nil) else { return false }
        guard let commands = Self.userCommandLines() else { return nil }
        return commands.contains { owner.matches($0) }
    }

    /// This checker with the process list read once, for checking many owners together at a scan.
    public func listedOnce() -> SystemRunningAppChecker { SystemRunningAppChecker(processes: ListedProcesses(list: processes.processes())) }

    /// argv of every process the current user owns, or nil when the list can't be read.
    static func userCommandLines() -> [[String]]? { UserProcesses.pids()?.compactMap(UserProcesses.arguments) }
}

/// A process list read once.
struct ListedProcesses: ProcessListing {
    let list: [RunningProcess]?
    func processes() -> [RunningProcess]? { list }
}
