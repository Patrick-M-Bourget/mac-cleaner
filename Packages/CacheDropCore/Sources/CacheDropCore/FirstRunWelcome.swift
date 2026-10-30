import Foundation

/// The first-run welcome (#158): shown on first launch and again on every launch until it is finished or skipped.
public struct FirstRunWelcome {
    /// CacheDrop's preference recording the welcome: "pending" from the first launch that shows it, "seen" once it is
    /// finished or skipped. Only Skip and Start scan set "seen"; quitting with it open leaves it pending.
    static let stateKey = "CacheDrop.welcomeState"
    static let pending = "pending", seen = "seen"
    let preferences: any MigrationPreferences

    public init(preferences: any MigrationPreferences) { self.preferences = preferences }

    /// `migration` is this launch's `LegacyStillMigration` outcome; `stateExisted` says CacheDrop's state folder was
    /// there before it ran. Those count only the first time, before anything is recorded: someone who used Still
    /// (copied) or CacheDrop already (its state) never sees it. Otherwise "pending" is recorded and it shows.
    public func shouldShow(migration: LegacyStillMigration.Outcome?, stateExisted: Bool) -> Bool {
        switch preferences.object(forKey: Self.stateKey) as? String {
        case Self.seen: return false
        case Self.pending: return true
        default:
            if stateExisted || migration == .copied || migration == .cacheDropHasState { markSeen(); return false }
            preferences.set(Self.pending, forKey: Self.stateKey)
            return true
        }
    }

    public func markSeen() { preferences.set(Self.seen, forKey: Self.stateKey) }
}
