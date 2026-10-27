import Foundation

/// Opens a guidance target. The app uses NSWorkspace; tests pass a fake, so nothing opens.
public protocol GuidanceOpening: Sendable {
    func open(_ target: GuidanceTarget) async -> Bool
}
