import Foundation
import Darwin

struct ChromeCacheLeaf {
    let descriptor: Int32; let name: String; let bytes: Int64
}
/// Holds no-follow descriptors; deletion never recurses or follows a cache entry.
final class ChromeOpenGroup {
    let chain: [ChromeDirectory]
    var descriptors: [Int32] = []
    var indexDescriptor: Int32?
    var indexIdentity: ChromeObjectIdentity?
    var cacheFD: Int32 { descriptors.last! }
    init(chain: [ChromeDirectory]) throws {
        self.chain = chain
        do {
            for item in chain {
                let fd = open(item.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard fd >= 0 else { throw ChromeCacheFailure("Cache access is unavailable.", (errno == EACCES || errno == EPERM) ? .denied : .unknown) }
                descriptors.append(fd)
                var info = stat()
                guard fstat(fd, &info) == 0, ChromeObjectIdentity(info) == item.identity,
                      info.st_uid == getuid(), info.st_mode & 0o022 == 0 else { throw ChromeCacheFailure("Cache directory changed.") }
            }
        } catch { for fd in descriptors { close(fd) }; descriptors = []; throw error }
    }
    deinit { for fd in descriptors { close(fd) }; if let indexDescriptor { close(indexDescriptor) } }
    func names(_ fd: Int32) throws -> [String] {
        guard let stream = fdopendir(dup(fd)) else { throw ChromeCacheFailure("Cache directory cannot be read.") }
        defer { closedir(stream) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
            guard names.count <= 10_000 else { throw ChromeCacheFailure("Cache group exceeds this version's supported limit.") }
            errno = 0
        }
        guard errno == 0 else { throw ChromeCacheFailure("Cache directory listing is incomplete.") }
        return names.sorted()
    }
    func leaf(_ fd: Int32, _ name: String) throws -> ChromeCacheLeaf {
        var info = stat()
        guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_flags & UInt32(SF_DATALESS) == 0, info.st_uid == getuid(), info.st_nlink == 1 else {
            throw ChromeCacheFailure("An unexpected or changed cache entry requires a recheck.")
        }
        return .init(descriptor: fd, name: name, bytes: info.st_size)
    }
    func entries() throws -> [ChromeCacheLeaf] {
        var result: [ChromeCacheLeaf] = []
        for name in try names(cacheFD) {
            if name == "index-dir" {
                let fd = openat(cacheFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard fd >= 0 else { throw ChromeCacheFailure("Cache index changed.") }
                indexDescriptor = fd
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else { throw ChromeCacheFailure("Cache index ownership is uncertain.") }
                indexIdentity = .init(info)
                for child in try names(fd) {
                    guard child == "the-real-index" else { throw ChromeCacheFailure("Unsupported cache index contents.") }
                    result.append(try leaf(fd, child))
                }
            } else {
                guard name == "index" || name.range(of: #"^[0-9a-f]{16}_[0-9]+$"#, options: .regularExpression) != nil else {
                    throw ChromeCacheFailure("Unexpected cache contents; cleanup is unavailable.")
                }
                result.append(try leaf(cacheFD, name))
            }
        }
        guard result.count <= 10_000 else { throw ChromeCacheFailure("Cache group exceeds the supported limit.") }
        return result
    }
    func remove(_ entry: ChromeCacheLeaf) throws -> Int64 {
        let current = try directoryChain(chain.map(\.url))
        guard current == chain else { throw ChromeCacheFailure("A cache directory changed during cleanup.") }
        if entry.descriptor != cacheFD {
            var info = stat()
            guard fstatat(cacheFD, "index-dir", &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & S_IFMT == S_IFDIR, ChromeObjectIdentity(info) == indexIdentity else {
                throw ChromeCacheFailure("The cache index changed during cleanup.")
            }
        }
        let verified = try leaf(entry.descriptor, entry.name)
        guard unlinkat(entry.descriptor, entry.name, 0) == 0 else { throw ChromeCacheFailure("A cache entry could not be removed.") }
        return verified.bytes
    }
}
