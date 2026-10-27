import Foundation

/// What Still could see of a guidance category. Unknown is never 0 (SPEC section 1).
public enum GuidanceSize: Sendable, Equatable {
    case estimate(SizeEstimate)
    /// macOS didn't let Still read it, usually because it needs Full Disk Access.
    case notAccessible
    /// Couldn't be read for a reason Full Disk Access doesn't change, such as `tmutil` failing.
    case unavailable
    /// Time Machine local snapshots: how many, size unknown.
    case snapshots(Int)
}
