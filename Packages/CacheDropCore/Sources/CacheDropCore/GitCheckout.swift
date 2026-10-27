import Foundation
import Darwin

/// SPEC section 2: a git working tree is live work. Discovery, the explorer and the check all decide it here.
enum GitCheckout {
    /// Whether `folder` holds a `.git` entry: a working tree's top (a folder) or a linked worktree's (a file).
    static func isRoot(_ folder: URL) -> Bool {
        var info = stat()
        return lstat(folder.appendingPathComponent(".git").path, &info) == 0
    }

    /// Whether a folder holding `url` is a checkout's top, from its parent up to and including `top`. With no `top`,
    /// up to the home folder or the root, so a checkout above a picked folder counts too. The home folder itself
    /// never counts: a dotfiles repository there doesn't make Downloads or a picked folder live work.
    static func encloses(_ url: URL, upTo top: URL?, home: URL) -> Bool {
        let homePath = realPath(home.path) ?? home.standardizedFileURL.path
        let topPath = top?.standardizedFileURL.path
        var folder = url.standardizedFileURL.deletingLastPathComponent()
        while topPath.map({ folder.path == $0 || folder.path.hasPrefix($0 + "/") }) ?? true {
            if topPath == nil, folder.path == homePath { return false }
            if folder.path != homePath, isRoot(folder) { return true }
            if folder.path == topPath || folder.path == "/" { return false }
            folder = folder.deletingLastPathComponent()
        }
        return false
    }
}
