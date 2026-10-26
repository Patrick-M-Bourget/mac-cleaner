import Foundation
import Darwin

private let xcodeJournalLimit = 20_000_000
final class XcodeJournalLease {
    let fd: Int32
    init(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        _ = try xcodeChain(parent)
        fd = open(parent.appendingPathComponent(".xcode-intermediate-lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw XcodeIntermediateFailure("Cleanup records cannot be locked.") }
        var s = stat()
        guard fstat(fd, &s) == 0, s.st_mode & S_IFMT == S_IFREG, s.st_uid == getuid(), s.st_nlink == 1,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw XcodeIntermediateFailure("Cleanup records are unsafe or another operation owns them.") }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
}
extension XcodeIntermediates {
    public func records() throws -> [XcodeRun] {
        _ = try xcodeChain(journalURL.deletingLastPathComponent())
        var info = stat()
        if lstat(journalURL.path, &info) != 0 {
            if errno == ENOENT { return [] }
            throw XcodeIntermediateFailure("Cleanup records are unreadable.")
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1, info.st_size <= xcodeJournalLimit else { throw XcodeIntermediateFailure("Cleanup records are unsafe or too large.") }
        let fd = open(journalURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw XcodeIntermediateFailure("Cleanup records cannot be opened.") }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, XcodeFingerprint(opened) == XcodeFingerprint(info) else { throw XcodeIntermediateFailure("Cleanup records changed.") }
        let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: xcodeJournalLimit + 1) ?? Data()
        guard data.count <= xcodeJournalLimit else { throw XcodeIntermediateFailure("Cleanup record limit reached.") }
        return try JSONDecoder().decode([XcodeRun].self, from: data)
    }
    func persistXcode(_ runs: [XcodeRun]) throws {
        let parent = journalURL.deletingLastPathComponent()
        _ = try xcodeChain(parent)
        var previous = stat()
        if lstat(journalURL.path, &previous) == 0 {
            guard previous.st_mode & S_IFMT == S_IFREG, previous.st_uid == getuid(), previous.st_nlink == 1 else { throw XcodeIntermediateFailure("Cleanup record destination changed.") }
        } else if errno != ENOENT { throw XcodeIntermediateFailure("Cleanup record destination is unavailable.") }
        let data = try JSONEncoder().encode(runs)
        guard data.count <= xcodeJournalLimit else { throw XcodeIntermediateFailure("Cleanup record limit reached.") }
        let temp = parent.appendingPathComponent(".xcode-intermediate-" + UUID().uuidString)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw XcodeIntermediateFailure("Cleanup intent cannot be saved.") }
        defer { close(fd); unlink(temp.path) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(fd) == 0, rename(temp.path, journalURL.path) == 0 else { throw XcodeIntermediateFailure("Cleanup records cannot be committed.") }
        let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw XcodeIntermediateFailure("Cleanup record directory is unavailable.") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw XcodeIntermediateFailure("Cleanup record directory cannot be synced.") }
    }
}
