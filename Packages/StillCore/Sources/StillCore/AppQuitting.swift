import AppKit
import Foundation

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
