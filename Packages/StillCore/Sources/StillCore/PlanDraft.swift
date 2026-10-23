import Foundation
import Darwin

public struct DownloadsRoot: Sendable {
    public let url: URL
    public let resourceID: String
    public init(url: URL) throws {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw PlanSelectionError.ineligible }
        guard let resolved = realpath(url.path, nil) else { throw PlanSelectionError.ineligible }
        defer { free(resolved) }
        self.url = URL(fileURLWithPath: String(cString: resolved))
        resourceID = "\(info.st_dev):\(info.st_ino)"
    }
}
public enum PlanSelectionError: Error { case ineligible }
public struct PlannedTarget: Sendable, Identifiable {
    /// Exact directory entry + observed resource + action; hardlink aliases are distinct targets.
    public var id: String { url.path + "|" + resourceID + "|moveToTrash" }
    public let url: URL
    public let resourceID: String
    public let scope: URL
    public let scopeCanonicalURL: URL
    public let scopeResourceID: String
    public let volumeID: String
    public let downloadsRoot: DownloadsRoot
    public let observedAt: Date
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
}
public struct CleanupReview: Sendable, Identifiable {
    public let id: UUID
    public let targets: [PlannedTarget]
    public let mutationVersion: UInt64
    fileprivate let sessionID: UUID
    fileprivate init(targets: [PlannedTarget], mutationVersion: UInt64, sessionID: UUID) {
        id = UUID(); self.targets = targets; self.mutationVersion = mutationVersion; self.sessionID = sessionID
    }
}
public struct CleanupApproval: Sendable, Identifiable {
    public let id: UUID
    public let targets: [PlannedTarget]
    public let approvedAt: Date
    public let action = "moveToTrash"
    fileprivate init(review: CleanupReview, date: Date) { id = UUID(); targets = review.targets; approvedAt = date }
}
public enum CategorySelectionState: Sendable { case unchecked, mixed, checked }
public struct PlanDraft: Sendable {
    private let sessionID = UUID()
    private var chosen: [String: PlannedTarget] = [:]
    public private(set) var mutationVersion: UInt64 = 0
    public init() {}
    public func review() throws -> CleanupReview {
        guard !chosen.isEmpty else { throw PlanSelectionError.ineligible }
        return CleanupReview(targets: selected, mutationVersion: mutationVersion, sessionID: sessionID)
    }
    public mutating func selectAll(in scans: [ScanResult], downloads: DownloadsRoot) -> Int {
        var visited = Set<String>(), skipped = 0
        for scan in scans {
            for item in scan.observations where Self.canConsider(item, in: scan, downloads: downloads) {
                let id = item.url.path + "|" + item.resourceID
                guard visited.insert(id).inserted else { continue }
                do { let target = try Self.freshCandidate(item, in: scan, downloads: downloads); chosen[target.id] = target; invalidateReview() } catch { skipped += 1 }
            }
        }
        return skipped
    }
    public func categoryState(in scans: [ScanResult], downloads: DownloadsRoot) -> CategorySelectionState {
        let eligible = Set(scans.flatMap { scan in scan.observations.filter { Self.canConsider($0, in: scan, downloads: downloads) }.map { $0.url.path + "|" + $0.resourceID + "|moveToTrash" } })
        let count = eligible.filter { chosen[$0] != nil }.count
        return count == 0 ? .unchecked : count == eligible.count ? .checked : .mixed
    }
    public mutating func invalidateReview() { mutationVersion &+= 1 }
    public func approve(_ review: CleanupReview, at date: Date = Date()) throws -> CleanupApproval {
        guard !chosen.isEmpty, review.sessionID == sessionID, review.mutationVersion == mutationVersion,
              Set(review.targets.map(\.id)) == Set(chosen.keys) else { throw PlanSelectionError.ineligible }
        return CleanupApproval(review: review, date: date)
    }
    public var selected: [PlannedTarget] { chosen.values.sorted { $0.url.path < $1.url.path } }
    public var selectedCount: Int { chosen.count }
    /// Storage identities count once; selecting two hardlink entries still plans two exact paths.
    public var logicalBytes: Int64 { uniqueResources.reduce(0) { $0 + $1.logicalBytes } }
    public var allocatedBytes: Int64? {
        let entries = uniqueResources
        guard entries.allSatisfy({ $0.allocatedBytes != nil }) else { return nil }
        return entries.reduce(0) { $0 + ($1.allocatedBytes ?? 0) }
    }
    private var uniqueResources: [PlannedTarget] {
        var counted = Set<String>()
        return selected.filter { counted.insert($0.resourceID).inserted }
    }
    public func contains(_ item: FileObservation) -> Bool { chosen[item.url.path + "|" + item.resourceID + "|moveToTrash"] != nil }
    mutating func replaceAfterRefresh(_ original: PlannedTarget, with fresh: PlannedTarget) {
        guard chosen[original.id]?.observedAt == original.observedAt, original.id == fresh.id else { return }
        chosen[original.id] = fresh
        invalidateReview()
    }
    public mutating func remove(_ id: String) { chosen[id] = nil; invalidateReview() }
    public mutating func clear() { chosen.removeAll(); invalidateReview() }
    public mutating func select(_ item: FileObservation, in scan: ScanResult, downloadsRoot: URL) throws {
        try select(item, in: scan, downloads: DownloadsRoot(url: downloadsRoot))
    }
    public mutating func select(_ item: FileObservation, in scan: ScanResult, downloads: DownloadsRoot) throws {
        let target = try Self.candidate(item, in: scan, downloads: downloads)
        chosen[target.id] = target
        invalidateReview()
    }
    /// Presentation-only eligibility from scan evidence; selection still performs fresh checks.
    public static func canConsider(_ item: FileObservation, in scan: ScanResult, downloads: DownloadsRoot) -> Bool {
        let root = downloads.url.standardizedFileURL.pathComponents
        let parts = item.url.standardizedFileURL.pathComponents
        let scope = scan.scope.standardizedFileURL.pathComponents
        let protectedExtensions = Set(["app", "bundle", "framework", "xcarchive", "dsym", "photoslibrary", "photolibrary", "musiclibrary", "library", "backupbundle", "sparsebundle", "band", "logicx", "db", "sqlite", "sqlite3"])
        let affected = scan.issues.contains { issue in
            parts.starts(with: issue.url.standardizedFileURL.pathComponents)
        }
        return !affected && item.kind == .file && item.previewAvailability == .local && item.cloud.membership == false && scope.starts(with: root)
            && parts.starts(with: root) && parts.count > root.count
            && !parts.dropFirst(root.count).contains { protectedExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) || [".git", ".Trash", "Backups.backupdb", ".."].contains($0) }
    }
    public static func candidate(_ item: FileObservation, in scan: ScanResult, downloads: DownloadsRoot) throws -> PlannedTarget {
        guard scan.observations.contains(where: { $0.id == item.id && $0.resourceID == item.resourceID }) else { throw PlanSelectionError.ineligible }
        return try freshCandidate(item, in: scan, downloads: downloads)
    }
    static func freshCandidate(_ item: FileObservation, in scan: ScanResult, downloads: DownloadsRoot, preservingScope: URL? = nil) throws -> PlannedTarget {
        guard canConsider(item, in: scan, downloads: downloads) else { throw PlanSelectionError.ineligible }
        var rootInfo = stat()
        guard lstat(downloads.url.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR,
              "\(rootInfo.st_dev):\(rootInfo.st_ino)" == downloads.resourceID else { throw PlanSelectionError.ineligible }
        let rootParts = downloads.url.pathComponents
        let pathParts = item.url.pathComponents
        let targetScope = preservingScope ?? scan.scope
        let scopedRoot = try DownloadsRoot(url: targetScope)
        let scopeParts = scopedRoot.url.pathComponents
        guard scopeParts.starts(with: rootParts), pathParts.starts(with: rootParts), pathParts.count > rootParts.count else { throw PlanSelectionError.ineligible }
        var ancestor = downloads.url
        let protectedExtensions = Set(["app", "bundle", "framework", "xcarchive", "dsym", "photoslibrary", "photolibrary", "musiclibrary", "library", "backupbundle", "sparsebundle", "band", "logicx", "db", "sqlite", "sqlite3"])
        for part in pathParts.dropFirst(rootParts.count) {
            ancestor.appendPathComponent(part)
            var entry = stat()
            guard lstat(ancestor.path, &entry) == 0, entry.st_mode & S_IFMT != S_IFLNK,
                  entry.st_dev == rootInfo.st_dev, !protectedExtensions.contains(ancestor.pathExtension.lowercased()),
                  ![".git", ".Trash", "Backups.backupdb"].contains(part) else { throw PlanSelectionError.ineligible }
        }
        var info = stat()
        guard lstat(item.url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              "\(info.st_dev):\(info.st_ino)" == item.resourceID, Int64(info.st_size) == item.logicalBytes else { throw PlanSelectionError.ineligible }
        guard let volumeID = try item.url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else { throw PlanSelectionError.ineligible }
        return PlannedTarget(url: item.url, resourceID: item.resourceID, scope: targetScope, scopeCanonicalURL: scopedRoot.url, scopeResourceID: scopedRoot.resourceID, volumeID: volumeID, downloadsRoot: downloads,
            observedAt: scan.observedAt, modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            logicalBytes: Int64(info.st_size), allocatedBytes: item.allocatedBytes)
    }
}
