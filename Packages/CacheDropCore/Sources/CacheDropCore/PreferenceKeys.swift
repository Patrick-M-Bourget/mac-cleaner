import Foundation

/// The app's preference keys in its defaults domain, and the names they had before #150 renamed them (Still's,
/// also used by CacheDrop's own early builds). The one definition: the app, `RenamedPreferenceKeys` and
/// `LegacyStillMigration` all read it.
public enum PreferenceKeys {
    /// The Settings dry run (Decision 27).
    public static let dryRun = "CacheDropDryRun"
    /// Whether the menu bar item is shown.
    public static let showsMenuBarItem = "CacheDrop.showsMenuBarItem"
    /// The user's choice to start at login.
    public static let startAtLogin = "CacheDrop.startAtLogin"

    /// The login key's former name. Still's own value is never copied: login launch is registered for Still's app.
    static let legacyStartAtLogin = "Still.startAtLogin"
    /// Former name to current name, for every renamed key.
    static let renamed = ["StillDryRun": dryRun, "Still.showsMenuBarItem": showsMenuBarItem, legacyStartAtLogin: startAtLogin]
}
