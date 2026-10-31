import Foundation
import Darwin
import CacheDropCore

/// The app's side of its local state; `root(create:)` is in CacheDropCore so the Smart clean report reads the same folder.
extension LocalStateLocation {
    static var isDisposableTest: Bool {
        #if DEBUG
        let env = fixtureEnvironment
        return env["CACHEDROP_TEST_STATE_ROOT"] != nil || env["CACHEDROP_TEST_STATE_ID"] != nil
        #else
        return false
        #endif
    }
    static func removeKnownFile(_ relative: String) throws {
        let root = try root(create: false)
        let file = root.appendingPathComponent(relative)
        guard file.standardizedFileURL.path.hasPrefix(root.path + "/"), !relative.contains("..") else { throw CocoaError(.fileWriteNoPermission) }
        var info = stat()
        if lstat(file.path, &info) != 0 { if errno == ENOENT { return }; throw CocoaError(.fileWriteUnknown) }
        guard info.st_mode & S_IFMT == S_IFREG, file.path == file.resolvingSymlinksInPath().path, info.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: file)
    }
    /// Carries settings over from the app's former names, once: values this Mac saved under CacheDrop's pre-#150
    /// keys move to the new keys (`RenamedPreferenceKeys`), then Still's state and preferences are copied into
    /// CacheDrop's on the first launch after the rename (#149).
    /// Never in a disposable test run, which must not read the user's real state.
    /// Returns nil when it didn't run.
    @discardableResult static func migrateFromOldNames() -> LegacyStillMigration.Outcome? {
        guard !isDisposableTest else { return nil }
        // Settings this Mac saved under CacheDrop's pre-#150 keys move to the new keys first.
        RenamedPreferenceKeys(preferences: UserDefaults.standard).run()
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        return LegacyStillMigration(applicationSupport: support, preferences: UserDefaults.standard,
                             legacyPreferences: { UserDefaults.standard.persistentDomain(forName: LegacyStillMigration.legacyDomain) }).run()
    }
    /// CacheDrop's own state folder is there, as after an earlier launch (#158). False in a disposable test run.
    static var stateFolderExists: Bool {
        guard !isDisposableTest, let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return false }
        var info = stat()
        return lstat(support.appendingPathComponent(LegacyStillMigration.folder).path, &info) == 0
    }
}

/// Local app-owned journal location; recovery opens existing storage only.
enum CleanupJournalLocation {
    static func writer() throws -> SQLiteCleanupJournal {
        try SQLiteCleanupJournal(url: LocalStateLocation.root(create: true).appendingPathComponent("cleanup.sqlite"))
    }
    static func existingReader() throws -> SQLiteCleanupJournal? {
        let url = try LocalStateLocation.root(create: false).appendingPathComponent("cleanup.sqlite")
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw CleanupJournalError.unavailable
        }
        return try SQLiteCleanupJournal(url: url, readOnly: true)
    }

}
