import Foundation

/// Preliminary observations never authorize cleanup or represent complete coverage.
public enum ScanPhase: String, Sendable { case enumerating, rechecking, checkingDirectories }
public struct ScanProgress: Sendable {
    public let scope: URL
    public let visitedEntries: Int
    public let retainedObservations: Int
    public let knownLogicalSubtotal: Int64
    public let recentObservations: [FileObservation]
    public let elapsed: TimeInterval
    public let phase: ScanPhase
    public var isComplete: Bool { false }
}

/// Cancellation requests are synchronous, independent of the scanner's serial actor.
/// A currently blocked OS metadata call still has to return before work can stop.
public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    public init() {}
    public func cancel() { lock.lock(); requested = true; lock.unlock() }
    public var isCancellationRequested: Bool { lock.lock(); defer { lock.unlock() }; return requested }
}
