import Foundation

/// One-time copy, inside CacheDrop's own defaults domain, of settings saved under the keys CacheDrop used before #150
/// renamed them. A new key that already has a value is never overwritten, and the old values are kept.
public struct RenamedPreferenceKeys {
    /// Old key to new key. Must match the app's keys.
    static let renamed = ["StillDryRun": "CacheDropDryRun", "Still.showsMenuBarItem": "CacheDrop.showsMenuBarItem",
                          "Still.startAtLogin": "CacheDrop.startAtLogin"]
    /// Recorded once the copy is done, so it runs once.
    public static let completedKey = "CacheDrop.renamedPreferenceKeys"

    let preferences: any MigrationPreferences

    public init(preferences: any MigrationPreferences) { self.preferences = preferences }

    public func run() {
        if preferences.object(forKey: Self.completedKey) as? Bool == true { return }
        for (old, new) in Self.renamed where preferences.object(forKey: new) == nil {
            if let value = preferences.object(forKey: old) { preferences.set(value, forKey: new) }
        }
        preferences.set(true, forKey: Self.completedKey)
    }
}
