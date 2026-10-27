import Foundation

/// Counts Time Machine local snapshots. nil means they couldn't be listed.
public protocol LocalSnapshotListing: Sendable {
    func count() -> Int?
}
