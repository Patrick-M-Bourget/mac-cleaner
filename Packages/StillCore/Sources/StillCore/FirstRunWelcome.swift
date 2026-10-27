import Foundation

/// The first-run welcome (#158): shown once, until it is finished or skipped.
public struct FirstRunWelcome {
    /// Recorded in CacheDrop's preferences once the welcome is finished or skipped.
    public static let seenKey = "CacheDrop.hasSeenWelcome"
    let preferences: any MigrationPreferences

    public init(preferences: any MigrationPreferences) { self.preferences = preferences }

    /// `migration` is this launch's `LegacyStillMigration` outcome; `stateExisted` says CacheDrop's state folder was
    /// there before it ran. Someone who used Still (copied) or CacheDrop already (its state) counts as having seen it,
    /// and that is recorded so it holds on later launches.
    public func shouldShow(migration: LegacyStillMigration.Outcome?, stateExisted: Bool) -> Bool {
        if preferences.object(forKey: Self.seenKey) as? Bool == true { return false }
        if stateExisted || migration == .copied || migration == .cacheDropHasState { markSeen(); return false }
        return true
    }

    public func markSeen() { preferences.set(true, forKey: Self.seenKey) }
}
