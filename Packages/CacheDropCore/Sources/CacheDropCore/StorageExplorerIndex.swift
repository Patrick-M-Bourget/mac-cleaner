import Foundation

/// The storage explorer's read-only snapshot of scanned folders (#346): overlap, scope membership and totals share one
/// owner. It uses supplied observations only and never reads filesystem metadata. Built once per change in the scans, off
/// the main thread, it answers every lookup the explorer makes while drawing without walking every observation: a
/// location holds up to 100,000, and re-sorting them all on each redraw froze the app.
public struct StorageExplorerIndex: Sendable {
    public struct Entry: Sendable, Identifiable {
        public let item: FileObservation
        public let scan: ScanResult
        /// `item.url.path`, read once at indexing.
        public let path: String
        public var id: String { item.id + "|" + item.resourceID }
    }
    public struct Subtotal: Sendable, Equatable {
        public let bytes: Int64
        public let hasUnknownRemainder: Bool
    }
    /// The scanned locations shown, by path.
    public let scans: [ScanResult]
    /// Every observation once, in no particular order.
    public let entries: [Entry]
    /// Each folder's direct children by its path: folders first, then by name as Finder sorts them.
    private let childrenByFolder: [String: [Entry]]
    private let folderPaths: Set<String>
    private let entriesByID: [String: Entry]
    private let entriesByResource: [String: Entry]
    /// What each folder holds on disk, each file identity once, and whether an unknown size leaves a remainder.
    private let allocatedByFolder: [String: (bytes: Int64, unknown: Bool)]
    /// Every issue's path and the folders above it: a folder listed here holds an issue.
    private let issueAncestors: Set<String>
    private let issuePaths: Set<String>

    /// The latest scan of each location in `selected` and `reports`, minus locations a recheck couldn't reach (`gone`, #249)
    /// and those outside `allowedScopes`. Where locations overlap, an item `eligible` in one keeps its evidence.
    public init(scans selected: [ScanResult], reports: [ScanResult], gone: [URL] = [], allowedScopes: Set<URL>?,
                eligible: (FileObservation, ScanResult) -> Bool) {
        var latest = Dictionary(UnavailableScannedFolder.current(selected, gone: gone).map { ($0.scope, $0) }, uniquingKeysWith: { first, _ in first })
        for scan in UnavailableScannedFolder.current(reports, gone: gone) {
            if latest[scan.scope].map({ $0.observedAt < scan.observedAt }) ?? true { latest[scan.scope] = scan }
        }
        scans = latest.values.filter { scan in
            allowedScopes?.contains(scan.scope.standardizedFileURL) ?? true
        }.sorted { $0.scope.path < $1.scope.path }
        var representatives: [String: Entry] = [:]
        for scan in scans.sorted(by: { $0.observedAt > $1.observedAt }) {
            for item in scan.observations {
                let entry = Entry(item: item, scan: scan, path: item.url.path)
                if let existing = representatives[entry.id] {
                    // One failed overlapping location must not suppress independent valid evidence.
                    if !eligible(existing.item, existing.scan), eligible(item, scan) { representatives[entry.id] = entry }
                } else { representatives[entry.id] = entry }
            }
        }
        entriesByID = representatives
        entries = Array(representatives.values)
        // A shared identity (hard links) is always represented by the same observation: the first path.
        entriesByResource = Dictionary(entries.map { ($0.item.resourceID, $0) }, uniquingKeysWith: { left, right in left.path < right.path ? left : right })

        var children: [String: [(entry: Entry, name: Substring)]] = [:]
        for entry in entries {
            let path = entry.path
            let slash = path.lastIndex(of: "/") ?? path.startIndex
            let parent = slash == path.startIndex ? "/" : String(path[..<slash])
            children[parent, default: []].append((entry, path[path.index(after: slash)...]))
        }
        // Siblings share their parent, so their names alone give Finder's order.
        childrenByFolder = children.mapValues { siblings in
            siblings.sorted { Self.finderOrder($0.entry, $0.name, $1.entry, $1.name) }.map(\.entry)
        }
        folderPaths = Set(scans.map(\.scope.path)).union(entries.filter { $0.item.kind == .folder }.map(\.path))

        // One pass: each file adds to every folder above it, through any location that contains its own (#346 review:
        // overlapping locations). Only identities seen more than once (hard links) are remembered per folder, so each still
        // counts once.
        var resourceCounts: [String: Int] = [:]
        for entry in entries where entry.item.kind != .folder { resourceCounts[entry.item.resourceID, default: 0] += 1 }
        // Each location's walk ends at the outermost shown location holding it, so a nested one's files reach the outer's folders.
        let shown = scans, shownPaths = shown.map(\.scope.path)
        let outermost = Dictionary(shown.map { scan in
            (scan.scope, shownPaths.filter { Self.isWithin(scan.scope.path, $0) }.min { $0.count < $1.count } ?? scan.scope.path)
        }, uniquingKeysWith: { first, _ in first })
        var allocated: [String: (bytes: Int64, unknown: Bool)] = [:]
        var counted: [String: Set<String>] = [:]
        for entry in entries where entry.item.kind != .folder {
            let shared = resourceCounts[entry.item.resourceID, default: 0] > 1
            let size = entry.item.kind == .file ? entry.item.allocatedBytes : nil
            for folder in Self.ancestors(of: entry.path, within: outermost[entry.scan.scope] ?? "/") {
                if shared { guard counted[folder, default: []].insert(entry.item.resourceID).inserted else { continue } }
                var subtotal = allocated[folder] ?? (0, false)
                if let size {
                    let sum = subtotal.bytes.addingReportingOverflow(size)
                    if sum.overflow { subtotal.unknown = true } else { subtotal.bytes = sum.partialValue }
                } else { subtotal.unknown = true }
                allocated[folder] = subtotal
            }
        }
        allocatedByFolder = allocated
        let issues = scans.flatMap(\.issues).map(\.url.path)
        issuePaths = Set(issues)
        issueAncestors = Set(issues.flatMap { [$0] + Self.ancestors(of: $0, within: "/") })
    }

