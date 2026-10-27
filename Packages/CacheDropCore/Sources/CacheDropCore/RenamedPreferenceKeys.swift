import Foundation

/// One-time copy, inside CacheDrop's own defaults domain, of settings saved under the keys CacheDrop used before #150
/// renamed them. A new key that already has a value is never overwritten, and the old values are kept.
public struct RenamedPreferenceKeys {
    /// Recorded once the copy is done, so it runs once.
    public static let completedKey = "CacheDrop.renamedPreferenceKeys"

    let preferences: any MigrationPreferences

    public init(preferences: any MigrationPreferences) { self.preferences = preferences }

    public func run() {
        if preferences.object(forKey: Self.completedKey) as? Bool == true { return }
        for (old, new) in PreferenceKeys.renamed where preferences.object(forKey: new) == nil {
            if let value = preferences.object(forKey: old) { preferences.set(value, forKey: new) }
        }
        preferences.set(true, forKey: Self.completedKey)
    }
}
