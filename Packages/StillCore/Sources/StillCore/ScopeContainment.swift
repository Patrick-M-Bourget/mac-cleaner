import Foundation
import Darwin

/// SPEC section 4: an item lies inside its base folder (home, or the user's `/private/var/folders` entry), and is
/// reached from it without following a symlink at or below the base. A rule's location may name `~/.cargo/registry`,
/// but a `~/.cargo` symlinked elsewhere doesn't make that folder the user's cache.
enum ScopeContainment {
    /// A descriptor for `url`'s parent folder, opened from `base` one component at a time with `O_NOFOLLOW`,
    /// or -1 when `url` isn't inside `base` that way. The item itself must exist and not be a symlink.
    /// The caller closes the descriptor.
    static func openParent(of url: URL, in base: URL) -> Int32 {
        let baseParts = base.standardizedFileURL.pathComponents, parts = url.standardizedFileURL.pathComponents
        guard parts.starts(with: baseParts), let realBase = realPath(base.path), let realItem = realPath(url.path),
              realItem == realBase || realItem.hasPrefix(realBase == "/" ? "/" : realBase + "/") else { return -1 }
        // A location of "" names the base itself, which is trusted as it is.
        let isBase = parts.count == baseParts.count
        var parent = open(isBase ? (realBase as NSString).deletingLastPathComponent : realBase, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { return -1 }
        let relative = isBase ? [(realBase as NSString).lastPathComponent] : Array(parts.dropFirst(baseParts.count))
        for part in relative.dropLast() {
            guard part != ".", part != ".." else { close(parent); return -1 }
            let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(parent)
            guard next >= 0 else { return -1 }
            parent = next
        }
        var info = stat()
        guard let last = relative.last, last != ".", last != "..",
              fstatat(parent, last, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_mode & S_IFMT != S_IFLNK else { close(parent); return -1 }
        return parent
    }

    static func contains(_ url: URL, in base: URL) -> Bool {
        let parent = openParent(of: url, in: base)
        guard parent >= 0 else { return false }
        close(parent)
        return true
    }
}
