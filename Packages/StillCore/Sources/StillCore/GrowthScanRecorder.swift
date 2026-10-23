import Foundation
import CryptoKit
import Darwin

public struct GrowthScanToken: Sendable {
    public let id = UUID()
    fileprivate let startedAt = Date()
    fileprivate let scope: URL
    fileprivate let epoch: UUID
    fileprivate let fingerprint: GrowthFingerprint
}
/// Metadata-only context around an explicit scan. It never starts enumeration itself.
public actor GrowthScanRecorder: GrowthObservationRecording {
    private let store: GrowthHistoryStore
    public init(store: GrowthHistoryStore) { self.store = store }
    public func begin(scope: URL) async throws -> GrowthScanToken { try await begin(scope: scope, exclusionFingerprint: "none") }
    public func begin(scope: URL, exclusionFingerprint: String) async throws -> GrowthScanToken {
        let epoch = try await store.recordingEpoch()
        return GrowthScanToken(scope: scope.standardizedFileURL, epoch: epoch, fingerprint: try fingerprint(scope, exclusions: exclusionFingerprint))
    }
    public func complete(_ scan: ScanResult, token: GrowthScanToken) async throws -> GrowthComparison {
        try Task.checkCancellation()
        guard scan.scope.standardizedFileURL == token.scope, scan.observedAt >= token.startedAt,
              try fingerprint(scan.scope, exclusions: scan.exclusionFingerprint) == token.fingerprint,
              scan.isComplete, !scan.hasUnmeasuredContents, scan.includedLogicalBytes != nil else {
            return GrowthComparison(state: .unknown, current: nil, from: nil, groups: [])
        }
        let rootLabel = "Files in selected folder"
        var folders: [String: Int64] = ["root-files": 0]
        var folderLabels: [String: String] = ["root-files": rootLabel]
        var categories: [String: Int64] = [:]
        var seen = Set<String>()
        let rootParts = scan.scope.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let originalParts = scan.scope.standardizedFileURL.pathComponents
        func relative(_ item: FileObservation) -> ArraySlice<String>? {
            let parts = item.url.standardizedFileURL.pathComponents
            if parts.starts(with: originalParts) { return parts.dropFirst(originalParts.count) }
            if parts.starts(with: rootParts) { return parts.dropFirst(rootParts.count) }
            return nil
        }
        guard scan.observations.filter({ $0.kind == .file }).allSatisfy({ relative($0) != nil }) else { return .unknown }
        // More than 128 top-level folder groups remains unknown instead of changing grouping coverage.
        let names = Set(scan.observations.filter { $0.kind == .file }.compactMap { item -> String? in
            let parts = relative(item)!
            return parts.count > 1 ? parts.first : nil
        }).sorted()
        guard names.count <= 128 else { return .unknown }
        for item in scan.observations.sorted(by: { $0.url.path < $1.url.path }) where item.kind == .file {
            try Task.checkCancellation()
            guard seen.insert(item.resourceID).inserted, let bytes = item.logicalBytes else { continue }
            let parts = relative(item)!
            let folder: String
            if parts.count > 1, let name = parts.first {
                folder = "directory:" + Self.digest(name)
                folderLabels[folder] = name == rootLabel ? "Folder: " + name : name
            } else { folder = "root-files" }
            folders[folder, default: 0] += bytes
            categories[Self.category(item.url.pathExtension.lowercased()), default: 0] += bytes
        }
        let groups = folders.map { GrowthAggregate(id: "folder:" + $0.key, label: folderLabels[$0.key]!, logicalBytes: $0.value) }
            + categories.map { GrowthAggregate(id: "category:" + $0.key, label: $0.key, logicalBytes: $0.value, dimension: .category) }
        let snapshot = GrowthSnapshot(fingerprint: token.fingerprint, scopeLabel: scan.scope.lastPathComponent, observedAt: scan.observedAt, groups: groups.sorted { $0.id < $1.id })
        return try await store.record(snapshot, expectedEpoch: token.epoch)
    }
    private func fingerprint(_ scope: URL, exclusions: String) throws -> GrowthFingerprint {
        let canonical = scope.resolvingSymlinksInPath().standardizedFileURL
        var info = stat()
        guard lstat(canonical.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              let volume = try canonical.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else { throw CocoaError(.fileReadNoPermission) }
        return GrowthFingerprint(scopeID: Self.digest(canonical.path), rootID: "\(info.st_dev):\(info.st_ino)", volumeID: volume,
            access: "complete-explicit-metadata-scope-v1-mode\(info.st_mode & 0o777)-uid\(info.st_uid)-gid\(info.st_gid)", rules: "scanner-v2-directory-stability-recheck1-deadline30-depth64-entry100000-packages-unmeasured", exclusions: "scanner-protected-boundaries-v1|" + exclusions, classification: "logical-folder128-category-v2-semantic-buckets")
    }
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func category(_ ext: String) -> String {
        if ["pdf", "txt", "md", "doc", "docx", "pages", "xls", "xlsx", "csv", "ppt", "pptx"].contains(ext) { return "Documents" }
        if ["jpg", "jpeg", "png", "heic", "gif", "mov", "mp4", "mp3", "wav", "aiff"].contains(ext) { return "Media" }
        if ["zip", "gz", "tar", "dmg", "pkg", "iso"].contains(ext) { return "Archives and installers" }
        return "Other files"
    }
}
