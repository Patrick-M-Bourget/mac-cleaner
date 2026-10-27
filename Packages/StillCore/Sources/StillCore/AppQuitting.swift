import AppKit
import Foundation

/// The plan's line for an owner that was running at the scan. An open app can be quit from here (#138);
/// a command-line tool isn't an app, so the user quits it and checks again.
public struct RunningOwnerNotice: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// A link button with this title that asks the app to quit, like ⌘Q.
        case quitApp(String)
        case checkAgain
    }
    public let text: String
    public let action: Action
    /// `appOpen`: the owner's app itself is open, not only its command-line tools.
    /// `stillOpen`: the app was asked to quit and is still open (unsaved work, or it refused).
    public init(name: String, appOpen: Bool, stillOpen: Bool = false) {
        if appOpen {
            text = stillOpen ? "\(name) is still open." : "\(name) is running."
            action = .quitApp("Quit \(name)")
        } else {
            text = "Quit \(name) to include this."
            action = .checkAgain
        }
    }
}

/// The one way Still asks an app to quit (SPEC section 2): a normal quit request, like ⌘Q, sent only when the user asks.
/// There is deliberately no force-quit here. The app may ask to save, or refuse.
public protocol AppQuitting: Sendable {
    /// Whether an app with one of these bundle identifiers is open.
    func isOpen(_ bundleIDs: [String]) -> Bool
    /// Sends a normal quit request to each open instance. Returns whether any request was sent.
    func requestQuit(_ bundleIDs: [String]) -> Bool
    /// Waits until none is open, or the timeout passes. Returns whether all of them quit.
    func waitUntilClosed(_ bundleIDs: [String], timeout: Duration) async -> Bool
}

public enum AppQuitOutcome: Sendable, Equatable { case quit, stillOpen, notAnApp }

/// Asks an owner's app to quit and waits a little for it to go.
public struct AppQuitRequest: Sendable {
    public let quitter: any AppQuitting
    public let timeout: Duration
    public init(quitter: any AppQuitting, timeout: Duration = .seconds(15)) { self.quitter = quitter; self.timeout = timeout }

    public func quit(_ owner: RuleOwner) async -> AppQuitOutcome {
        guard !owner.bundleIDs.isEmpty else { return .notAnApp }
        _ = quitter.requestQuit(owner.bundleIDs)
        return await quitter.waitUntilClosed(owner.bundleIDs, timeout: timeout) ? .quit : .stillOpen
    }
}

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
