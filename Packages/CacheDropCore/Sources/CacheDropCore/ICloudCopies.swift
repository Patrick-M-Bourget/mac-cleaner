import Foundation
import Darwin

/// iCloud as the evict action sees it. Reading is metadata only: implementations never open or read file contents.
public protocol UbiquitousItemAccess: Sendable {
    /// The item's iCloud state now; `.unknown` when it can't be read.
    func metadata(_ url: URL) -> CloudMetadata
    /// Removes the local copy only. The original stays in iCloud.
    func evict(_ url: URL) throws
}

/// The real iCloud, through `URLResourceValues` and `FileManager.evictUbiquitousItem`.
public struct SystemUbiquitousItems: UbiquitousItemAccess {
    /// macOS records Keep Downloaded as this extended attribute. No public resource key reports it (macOS 14 to 26 SDKs),
    /// so an attribute that can't be read counts as pinned.
    static let pinnedAttribute = "com.apple.fileprovider.pinned#PX"
    public init() {}
    public func metadata(_ url: URL) -> CloudMetadata {
        guard let cloud = try? FoundationMetadataSupplement().read(url).cloud else { return .unknown }
        return CloudMetadata(membership: cloud.membership, downloadState: cloud.downloadState, uploaded: cloud.uploaded, uploading: cloud.uploading,
                             downloading: cloud.downloading, conflicts: cloud.conflicts, pinned: Self.pinned(url))
    }
    public func evict(_ url: URL) throws { try FileManager.default.evictUbiquitousItem(at: url) }

    /// Whether the item, or a folder holding it inside its iCloud container, is set to Keep Downloaded; nil when that can't be read.
    static func pinned(_ url: URL) -> Bool? {
        var path = url.standardizedFileURL
        while path.pathComponents.count > 1, path.lastPathComponent != "Mobile Documents" {
            let size = getxattr(path.path, pinnedAttribute, nil, 0, 0, XATTR_NOFOLLOW)
            if size >= 0 { return true }
            if errno != ENOATTR { return nil }
            path.deleteLastPathComponent()
        }
        return false
    }
}

extension CloudMetadata {
    /// Why the local copy must stay, or nil when it can be removed: an uploaded, settled local copy, not set to Keep Downloaded.
    public var evictionRefusal: CheckRefusal? {
        guard membership == true else { return membership == false ? .changed : .cloudUnknown }
        guard downloadState == .current || downloadState == .downloaded, downloading != true else { return .notDownloaded }
        guard let pinned else { return .cloudUnknown }
        if pinned { return .keptDownloaded }
        guard let conflicts else { return .cloudUnknown }
        if conflicts { return .conflicted }
        guard uploaded == true, uploading != true else { return .notUploaded }
        return nil
    }
}

/// What a walk of an iCloud item found: the files and packages whose local copies can be removed now.
struct CloudCopies {
    var units: [URL] = []
    var logicalBytes: Int64 = 0
    var allocatedBytes: Int64 = 0
}

extension Catalog {
    /// Runs `body` with this thread barred from downloading iCloud placeholders: touching one fails instead.
    static func withoutDownloads<T>(_ body: () throws -> T) rethrows -> T {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer { if previous >= 0 { _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous) } }
        return try body()
    }

    /// The files and packages in `root` (or `root` itself) whose local copies can be removed. Never follows symlinks,
    /// crosses volumes or enters placeholders, protected or excluded folders; packages count as one item, as iCloud syncs them.
    static func cloudCopies(in root: URL, rule: CleanupRule, cloud: any UbiquitousItemAccess, exclusions: ExclusionPolicy, volumeID: String?) -> CloudCopies {
        withoutDownloads {
            let protection = Protection(rule)
            var found = CloudCopies()
            FileTree.walk(root) { entry in
                let kind = Int32(entry.pointee.fts_info)
                guard kind == FTS_D || kind == FTS_F, let info = entry.pointee.fts_statp?.pointee else { return .continue }
                let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                let skip = (entry.pointee.fts_level > 0 && protection.protects(url.lastPathComponent))
                    || info.st_flags & UInt32(SF_DATALESS) != 0 || info.st_uid != geteuid()
                    || (!exclusions.rules.isEmpty && (volumeID.map { exclusions.covers(url, volumeID: $0) } ?? true))
                let package = kind == FTS_D && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                let next: FileTree.Next = kind == FTS_D && (skip || package) ? .skip : .continue
                guard !skip, kind == FTS_F || package, cloud.metadata(url).evictionRefusal == nil else { return next }
                let size = package ? packageSize(url) : (Int64(info.st_size), Int64(info.st_blocks) * 512)
                found.units.append(url); found.logicalBytes += size.0; found.allocatedBytes += size.1
                return next
            }
            return found
        }
    }

    /// Logical and allocated bytes of the files in a package; placeholders inside count as nothing local.
    private static func packageSize(_ package: URL) -> (Int64, Int64) {
        var logical: Int64 = 0, allocated: Int64 = 0
        FileTree.walk(package) { entry in
            guard Int32(entry.pointee.fts_info) == FTS_F, let info = entry.pointee.fts_statp?.pointee, info.st_flags & UInt32(SF_DATALESS) == 0 else { return .continue }
            logical += Int64(info.st_size); allocated += Int64(info.st_blocks) * 512
            return .continue
        }
        return (logical, allocated)
    }

    /// Each visible file or folder in an iCloud location whose local copies can be removed, sized by what removal releases.
    func cloudCandidates(in location: URL, rule: CleanupRule, cloud: any UbiquitousItemAccess, exclusions: ExclusionPolicy) -> [Candidate] {
        let names = Self.withoutDownloads { (try? FileManager.default.contentsOfDirectory(atPath: location.path)) ?? [] }
        return names.sorted().filter { !$0.hasPrefix(".") }.compactMap { name -> Candidate? in
            let url = location.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return nil }
            let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            let copies = Self.cloudCopies(in: url, rule: rule, cloud: cloud, exclusions: exclusions, volumeID: volume)
            guard !copies.units.isEmpty else { return nil }
            let lastUsed = info.st_mode & S_IFMT == S_IFREG ? Self.lastUsed(url, info) : nil
            return candidate(rule, url, info, logical: copies.logicalBytes, allocated: copies.allocatedBytes, complete: true, lastUsed: lastUsed)
        }
    }
}

extension BuiltInCatalog {
    /// iCloud Drive's local folder, relative to the home folder.
    public static let iCloudDrivePath = "Library/Mobile Documents/com~apple~CloudDocs"
    /// RESET Decision 13: iCloud Drive files downloaded to this Mac. Only the local copy is removed; never a delete.
    static let iCloudLocalCopies = CleanupRule(id: "icloud-local-copies", category: .icloud, title: "Downloaded iCloud Drive files",
        detail: "Files in iCloud Drive that are also stored on this Mac. Files set to Keep Downloaded, not yet uploaded or in conflict are not offered.",
        consequence: "Only the copies on this Mac are removed. The files stay in iCloud and download again when you open them; that needs an internet connection.",
        regen: .cloudCopy, action: .evict, locations: [iCloudDrivePath], owner: nil)
}
