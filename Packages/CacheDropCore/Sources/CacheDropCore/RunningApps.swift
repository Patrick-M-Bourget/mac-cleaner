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

    /// Whether anything running could be this owner: it names an app, a maker, a folder or a command line to look for.
    var looksForProcesses: Bool {
        !bundleIDs.isEmpty || !bundleIDPrefixes.isEmpty || !paths.isEmpty || !executables.isEmpty || !scripts.isEmpty || !arguments.isEmpty
    }
}

/// Whether an owner is running, from one reading of `processes` per check (#261): apps and helpers by bundle ID, a maker
/// (`bundleIDPrefixes`) by every running process, background helpers included (#240), an app's folder by any process run from
/// inside it (#281), and command-line tools by the current user's command lines.
public struct SystemRunningAppChecker: RunningAppChecking {
    let processes: any ProcessListing
    private let makers = RunningMakerCache()
    public init(processes: any ProcessListing = SystemProcessListing()) { self.processes = processes }
    public func isRunning(_ owner: RuleOwner) -> Bool? {
        // Owners with nothing to look for never need the list.
        guard owner.looksForProcesses else { return false }
        guard let listed = processes.processes() else { return nil }
        if listed.contains(where: { process in
            process.bundleID.map(owner.bundleIDs.contains) == true || owner.paths.contains { process.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }) { return true }
        if !owner.bundleIDPrefixes.isEmpty, RunningMakers(listed, resolve: makers.products).runs(owner) { return true }
        return listed.contains { $0.arguments.map(owner.matches) == true }
    }

    /// This checker with the process list read once, for checking many owners together at a scan.
    public func listedOnce() -> SystemRunningAppChecker { SystemRunningAppChecker(processes: ListedProcesses(list: processes.processes())) }
    public func snapshot() -> any RunningAppChecking { listedOnce() }
}

/// A process list read once.
struct ListedProcesses: ProcessListing {
    let list: [RunningProcess]?
    func processes() -> [RunningProcess]? { list }
}
