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

/// Runs blocking `work` on a thread of its own and waits for it without holding a Swift concurrency thread.
/// A test that waits seconds on a real tool must not block the pool: under LIBDISPATCH_COOPERATIVE_POOL_STRICT=1
/// it can be a single thread, and every other async test in the run would wait behind it.
/// Keep `#expect` out of `work`; check what it returns instead.
func onOwnThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        Thread { continuation.resume(with: Result { try work() }) }.start()
    }
}

/// Cancels `cancellation` once `file` appears, which a stand-in tool writes to say it reached a point, marking `at` first.
/// It watches on a thread of its own, never GCD's global queues or the Swift concurrency pool: on a runner with few cores,
/// tests blocked in a tool run can fill both, so a watcher queued there may start only after the tool has finished.
/// It has no time limit of its own, which a slow runner may outlast; the tool's time limit bounds the test,
/// and `stop()` (deferred by the test) ends the watch.
final class CancelWhenFileAppears: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    init(_ file: URL, cancel cancellation: CleanupCancellation, at: CancelTime? = nil) {
        let thread = Thread { [self] in
            while !isStopped {
                if FileManager.default.fileExists(atPath: file.path) { at?.mark(); cancellation.cancel(); return }
                usleep(10_000)
            }
        }
        thread.start()
    }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func stop() { lock.lock(); stopped = true; lock.unlock() }
}

/// When a test cancelled, so a stop is timed from the cancel rather than from a start a busy test run may delay.
final class CancelTime: @unchecked Sendable {
    private let lock = NSLock()
    private var at: TimeInterval?
    func mark() { lock.lock(); at = ProcessInfo.processInfo.systemUptime; lock.unlock() }
    /// Seconds since the cancel. A cancel that never fired fails the test, and reads as forever so no time bound passes.
    var elapsed: TimeInterval {
        lock.lock(); let at = self.at; lock.unlock()
        guard let at else { Issue.record("The cancel never fired"); return .infinity }
        return ProcessInfo.processInfo.systemUptime - at
    }
}

/// How long the processes whose command line carries `marker` lived: from the first time one is seen until none is left,
/// timed on a thread of its own. A busy test run can delay a test by many seconds before and after its tool runs;
/// this times only the tool, so a time-limit check measures the limit rather than the runner.
final class MarkedProcessLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let marker: String
    private var firstSeen: TimeInterval?, gone: TimeInterval?, stopped = false
    init(_ marker: String) {
        self.marker = marker
        Thread { [self] in
            while true {
                lock.lock(); let done = stopped || gone != nil; lock.unlock()
                if done { return }
                observe(); usleep(10_000)
            }
        }.start()
    }
    private func observe() {
        let alive = !survivors(marker).isEmpty, now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if alive, firstSeen == nil { firstSeen = now } else if !alive, firstSeen != nil, gone == nil { gone = now }
        lock.unlock()
    }
    /// Seconds the processes lived. Ones never seen, or still running, fail the test and read as forever.
    var seconds: TimeInterval {
        observe()
        lock.lock(); stopped = true; let (firstSeen, gone) = (self.firstSeen, self.gone); lock.unlock()
        guard let firstSeen, let gone else { Issue.record("The tool's processes were never seen, or are still running"); return .infinity }
        return gone - firstSeen
    }
}
