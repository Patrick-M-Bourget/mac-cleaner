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
public struct SystemRunningAppChecker: RunningAppChecking {
    public init() {}
    public func isRunning(_ owner: RuleOwner) -> Bool? {
        if !UserProcesses.apps(owner.bundleIDs).isEmpty { return true }
        guard !owner.executables.isEmpty || !owner.scripts.isEmpty || !owner.arguments.isEmpty || !owner.paths.isEmpty else { return false }
        guard let commands = Self.userCommandLines() else { return nil }
        return commands.contains { owner.matches($0) }
    }

    /// argv of every process the current user owns, or nil when the list can't be read.
    static func userCommandLines() -> [[String]]? { UserProcesses.pids()?.compactMap(UserProcesses.arguments) }
}
