import Foundation
import Testing
@testable import CacheDropCore

/// No apps are installed: tests never ask LaunchServices about this Mac's apps.
struct FixtureApps: AppLookup {
    func app(bundleID: String) -> InstalledApp? { nil }
    func app(updaterCacheDirName name: String) -> InstalledApp? { nil }
}

/// The built-in catalog with no installed apps.
let fixtureRules = BuiltInCatalog.rules(apps: FixtureApps())

/// Copies are never in use; tests that check use pass their own.
struct FixtureNothingInUse: InUseChecking {
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? { [] }
}

/// For executors whose candidates are deleted, never trashed: the real Trash is never the default.
struct TrashNeverUsed: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL? {
        Issue.record("Nothing should be moved to Trash here: \(url.path)")
        throw CocoaError(.featureUnsupported)
    }
}

extension Catalog {
    /// Discovery as tests run it, reading nothing outside the fixture: the fixture home stands in for the system root,
    /// no tool is installed unless `locateTool` finds a stand-in, there's no user folder unless one is given,
    /// and no copy is in use.
    func discover(fixture home: URL, userFolder: URL? = nil, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = FixtureNothingInUse(),
                  now: Date = Date(), locateTool: (ToolCommand) -> URL? = { _ in nil }, systemRoot: URL? = nil, cloud: any UbiquitousItemAccess = FakeCloud()) -> [Candidate] {
        discovery(fixture: home, userFolder: userFolder, exclusions: exclusions, inUse: inUse, now: now, locateTool: locateTool, systemRoot: systemRoot, cloud: cloud).candidates
    }
    func discovery(fixture home: URL, userFolder: URL? = nil, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = FixtureNothingInUse(),
                   now: Date = Date(), locateTool: (ToolCommand) -> URL? = { _ in nil }, systemRoot: URL? = nil, cloud: any UbiquitousItemAccess = FakeCloud(),
                   access: FullDiskAccessStatus = .granted) -> CatalogDiscovery {
        discovery(home: home, userFolder: userFolder, exclusions: exclusions, inUse: inUse, now: now, locateTool: locateTool, systemRoot: systemRoot ?? home, cloud: cloud,
                  access: access)
    }
}

/// iCloud as tests see it: each fixture path's state is set by the test, so tests never touch real iCloud Drive.
/// Unlisted paths read as unknown. It records every eviction, and whether each read ran with downloads blocked.
final class FakeCloud: UbiquitousItemAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String: CloudMetadata] = [:]
    private var evictedPaths: [String] = []
    private var readsAllowingDownload: [String] = []
    var evictionError: (any Error)?
    init(_ states: [URL: CloudMetadata] = [:]) { for (url, state) in states { self.states[url.path] = state } }
    /// A local copy that is uploaded, settled and not set to Keep Downloaded.
    static let ready = CloudMetadata(membership: true, downloadState: .current, uploaded: true, uploading: false, downloading: false, conflicts: false, pinned: false)
    func set(_ url: URL, _ state: CloudMetadata) { lock.lock(); states[url.path] = state; lock.unlock() }
    var evicted: [String] { lock.lock(); defer { lock.unlock() }; return evictedPaths }
    /// Paths read while the thread could still download a placeholder.
    var downloadableReads: [String] { lock.lock(); defer { lock.unlock() }; return readsAllowingDownload }
    func metadata(_ url: URL) -> CloudMetadata {
        let policy = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        lock.lock(); defer { lock.unlock() }
        if policy != IOPOL_MATERIALIZE_DATALESS_FILES_OFF { readsAllowingDownload.append(url.path) }
        return states[url.path] ?? .unknown
    }
    func evict(_ url: URL) throws {
        if let evictionError { throw evictionError }
        lock.lock(); evictedPaths.append(url.path)
        states[url.path] = states[url.path].map { CloudMetadata(membership: $0.membership, downloadState: .notDownloaded, uploaded: $0.uploaded, uploading: false, downloading: false, conflicts: $0.conflicts, pinned: $0.pinned) }
        lock.unlock()
    }
}

/// Snapshots as tests see them: a fixed count, never this Mac's.
struct FixtureSnapshots: LocalSnapshotListing {
    var snapshots: Int? = 0
    func count() -> Int? { snapshots }
}

extension Catalog {
    /// Guidance sizing as tests run it: the fixture home stands in for the system root, and no snapshots unless given.
    func guidance(fixture home: URL, snapshots: Int? = 0) -> [GuidanceFinding] {
        guidance(home: home, systemRoot: home, snapshots: FixtureSnapshots(snapshots: snapshots))
    }
}

/// A home folder that doesn't exist, for tests whose home doesn't matter: never the real one.
let fixtureNoHome = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropNoHome-\(UUID())")

extension CandidateCheck {
    /// The check as tests run it when the home folder doesn't matter.
    init(catalog: Catalog, running: any RunningAppChecking, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = SystemInUseChecker(),
         cloud: any UbiquitousItemAccess = SystemUbiquitousItems()) {
        self.init(catalog: catalog, running: running, exclusions: exclusions, inUse: inUse, cloud: cloud, home: fixtureNoHome)
    }
}

/// Finds `stand-in` only for the tool named `name` (`brew`, `ollama`), so a test never runs its stand-in as another
/// tool, such as Docker's `system df` during discovery.
func onlyTool(_ name: String, _ standIn: URL) -> @Sendable (ToolCommand) -> URL? {
    { command in command.executables.contains { URL(fileURLWithPath: $0).lastPathComponent == name } ? standIn : nil }
}

/// Waits up to `timeout` for `file` to appear, which a stand-in tool writes to say it reached a point; true once it has.
/// Bounded, so a tool that never gets there fails the test instead of hanging it.
func waitForFile(_ file: URL, timeout: TimeInterval = 10) -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while !FileManager.default.fileExists(atPath: file.path) {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
        usleep(10_000)
    }
    return true
}