    /// Whether another shown location contains `scope` or sits inside it.
    public func overlaps(_ scope: URL) -> Bool {
        scans.contains { $0.scope != scope && ($0.scope.pathComponents.starts(with: scope.pathComponents) || scope.pathComponents.starts(with: $0.scope.pathComponents)) }
    }
    /// The entries directly inside `folder`: folders first, then by name as Finder sorts them.
    public func children(of folder: URL) -> [Entry] { childrenByFolder[folder.standardizedFileURL.path] ?? [] }
    /// Search: every entry below `folder` whose path inside it contains `query`, folders first, then by path as Finder
    /// sorts them. Only the matches are sorted.
    public func matches(in folder: URL, query: String) -> [Entry] {
        let path = folder.standardizedFileURL.path, prefix = path == "/" ? "/" : path + "/"
        return entries.filter { $0.path.hasPrefix(prefix) && $0.path.dropFirst(prefix.count).localizedCaseInsensitiveContains(query) }
            .sorted { Self.finderOrder($0, $0.path[...], $1, $1.path[...]) }
    }
    /// `entries` as the list's column header sorts them (#373). By name, folders stay first either way round; by size, folders
    /// and files mix by what each holds on disk, a folder by its subtotal and an unknown size as nothing.
    public func ordered(_ entries: [Entry], by sort: ListSort) -> [Entry] {
        let name = { (entry: Entry) in String(entry.path[(entry.path.lastIndex(of: "/").map(entry.path.index(after:)) ?? entry.path.startIndex)...]) }
        switch sort.column {
        case .name:
            let folders = entries.filter { $0.item.kind == .folder }, others = entries.filter { $0.item.kind != .folder }
            return sort.ordered(folders, name: name, bytes: { _ in 0 }) + sort.ordered(others, name: name, bytes: { _ in 0 })
        case .size:
            return sort.ordered(entries, name: name) { entry in
                entry.item.kind == .folder ? allocatedByFolder[entry.path]?.bytes ?? 0 : entry.item.allocatedBytes ?? 0
            }
        }
    }
    /// Whether `folder` is a shown location or an observed folder.
    public func contains(folder: URL) -> Bool { folderPaths.contains(folder.standardizedFileURL.path) }
    /// The entry with this row identity and resource, if it is still observed.
    public func entry(id: String, resource: String) -> Entry? { entriesByID[id + "|" + resource] }
    /// An entry observing this file identity, if any.
    public func entry(resource: String) -> Entry? { entriesByResource[resource] }
    /// What `folder` holds on disk, each file identity once; unknown sizes and partly scanned locations leave a remainder.
    public func allocatedSubtotal(in folder: URL) -> Subtotal {
        let path = folder.standardizedFileURL.path
        let found = allocatedByFolder[path] ?? (0, false)
        let excluded = scans.contains { scan in
            scan.excludedEntryCount > 0 && (Self.isWithin(path, scan.scope.path) || Self.isWithin(scan.scope.path, path))
        }
        let issue = issueAncestors.contains(path) || Self.ancestors(of: path, within: "/").contains(where: issuePaths.contains)
        return Subtotal(bytes: found.bytes, hasUnknownRemainder: found.unknown || excluded || issue)
    }

    /// Folders first, then by `leftKey` and `rightKey` (a name or a path) as Finder sorts them ("file 9" before "file 10").
    private static func finderOrder(_ left: Entry, _ leftKey: Substring, _ right: Entry, _ rightKey: Substring) -> Bool {
        if (left.item.kind == .folder) != (right.item.kind == .folder) { return left.item.kind == .folder }
        return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
    }
    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
    /// The folders above `path`, nearest first, down to and including `root`.
    private static func ancestors(of path: String, within root: String) -> [String] {
        var result: [String] = [], current = path
        while current != root, current != "/" {
            current = parent(of: current)
            result.append(current)
        }
        return result
    }
    /// Whether `path` is `folder` or inside it.
    private static func isWithin(_ path: String, _ folder: String) -> Bool { path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/") }
}
