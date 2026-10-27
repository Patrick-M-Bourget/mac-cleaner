import Foundation
import Darwin

/// The one way CacheDrop walks a folder tree: physically, never following symlinks or crossing volumes.
enum FileTree {
    /// What the walk does after an entry.
    enum Next { case `continue`, skip, stop }

    /// Calls `visit` for `root` and each entry under it, folders again after their contents (`FTS_DP`).
    /// `.skip` on a folder leaves its contents out. False when `root` couldn't be opened.
    @discardableResult
    static func walk(_ root: URL, _ visit: (UnsafeMutablePointer<FTSENT>) -> Next) -> Bool {
        let path = strdup(root.path)
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return false }
        defer { fts_close(tree) }
        while let entry = fts_read(tree) {
            switch visit(entry) {
            case .continue: break
            case .skip: fts_set(tree, entry, FTS_SKIP)
            case .stop: return true
            }
        }
        return true
    }

    /// How `entries(below:limit:_:)` ended.
    enum Ending: Equatable { case finished, stopped, unreadable, tooLarge }
    /// Calls `visit` with the path and kind (folder or not) of each entry below `root`, until it returns true (#291). Any folder
    /// that can't be read ends it as `unreadable`, at any depth, so nothing below is taken as checked; so does a root that can't
    /// be opened. More than `limit` entries end it as `tooLarge`.
    static func entries(below root: String, limit: Int, _ visit: (_ path: String, _ isFolder: Bool) -> Bool) -> Ending {
        var ending = Ending.finished, seen = 0
        let opened = walk(URL(fileURLWithPath: root)) { entry in
            let kind = Int32(entry.pointee.fts_info)
            if kind == FTS_DNR || kind == FTS_ERR || kind == FTS_NS { ending = .unreadable; return .stop }
            guard entry.pointee.fts_level > 0, kind != FTS_DP else { return .continue }
            seen += 1
            if seen > limit { ending = .tooLarge; return .stop }
            if visit(String(cString: entry.pointee.fts_path), kind == FTS_D) { ending = .stopped; return .stop }
            return .continue
        }
        return opened ? ending : .unreadable
    }
}
