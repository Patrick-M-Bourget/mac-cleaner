import Foundation
import SQLite3

/// The preferences store the migration reads and writes; `UserDefaults` in the app, memory in tests.
public protocol MigrationPreferences: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: MigrationPreferences {}

/// One-time copy of Still's state and preferences into CacheDrop's (#149). Still was the app's former name.
/// Copies, never moves: Still's data stays where it is. Runs only while CacheDrop has no state, never overwrites,
/// and leaves everything as it was on any failure, so a failed copy is tried again on the next launch.
public struct LegacyStillMigration {
    public enum Outcome: Equatable, Sendable {
        /// Still's state and preferences were copied.
        case copied
        /// An earlier launch already recorded the migration.
        case alreadyDone
        /// CacheDrop already has state of its own, so nothing was copied.
        case cacheDropHasState
        /// Still left nothing to copy.
        case nothingToCopy
        /// Still is running, or that couldn't be checked: its journal may be mid-write. Nothing was recorded (#151).
        case stillRunning
        /// The copy failed; nothing was recorded or changed.
        case failed
    }

    public static let folder = "CacheDrop"
    public static let legacyFolder = "Still"
    public static let legacyDomain = "com.patrickbourget.Still"
    /// Still's cleanup journal, copied through SQLite's backup API rather than as files (#151).
    static let journal = "cleanup.sqlite"
    /// Recorded in CacheDrop's preferences once the migration is done.
    public static let completedKey = "CacheDrop.migratedFromStill"
    /// Login launch is registered with macOS for Still's app, not CacheDrop's, so its intent isn't carried over.
    static let skippedKeys: Set<String> = ["Still.startAtLogin"]
    /// Still's preference keys that CacheDrop renamed (#150), copied under CacheDrop's names. Must match the app's keys.
    static let renamedKeys = ["StillDryRun": "CacheDropDryRun", "Still.showsMenuBarItem": "CacheDrop.showsMenuBarItem"]

    let applicationSupport: URL
    let fileManager: FileManager
    let preferences: any MigrationPreferences
    let legacyPreferences: () -> [String: Any]?
    let running: any RunningAppChecking

    /// `applicationSupport` holds both apps' state folders; `legacyPreferences` reads Still's defaults domain.
    public init(applicationSupport: URL, fileManager: FileManager = .default, preferences: any MigrationPreferences,
                legacyPreferences: @escaping () -> [String: Any]?, running: any RunningAppChecking = SystemRunningAppChecker()) {
        self.applicationSupport = applicationSupport
        self.fileManager = fileManager
        self.preferences = preferences
        self.legacyPreferences = legacyPreferences
        self.running = running
    }

    @discardableResult public func run() -> Outcome {
        if preferences.object(forKey: Self.completedKey) as? Bool == true { return .alreadyDone }
        let target = applicationSupport.appendingPathComponent(Self.folder, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(Self.legacyFolder, isDirectory: true)
        if exists(target) { return record(.cacheDropHasState) }
        let legacyIsFolder = isRealFolder(legacy)
        let values = (legacyPreferences() ?? [:]).filter { !Self.skippedKeys.contains($0.key) && $0.key != Self.completedKey }
        if !legacyIsFolder && values.isEmpty { return record(.nothingToCopy) }
        guard running.isRunning(RuleOwner(name: Self.legacyFolder, bundleIDs: [Self.legacyDomain])) == false else { return .stillRunning }
        if legacyIsFolder {
            // Copied beside the target first and renamed into place, so CacheDrop never sees a partial copy.
            let staging = applicationSupport.appendingPathComponent(".\(Self.folder)-migration-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.copyItem(at: legacy, to: staging)
                try copyJournal(from: legacy, into: staging)
                try fileManager.moveItem(at: staging, to: target)
            } catch {
                try? fileManager.removeItem(at: staging)
                return .failed
            }
        }
        for (legacyKey, value) in values {
            let key = Self.renamedKeys[legacyKey] ?? legacyKey
            if preferences.object(forKey: key) == nil { preferences.set(value, forKey: key) }
        }
        return record(.copied)
    }

    /// Replaces the file copy of the journal with a consistent one: SQLite's backup API reads every committed
    /// record, those still in the write-ahead log included, under SQLite's own locking.
    private func copyJournal(from legacy: URL, into staging: URL) throws {
        // SQLite's no-follow open refuses a link anywhere in the path, so both folders are resolved first;
        // `run` has already refused a linked Still folder.
        guard let legacyPath = realPath(legacy.path), let stagingPath = realPath(staging.path) else { throw CocoaError(.fileReadInvalidFileName) }
        let source = URL(fileURLWithPath: legacyPath).appendingPathComponent(Self.journal)
        guard exists(source) else { return }
        let target = URL(fileURLWithPath: stagingPath).appendingPathComponent(Self.journal)
        for suffix in ["", "-wal", "-shm", "-journal"] where exists(URL(fileURLWithPath: target.path + suffix)) {
            try fileManager.removeItem(at: URL(fileURLWithPath: target.path + suffix))
        }
        var from: OpaquePointer?, to: OpaquePointer?
        defer { sqlite3_close(from); sqlite3_close(to) }
        guard sqlite3_open_v2(source.path, &from, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
              sqlite3_open_v2(target.path, &to, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(to, "main", from, "main") else { throw CocoaError(.fileReadCorruptFile) }
        let step = sqlite3_backup_step(backup, -1)
        guard sqlite3_backup_finish(backup) == SQLITE_OK, step == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
        // The copy keeps Still's WAL mode in its header, but a read-only open (recovery at launch) needs the `-shm`
        // file a WAL database keeps, so the copy is left as a plain file; CacheDrop's writer turns WAL back on.
        guard sqlite3_exec(to, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        guard chmod(target.path, 0o600) == 0 else { throw CocoaError(.fileWriteNoPermission) }
    }

    private func record(_ outcome: Outcome) -> Outcome {
        preferences.set(true, forKey: Self.completedKey)
        return outcome
    }

    private func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// A folder, not a link to one: a link could point anywhere.
    private func isRealFolder(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }
}
