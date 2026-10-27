import Foundation

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
        /// The copy failed; nothing was recorded or changed.
        case failed
    }

    public static let folder = "CacheDrop"
    public static let legacyFolder = "Still"
    public static let legacyDomain = "com.patrickbourget.Still"
    /// Recorded in CacheDrop's preferences once the migration is done.
    public static let completedKey = "CacheDrop.migratedFromStill"
    /// Login launch is registered with macOS for Still's app, not CacheDrop's, so its intent isn't carried over.
    static let skippedKeys: Set<String> = ["Still.startAtLogin"]

    let applicationSupport: URL
    let fileManager: FileManager
    let preferences: any MigrationPreferences
    let legacyPreferences: () -> [String: Any]?

    /// `applicationSupport` holds both apps' state folders; `legacyPreferences` reads Still's defaults domain.
    public init(applicationSupport: URL, fileManager: FileManager = .default, preferences: any MigrationPreferences,
                legacyPreferences: @escaping () -> [String: Any]?) {
        self.applicationSupport = applicationSupport
        self.fileManager = fileManager
        self.preferences = preferences
        self.legacyPreferences = legacyPreferences
    }

    @discardableResult public func run() -> Outcome {
        if preferences.object(forKey: Self.completedKey) as? Bool == true { return .alreadyDone }
        let target = applicationSupport.appendingPathComponent(Self.folder, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(Self.legacyFolder, isDirectory: true)
        if exists(target) { return record(.cacheDropHasState) }
        let legacyIsFolder = isRealFolder(legacy)
        let values = (legacyPreferences() ?? [:]).filter { !Self.skippedKeys.contains($0.key) && $0.key != Self.completedKey }
        if !legacyIsFolder && values.isEmpty { return record(.nothingToCopy) }
        if legacyIsFolder {
            // Copied beside the target first and renamed into place, so CacheDrop never sees a partial copy.
            let staging = applicationSupport.appendingPathComponent(".\(Self.folder)-migration-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.copyItem(at: legacy, to: staging)
                try fileManager.moveItem(at: staging, to: target)
            } catch {
                try? fileManager.removeItem(at: staging)
                return .failed
            }
        }
        for (key, value) in values where preferences.object(forKey: key) == nil { preferences.set(value, forKey: key) }
        return record(.copied)
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
