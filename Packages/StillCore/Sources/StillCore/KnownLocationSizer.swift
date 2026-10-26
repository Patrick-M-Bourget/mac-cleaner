import Foundation
import Darwin

public struct ItemSize: Sendable, Equatable {
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    public let entries: Int
    /// False when the time budget ran out or part of the tree was unreadable; sizes are then lower bounds.
    public let complete: Bool
}

/// Sizes one known location without FolderScanner's entry cap. Never follows symlinks or crosses volumes.
public struct KnownLocationSizer: Sendable {
    public let timeBudget: TimeInterval
    public init(timeBudget: TimeInterval = 60) { self.timeBudget = timeBudget }
    public func size(_ url: URL) -> ItemSize {
        let deadline = ProcessInfo.processInfo.systemUptime + timeBudget
        var logical: Int64 = 0, allocated: Int64 = 0, entries = 0, complete = true
        var linked = Set<String>()
        let path = strdup(url.path)
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            return ItemSize(logicalBytes: 0, allocatedBytes: nil, entries: 0, complete: false)
        }
        defer { fts_close(tree) }
        while let entry = fts_read(tree) {
            switch Int32(entry.pointee.fts_info) {
            case FTS_DNR, FTS_ERR, FTS_NS: complete = false; continue
            case FTS_DP: continue
            default: break
            }
            guard let info = entry.pointee.fts_statp?.pointee else { complete = false; continue }
            entries += 1
            if entries % 1024 == 0, ProcessInfo.processInfo.systemUptime > deadline { complete = false; break }
            if info.st_mode & S_IFMT != S_IFDIR, info.st_nlink > 1, !linked.insert(info.resourceID).inserted { continue }
            if info.st_mode & S_IFMT == S_IFREG { logical += Int64(info.st_size) }
            allocated += Int64(info.st_blocks) * 512
        }
        return ItemSize(logicalBytes: logical, allocatedBytes: allocated, entries: entries, complete: complete)
    }
}
