import Foundation
import CryptoKit
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
    /// The chosen installation is not executed. Only byte-verified shell fast paths
    /// are staged; no mutable brew.env, Git, tap, formula, Ruby or wrapper is loaded.
    public static func inspectSelected(executable: URL, cache: URL) throws -> HomebrewCacheInventory {
        guard executable.isFileURL, cache.isFileURL, executable.lastPathComponent == "brew",
              executable.deletingLastPathComponent().lastPathComponent == "bin" else { throw ToolPreviewError.unavailable }
        let selected = executable.standardizedFileURL
        let repository = selected.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let prefix = selected.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let selectedCache = cache.standardizedFileURL.resolvingSymlinksInPath()
        guard prefix.path != "/", selectedCache.path != "/" else { throw ToolPreviewError.unavailable }
        let pins = [
            "bin/brew": "5486710858db51927d4ec84ae0a4952da3e132c55cc12bad76ae8f1c18c9fb00",
            "Library/Homebrew/brew.sh": "cdb88f545ad22a68862c28153c4f91b79d9d0778c03442c7bcdfe5ab3c2bd84c",
            "Library/Homebrew/help.sh": "1dd0d74bb55ca636bff19b74e0c54710c61c114791b22b9fce3280394a33e38e",
            "Library/Homebrew/formula_path.sh": "87c5c6c9e751769c5fa7a208fecb811c18405e52515d7ee7a893b95e0e815212"
        ]
        var sources: [String: Data] = [:]
        for (path, pin) in pins {
            let url = repository.appendingPathComponent(path)
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_size > 0, metadata.st_size < 256_000,
                  let data = try? boundedSource(url),
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == pin else {
                return .init(version: "Unqualified installation (not executed)", prefix: prefix.path, cache: selectedCache.path,
                             supported: false, complete: false, regularFileCount: 0, logicalBytes: nil, allocatedBytes: nil,
                             downloadFileCount: 0, incompleteDownloads: [], incompleteDownloadCount: 0, observedAt: Date(),
                             guidance: "Choose an unmodified Homebrew 4.6.17 shell installation. Other versions remain unsupported; no installed code or cache was inspected.")
            }
            sources[path] = data
        }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("StillHomebrewQuery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        for (path, data) in sources {
            let target = stage.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": stage.path, "TMPDIR": stage.path,
                           "LANG": "C", "LC_ALL": "C", "HOMEBREW_PREFIX": prefix.path,
                           "HOMEBREW_REPOSITORY": stage.path, "HOMEBREW_LIBRARY": stage.appendingPathComponent("Library").path,
                           "HOMEBREW_CACHE": selectedCache.path, "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"]
        let script = stage.appendingPathComponent("Library/Homebrew/brew.sh")
        for (argument, expected) in [("--prefix", prefix.path), ("--cache", selectedCache.path)] {
            let output = try BoundedTool.run(executable: URL(fileURLWithPath: "/bin/bash"), arguments: ["-p", script.path, argument], environment: environment)
            guard output == expected + "\n" else { throw ToolPreviewError.invalidOutput }
        }
        return try measureHomebrewCache(selectedCache, prefix: prefix.path)
    }

    private static func boundedSource(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 256_000), data.count < 256_000 else { throw ToolPreviewError.outputLimit }
        return data
    }

    private static func measureHomebrewCache(_ cache: URL, prefix: String) throws -> HomebrewCacheInventory {
        var initial = stat()
        guard lstat(cache.path, &initial) == 0, initial.st_mode & S_IFMT == S_IFDIR else { throw ToolPreviewError.unavailable }
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
            guard lstat(url.path, &metadata) == 0, metadata.st_dev == initial.st_dev else { enumerator.skipDescendants(); complete = false; continue }
            let kind = metadata.st_mode & S_IFMT
            if kind == S_IFLNK { enumerator.skipDescendants(); complete = false; continue }
            if kind == S_IFDIR { continue }
            guard kind == S_IFREG, metadata.st_size >= 0, metadata.st_blocks >= 0, metadata.st_blocks <= Int64.max / 512,
                  metadata.st_flags & UInt32(SF_DATALESS) == 0 else { complete = false; continue }
            let relative = url.pathComponents.dropFirst(physicalComponents.count).joined(separator: "/")
            count += 1
            if relative.hasPrefix("downloads/") { downloads += 1 }
            // Match only Homebrew's top-level incomplete-file observation; nested
            // downloads may still be active and are not vendor dry-run candidates.
            if !relative.contains("/"), relative.hasSuffix(".incomplete") {
                incompleteCount += 1
                if incomplete.count < 100 { incomplete.append(.init(relativePath: relative, logicalBytes: metadata.st_size, allocatedBytes: metadata.st_blocks * 512)) }
            }
            if seen.insert("\(metadata.st_dev):\(metadata.st_ino)").inserted {
                let nextLogical = logical.addingReportingOverflow(metadata.st_size)
                let blocks = metadata.st_blocks.multipliedReportingOverflow(by: 512)
                let nextAllocated = allocated.addingReportingOverflow(blocks.partialValue)
                guard !nextLogical.overflow, !blocks.overflow, !nextAllocated.overflow else { complete = false; break }
                logical = nextLogical.partialValue; allocated = nextAllocated.partialValue
            }
        }
        var final = stat()
        if lstat(cache.path, &final) != 0 || initial.st_dev != final.st_dev || initial.st_ino != final.st_ino || initial.st_mtimespec.tv_sec != final.st_mtimespec.tv_sec || initial.st_mtimespec.tv_nsec != final.st_mtimespec.tv_nsec { complete = false }
        return .init(version: "Homebrew shell source 4.6.17", prefix: prefix, cache: cache.path, supported: true, complete: complete,
                     regularFileCount: count, logicalBytes: complete ? logical : nil, allocatedBytes: complete ? allocated : nil,
                     downloadFileCount: downloads, incompleteDownloads: incomplete.sorted { $0.relativePath < $1.relativePath }, incompleteDownloadCount: incompleteCount,
                     observedAt: Date(), guidance: "Explicit cache override; user and system brew.env settings are not read. Metadata is not an atomic snapshot. Folder ownership is not established by selection. Incomplete names can belong to active downloads. Vendor cleanup, formula/Cellar inventory and exclusively reclaimable space remain unqualified; no cleanup is available.")
    }
}
