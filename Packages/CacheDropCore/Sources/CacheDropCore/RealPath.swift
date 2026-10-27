import Foundation
import Darwin

/// The canonical path, as the kernel reports it; Foundation's `resolvingSymlinksInPath` drops `/private`.
func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}
