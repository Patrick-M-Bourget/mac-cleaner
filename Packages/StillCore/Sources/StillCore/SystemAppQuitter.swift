import AppKit
import Foundation

/// Apps through `NSRunningApplication`: `terminate()`, never `forceTerminate()`.
public struct SystemAppQuitter: AppQuitting {
    /// With `sendsRequests` off (debug UI tests), nothing is ever asked to quit, so a test can never quit a real app.
    public let sendsRequests: Bool
    public init(sendsRequests: Bool = true) { self.sendsRequests = sendsRequests }

    public func isOpen(_ bundleIDs: [String]) -> Bool { !Self.open(bundleIDs).isEmpty }

    public func requestQuit(_ bundleIDs: [String]) -> Bool {
        guard sendsRequests else { return false }
        return Self.open(bundleIDs).map { $0.terminate() }.contains(true)
    }

    /// Wakes on each `didTerminateApplicationNotification`; the timeout covers an app that waits on a save dialog or refuses.
    public func waitUntilClosed(_ bundleIDs: [String], timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                // Listening starts before the first look, so a quit in between is never missed.
                let terminations = NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didTerminateApplicationNotification)
                if !isOpen(bundleIDs) { return true }
                for await _ in terminations where !isOpen(bundleIDs) { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return !isOpen(bundleIDs)
            }
            let closed = await group.next() ?? false
            group.cancelAll()
            return closed
        }
    }

    private static func open(_ bundleIDs: [String]) -> [NSRunningApplication] {
        UserProcesses.apps(bundleIDs).filter { !$0.isTerminated }
    }
}
