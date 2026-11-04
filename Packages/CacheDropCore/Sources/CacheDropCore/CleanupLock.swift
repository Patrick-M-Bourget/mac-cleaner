import Foundation
import Darwin

/// One cleanup at a time across processes (#627): the app and `cachedrop clean` each hold this lock around a cleanup, from
/// before reading the journal for unfinished runs until the run ends, and the app's recovery review takes it to read the
/// journal, so a run going on in the other process never shows as interrupted. An advisory `flock` on `cleanup.lock` in the
/// app's state folder; macOS releases it when the holder exits, even after a crash, so it never outlives a run.
public final class CleanupLock: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { release() }

    /// The lock on `url`, created if needed; nil while another holder has it. `flock` locks belong to each `open`, so
    /// a second acquisition in the same process waits its turn too. Throws when the file can't be opened.
    public static func acquire(at url: URL) throws -> CleanupLock? {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK { return nil }
            throw CocoaError(.fileReadNoPermission)
        }
        return CleanupLock(descriptor: descriptor)
    }

    /// The app's lock, in its state folder beside the journal, creating the folder if needed.
    public static func acquire() throws -> CleanupLock? {
        try acquire(at: LocalStateLocation.root(create: true).appendingPathComponent(LocalStateLocation.cleanupLockName))
    }

    /// For reading the journal without starting a cleanup: `busy` while a cleanup holds the lock; otherwise the lock, held
    /// so none starts during the read, or nil when there's no state folder yet (so no journal) or the lock can't be opened.
    public enum Reading { case busy, free(CleanupLock?) }
    public static func forReading() -> Reading {
        guard let root = try? LocalStateLocation.root(create: false), FileManager.default.fileExists(atPath: root.path) else { return .free(nil) }
        do { return try acquire(at: root.appendingPathComponent(LocalStateLocation.cleanupLockName)).map { .free($0) } ?? .busy }
        catch { return .free(nil) }
    }

    /// Lets the next cleanup start. Safe to call more than once.
    public func release() {
        lock.lock(); defer { lock.unlock() }
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1
    }
}
