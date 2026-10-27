import Foundation
import Testing
@testable import CacheDropCore

/// Preferences held in memory, so tests never write to the user's defaults.
private final class Preferences: MigrationPreferences, @unchecked Sendable {
    var values: [String: Any]
    init(_ values: [String: Any] = [:]) { self.values = values }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// #150: a Mac that ran CacheDrop before its keys were renamed keeps its settings.
@Test func settingsSavedUnderTheOldKeysCarryOverAndTheOldValuesStay() {
    let preferences = Preferences(["StillDryRun": true, "Still.showsMenuBarItem": false, "Still.startAtLogin": true])
    RenamedPreferenceKeys(preferences: preferences).run()
    #expect(preferences.object(forKey: "CacheDropDryRun") as? Bool == true)
    #expect(preferences.object(forKey: "CacheDrop.showsMenuBarItem") as? Bool == false)
    #expect(preferences.object(forKey: "CacheDrop.startAtLogin") as? Bool == true)
    #expect(preferences.object(forKey: "StillDryRun") as? Bool == true)
    #expect(preferences.object(forKey: "Still.showsMenuBarItem") as? Bool == false)
    #expect(preferences.object(forKey: "Still.startAtLogin") as? Bool == true)
}

@Test func aValueAlreadySavedUnderTheNewKeyIsNeverOverwritten() {
    let preferences = Preferences(["StillDryRun": true, "CacheDropDryRun": false])
    RenamedPreferenceKeys(preferences: preferences).run()
    #expect(preferences.object(forKey: "CacheDropDryRun") as? Bool == false)
}

@Test func theKeyRenameRunsOnce() {
    let preferences = Preferences(["StillDryRun": true])
    RenamedPreferenceKeys(preferences: preferences).run()
    preferences.set(nil, forKey: "CacheDropDryRun") // the user's later change, such as Reset
    RenamedPreferenceKeys(preferences: preferences).run()
    #expect(preferences.object(forKey: "CacheDropDryRun") == nil)
}
