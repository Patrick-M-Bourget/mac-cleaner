import Darwin
import Foundation

/// The quitter of a debug UI test run (#377): it sees only apps run from inside `root`, the run's fixture home, by the
/// bundle identifier of the app bundle each process runs from, and asks only those to quit (SIGTERM, a normal quit request
/// to a process that isn't a Cocoa app). A journey quits a fixture app it started itself, never a real app on this Mac.
public struct FixtureAppQuitter: AppQuitting {
    public let root: URL
    public init(root: URL) { self.root = root }

    public func isOpen(_ bundleIDs: [String]) -> Bool { !processes(bundleIDs).isEmpty }

    public func requestQuit(_ bundleIDs: [String]) -> Bool {
        processes(bundleIDs).map { kill($0, SIGTERM) == 0 }.contains(true)
    }

    public func waitUntilClosed(_ bundleIDs: [String], timeout: Duration) async -> Bool {
        let end = ContinuousClock.now + timeout
        while isOpen(bundleIDs) {
            guard ContinuousClock.now < end else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    /// The current user's processes run from inside an app bundle under `root` with one of these identifiers.
    private func processes(_ bundleIDs: [String]) -> [pid_t] {
        let base = SystemRunningAppChecker.sameForm(root.resolvingSymlinksInPath().path + "/")
        return (UserProcesses.pids() ?? []).filter { pid in
            guard let path = UserProcesses.executablePath(pid).map(SystemRunningAppChecker.sameForm), path.hasPrefix(base),
                  let bundle = Self.enclosingApp(path) else { return false }
            let info = NSDictionary(contentsOfFile: bundle + "/Contents/Info.plist")
            return (info?["CFBundleIdentifier"] as? String).map(bundleIDs.contains) == true
        }
    }

    /// The innermost `.app` folder holding `path`.
    private static func enclosingApp(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let last = parts.dropLast().lastIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return parts[...last].joined(separator: "/")
    }
}
