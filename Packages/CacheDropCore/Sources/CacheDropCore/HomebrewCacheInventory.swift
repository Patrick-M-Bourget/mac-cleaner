import Foundation
import Darwin

public struct HomebrewCacheEntry: Sendable {
    public let relativePath: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
}

/// Metadata inventory, never vendor cleanup eligibility or execution authority.
public struct HomebrewCacheInventory: Sendable {
    public let version: String
    public let prefix: String
    public let cache: String
    public let supported: Bool
    public let complete: Bool
    public let regularFileCount: Int
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?
    public let downloadFileCount: Int
    public let incompleteDownloads: [HomebrewCacheEntry]
    public let incompleteDownloadCount: Int
    public let observedAt: Date
    public let guidance: String
    public var estimatedReleaseBytes: Int64? { nil }
}

extension HomebrewInspector {
    /// The chosen installation is never executed; only the selected cache's metadata is read.
    public static func inspectSelected(executable: URL, cache: URL) throws -> HomebrewCacheInventory {
        guard executable.isFileURL, cache.isFileURL, executable.lastPathComponent == "brew",
              executable.deletingLastPathComponent().lastPathComponent == "bin" else { throw ToolPreviewError.unavailable }
        let prefix = executable.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let selectedCache = cache.standardizedFileURL.resolvingSymlinksInPath()
        guard prefix.path != "/", selectedCache.path != "/" else { throw ToolPreviewError.unavailable }
        return try measureHomebrewCache(selectedCache, prefix: prefix.path)
    }

    private static func measureHomebrewCache(_ cache: URL, prefix: String) throws -> HomebrewCacheInventory {
        var initial = stat()
        guard lstat(cache.path, &initial) == 0, initial.st_mode & S_IFMT == S_IFDIR else { throw ToolPreviewError.unavailable }
        // Reject a cloud-only root before obtaining an enumerator: entering it can
        // cause provider work even when individual file contents are never opened.
        if initial.st_flags & UInt32(SF_DATALESS) != 0 {
            return .init(version: "Not executed", prefix: prefix, cache: cache.path,
                         supported: true, complete: false, regularFileCount: 0, logicalBytes: nil, allocatedBytes: nil,
                         downloadFileCount: 0, incompleteDownloads: [], incompleteDownloadCount: 0, observedAt: Date(),
                         guidance: "Selected cache folder is not fully local; contents were not enumerated. Totals and reclaimable space are unknown. No cleanup is available.")
        }
        guard let physicalPointer = realpath(cache.path, nil) else { throw ToolPreviewError.unavailable }
        let physicalComponents = URL(fileURLWithPath: String(cString: physicalPointer)).pathComponents
        free(physicalPointer)
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var complete = true
        guard let enumerator = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: [], errorHandler: { _, _ in complete = false; return false }) else { throw ToolPreviewError.unavailable }
        var count = 0, downloads = 0, incompleteCount = 0, entries = 0
        var logical: Int64 = 0, allocated: Int64 = 0
        var seen = Set<String>()
        var incomplete: [HomebrewCacheEntry] = []
        for case let url as URL in enumerator {
            entries += 1
            guard entries <= 100_000, ProcessInfo.processInfo.systemUptime < deadline else { complete = false; break }
            guard url.pathComponents.count - physicalComponents.count <= 64 else { enumerator.skipDescendants(); complete = false; continue }
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0, metadata.st_dev == initial.st_dev,
                  metadata.st_flags & UInt32(SF_DATALESS) == 0 else { enumerator.skipDescendants(); complete = false; continue }
            let kind = metadata.st_mode & S_IFMT
            if kind == S_IFLNK { enumerator.skipDescendants(); complete = false; continue }
            if kind == S_IFDIR { continue }
            guard kind == S_IFREG, metadata.st_size >= 0, metadata.st_blocks >= 0, metadata.st_blocks <= Int64.max / 512 else { complete = false; continue }
            let relative = url.pathComponents.dropFirst(physicalComponents.count).joined(separator: "/")
            count += 1
            if relative.hasPrefix("downloads/") { downloads += 1 }
            // Match only Homebrew's top-level incomplete-file observation; nested
            // downloads may still be active and are not vendor dry-run candidates.
            if !relative.contains("/"), relative.hasSuffix(".incomplete") {
                incompleteCount += 1
                if incomplete.count < 100 { incomplete.append(.init(relativePath: relative, logicalBytes: metadata.st_size, allocatedBytes: metadata.st_blocks * 512)) }
            }
            if seen.insert(metadata.resourceID).inserted {
                let nextLogical = logical.addingReportingOverflow(metadata.st_size)
                let blocks = metadata.st_blocks.multipliedReportingOverflow(by: 512)
                let nextAllocated = allocated.addingReportingOverflow(blocks.partialValue)
                guard !nextLogical.overflow, !blocks.overflow, !nextAllocated.overflow else { complete = false; break }
                logical = nextLogical.partialValue; allocated = nextAllocated.partialValue
            }
        }
        var final = stat()
        if lstat(cache.path, &final) != 0 || initial.st_dev != final.st_dev || initial.st_ino != final.st_ino || initial.st_mtimespec.tv_sec != final.st_mtimespec.tv_sec || initial.st_mtimespec.tv_nsec != final.st_mtimespec.tv_nsec || final.st_flags & UInt32(SF_DATALESS) != 0 { complete = false }
        return .init(version: "Not executed", prefix: prefix, cache: cache.path, supported: true, complete: complete,
                     regularFileCount: count, logicalBytes: complete ? logical : nil, allocatedBytes: complete ? allocated : nil,
                     downloadFileCount: downloads, incompleteDownloads: incomplete.sorted { $0.relativePath < $1.relativePath }, incompleteDownloadCount: incompleteCount,
                     observedAt: Date(), guidance: "Explicit cache override; user and system brew.env settings are not read. Metadata is not an atomic snapshot. Folder ownership is not established by selection. Incomplete names can belong to active downloads. Vendor cleanup, formula/Cellar inventory and exclusively reclaimable space remain unqualified; no cleanup is available.")
    }
}
