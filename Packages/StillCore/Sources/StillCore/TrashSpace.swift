import Foundation
import Darwin

/// What the Finder Trash holds. Unknown is never shown as 0 (SPEC section 1).
public enum TrashContents: Equatable, Sendable {
    case empty
    case holds(Int64)
    case unknown
}

/// The Finder Trash, sized read-only. Still never empties the Trash or deletes anything from it (SPEC section 2):
/// this only reads it, and `Protection` keeps every rule and the check away from it.
public enum TrashSpace {
    /// The user's Trash folder in `home`.
    public static func folder(home: URL) -> URL { home.appendingPathComponent(".Trash", isDirectory: true) }

    /// The space the Trash's items use, from allocated size. A Trash that can't be read in full is unknown.
    public static func measure(home: URL, sizer: KnownLocationSizer = KnownLocationSizer(timeBudget: 30)) -> TrashContents {
        let folder = folder(home: home)
        var info = stat()
        guard lstat(folder.path, &info) == 0 else { return errno == ENOENT ? .empty : .unknown }
        guard info.st_mode & S_IFMT == S_IFDIR, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return .unknown }
        // Finder's own bookkeeping files don't make the Trash non-empty.
        guard names.contains(where: { $0 != ".DS_Store" && $0 != ".localized" }) else { return .empty }
        let size = sizer.size(folder)
        guard size.complete, let bytes = size.allocatedBytes else { return .unknown }
        return bytes > 0 ? .holds(bytes) : .empty
    }
}

/// Opens the Trash folder in Finder. The app uses NSWorkspace; tests pass a fake, so nothing opens.
public protocol TrashOpening: Sendable {
    func open(_ folder: URL) -> Bool
}

extension TrashSpace {
    /// Opens `home`'s Trash folder. Only ever opens it; emptying the Trash is left to Finder.
    @discardableResult
    public static func open(home: URL, with opener: any TrashOpening) -> Bool { opener.open(folder(home: home)) }
}

extension TrashContents {
    /// Overview's quiet line, e.g. "Trash holds 2.4 GB"; nil when the Trash is empty or can't be read. Without Full Disk
    /// Access the Trash is usually unreadable, so an unknown line would be permanent noise (Decision 25).
    public var overviewText: String? {
        guard case .holds(let bytes) = self else { return nil }
        return "Trash holds " + Self.bytes(bytes)
    }
    /// The results line after a run moved `movedBytes` to the Trash; nil when it moved nothing. With the Trash
    /// unreadable, what the run moved is a lower bound.
    public func emptyHint(movedBytes: Int64) -> String? {
        guard movedBytes > 0 else { return nil }
        if case .holds(let bytes) = self { return "Empty the Trash in Finder to free " + Self.bytes(bytes) }
        return "Empty the Trash in Finder to free at least " + Self.bytes(movedBytes)
    }
    private static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
}
