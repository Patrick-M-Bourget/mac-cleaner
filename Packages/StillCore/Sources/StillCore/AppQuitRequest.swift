import AppKit
import Foundation

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
