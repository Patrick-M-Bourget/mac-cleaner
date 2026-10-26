import Foundation
import Darwin

/// The one way Still walks a folder tree: physically, never following symlinks or crossing volumes.
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
}
