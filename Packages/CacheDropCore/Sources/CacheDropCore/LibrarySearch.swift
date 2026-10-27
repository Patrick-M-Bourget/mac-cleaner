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

    /// "3 libraries · Macintosh HD, External": how many, and their volumes in the order found. `nouns` names what one
    /// package stands for, such as a Lightroom catalog for its previews (#179).
    public static func summary(_ libraries: [FoundLibrary], nouns: (one: String, many: String) = ("library", "libraries")) -> String {
        var volumes: [String] = []
        for library in libraries where !volumes.contains(library.volume) { volumes.append(library.volume) }
        return (libraries.count == 1 ? "1 \(nouns.one)" : "\(libraries.count) \(nouns.many)") + " · " + volumes.joined(separator: ", ")
    }
}

/// Finds library packages by extension in the home folder and on every volume connected under `/Volumes`.
enum LibrarySearch {
    /// Folders this deep under a root aren't searched, so a large home stays quick.
    static let maxDepth = 6

    /// The packages with each extension, never entering one. Skips `~/Library` (apps' own data), hidden folders and apps.
    /// `complete` is false when the time budget ran out before every root was searched.
    static func find(extensions: Set<String>, home: URL, systemRoot: URL, sizer: KnownLocationSizer) -> (found: [String: [FoundLibrary]], complete: Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + sizer.timeBudget
        let volumes = systemRoot.appendingPathComponent("Volumes")
        var roots = [home]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: volumes.path))?.sorted() ?? [] {
            var info = stat()
            // `/Volumes/Macintosh HD` is a link to `/`: only real mount folders are searched.
            let url = volumes.appendingPathComponent(name)
            if lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR { roots.append(url) }
        }
        var seen = Set<String>(), found: [String: [FoundLibrary]] = [:], complete = true
        for root in roots {
            guard complete else { break }
            var entries = 0
            FileTree.walk(root) { entry in
                entries += 1
                if entries % 1024 == 0, ProcessInfo.processInfo.systemUptime > deadline { complete = false; return .stop }
                guard Int32(entry.pointee.fts_info) == FTS_D, entry.pointee.fts_level > 0 else { return .continue }
                let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                let name = url.lastPathComponent, ext = url.pathExtension.lowercased()
                if name.hasPrefix(".") || ext == "app" || (root == home && entry.pointee.fts_level == 1 && name == "Library") { return .skip }
                if extensions.contains(ext) {
                    if seen.insert(url.standardizedFileURL.path).inserted {
                        found[ext, default: []].append(FoundLibrary(url: url, volume: volume(of: url, under: volumes), size: Catalog.estimate(sizer.size(url))))
                    }
                    return .skip
                }
                return Int(entry.pointee.fts_level) >= maxDepth ? .skip : .continue
            }
        }
        return (found, complete)
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
