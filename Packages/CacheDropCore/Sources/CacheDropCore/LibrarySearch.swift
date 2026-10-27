import Foundation
import Darwin

/// A library package an app manages, such as a Photos library (#180) or a Final Cut Pro library (#178). Found by its
/// name only; nothing inside it is read, beyond sizing it from metadata. Guidance only: never offered.
public struct FoundLibrary: Sendable, Equatable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    /// The volume it is on: a connected volume's name, or this Mac's startup volume.
    public let volume: String
    public let size: SizeEstimate
    /// "Trip 2019" for `Trip 2019.photoslibrary`.
    public var name: String { url.deletingPathExtension().lastPathComponent }

    /// "3 libraries · Macintosh HD, External": how many, and their volumes in the order found. A volume the search had to
    /// abandon (#244) is named after them: "· NAS not searched".
    public static func summary(_ libraries: [FoundLibrary], notSearched: [String] = []) -> String {
        var volumes: [String] = []
        for library in libraries where !volumes.contains(library.volume) { volumes.append(library.volume) }
        let found = (libraries.count == 1 ? "1 library" : "\(libraries.count) libraries") + " · " + volumes.joined(separator: ", ")
        return notSearched.isEmpty ? found : found + " · " + notSearched.joined(separator: ", ") + " not searched"
    }
}

/// How the library search reaches each volume (#244): whether a volume is local, and the walk of one root. Tests stand in a
/// slow reader and network flags here, so they never touch a real volume.
struct LibraryVolumes: Sendable {
    /// False for a network volume, which is never searched.
    var isLocal: @Sendable (URL) -> Bool
    /// Walks one root's tree, as `FileTree.walk` does.
    var walk: @Sendable (URL, (UnsafeMutablePointer<FTSENT>) -> FileTree.Next) -> Bool

    /// This Mac's volumes. Local is read from the kernel's mount table without waiting on any file system
    /// (`getfsstat` with `MNT_NOWAIT`, the flag `volumeIsLocalKey` reports), so a dropped share can't hang the check itself.
    /// A folder under `/Volumes` that isn't a mount point is on the startup volume, so local.
    static let system = LibraryVolumes(isLocal: { url in
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return true }
        var mounts: [statfs] = Array(repeating: .init(), count: Int(count))
        let read = getfsstat(&mounts, Int32(MemoryLayout<statfs>.stride * mounts.count), MNT_NOWAIT)
        let path = url.standardizedFileURL.path
        for var mount in mounts.prefix(Int(max(read, 0))) {
            let mountedOn = withUnsafeBytes(of: &mount.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            if mountedOn == path { return mount.f_flags & UInt32(MNT_LOCAL) != 0 }
        }
        return true
    }, walk: { FileTree.walk($0, $1) })
}

/// Finds library packages by extension in the home folder and on every local volume connected under `/Volumes`.
enum LibrarySearch {
    /// Folders this deep under a root aren't searched, so a large home stays quick.
    static let maxDepth = 6

    /// The packages with each extension, never entering one. Skips `~/Library` (apps' own data), hidden folders and apps.
    /// Each root is searched on its own thread, all within the sizer's time budget; a root whose walk hasn't returned by
    /// then, such as a hung share, is abandoned and named in `notSearched` (#244). Network volumes are skipped.
    /// `complete` is false when the time budget ran out before every root was searched.
    static func find(extensions: Set<String>, home: URL, systemRoot: URL, sizer: KnownLocationSizer,
                     volumes access: LibraryVolumes = .system) -> (found: [String: [FoundLibrary]], complete: Bool, notSearched: [String]) {
        let deadline = ProcessInfo.processInfo.systemUptime + sizer.timeBudget
        let volumes = systemRoot.appendingPathComponent("Volumes")
        var roots = [home]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: volumes.path))?.sorted() ?? [] {
            let url = volumes.appendingPathComponent(name)
            if access.isLocal(url) { roots.append(url) }
        }
        let searches = roots.map { root in
            RootSearch(root: root, isHome: root == home, extensions: extensions, volumes: volumes, deadline: deadline, sizer: sizer, access: access)
        }
        // A walk checks the deadline itself every 1024 entries; the grace lets one that is slow but moving return what it found.
        let abandonAt = DispatchTime.now() + sizer.timeBudget + min(1, sizer.timeBudget / 4)
        var seen = Set<String>(), found: [String: [FoundLibrary]] = [:], complete = true, notSearched: [String] = []
        for search in searches {
            guard let result = search.wait(until: abandonAt) else {
                complete = false
                notSearched.append(volume(of: search.root, under: volumes))
                continue
            }
            if !result.complete { complete = false }
            for library in result.found where seen.insert(library.url.standardizedFileURL.path).inserted {
                found[library.url.pathExtension.lowercased(), default: []].append(library)
            }
        }
        return (found, complete, notSearched)
    }

    /// One root searched on its own thread. Abandoning it leaves the thread to finish or stay stuck; its result is dropped.
    private final class RootSearch: @unchecked Sendable {
        let root: URL
        private let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var result: (found: [FoundLibrary], complete: Bool)?
        private var abandoned = false

        init(root: URL, isHome: Bool, extensions: Set<String>, volumes: URL, deadline: TimeInterval, sizer: KnownLocationSizer, access: LibraryVolumes) {
            self.root = root
            Thread.detachNewThread { [self] in
                var found: [FoundLibrary] = [], complete = true, entries = 0, info = stat()
                // `/Volumes/Macintosh HD` is a link to `/`: only real mount folders are searched. Checked here, since
                // even this can hang on a dropped share.
                if isHome || (lstat(root.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR) {
                    _ = access.walk(root) { entry in
                        entries += 1
                        if entries % 1024 == 0, ProcessInfo.processInfo.systemUptime > deadline || self.isAbandoned { complete = false; return .stop }
                        guard Int32(entry.pointee.fts_info) == FTS_D, entry.pointee.fts_level > 0 else { return .continue }
                        let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                        let name = url.lastPathComponent, ext = url.pathExtension.lowercased()
                        if name.hasPrefix(".") || ext == "app" || (isHome && entry.pointee.fts_level == 1 && name == "Library") { return .skip }
                        if extensions.contains(ext) {
                            found.append(FoundLibrary(url: url, volume: LibrarySearch.volume(of: url, under: volumes), size: Catalog.estimate(sizer.size(url))))
                            return .skip
                        }
                        return Int(entry.pointee.fts_level) >= maxDepth ? .skip : .continue
                    }
                }
                self.lock.lock(); self.result = (found, complete); self.lock.unlock()
                self.done.signal()
            }
        }
        private var isAbandoned: Bool { lock.lock(); defer { lock.unlock() }; return abandoned }
        /// The root's result, or nil when its walk hadn't returned by `time`, which abandons it.
        func wait(until time: DispatchTime) -> (found: [FoundLibrary], complete: Bool)? {
            let finished = done.wait(timeout: time) == .success
            lock.lock(); defer { lock.unlock() }
            if !finished { abandoned = true; return nil }
            return result
        }
    }

    /// A connected volume's folder name under `/Volumes`, else the startup volume's name.
    static func volume(of url: URL, under volumes: URL) -> String {
        let prefix = volumes.standardizedFileURL.path + "/"
        if url.standardizedFileURL.path.hasPrefix(prefix) {
            return String(url.standardizedFileURL.path.dropFirst(prefix.count).prefix { $0 != "/" })
        }
        return (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "This Mac"
    }
}
