import Foundation
import Darwin

public enum PreviewAvailability: String, Sendable { case local, nonlocal, unknown }
public enum ObservationKind: String, Sendable { case file, folder, package, symbolicLink, other }

public struct MetadataSupplement: Sendable {
    public let allocatedBytes: Int64?
    public let locality: PreviewAvailability
    public let cloud: CloudMetadata
    public init(allocatedBytes: Int64?, locality: PreviewAvailability, cloud: CloudMetadata = .unknown) {
        self.allocatedBytes = allocatedBytes
        self.locality = locality
        self.cloud = cloud
    }
}

/// Metadata-only filesystem boundary. Implementations must never open file contents.
public protocol MetadataSupplementReading: Sendable {
    func read(_ url: URL) throws -> MetadataSupplement
}

public struct FoundationMetadataSupplement: MetadataSupplementReading {
    public init() {}
    public func read(_ url: URL) throws -> MetadataSupplement {
        let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemIsDownloadingKey, .ubiquitousItemHasUnresolvedConflictsKey])
        var information = stat()
        let hasStat = lstat(url.path, &information) == 0
        let dataless = hasStat && information.st_flags & UInt32(SF_DATALESS) != 0
        let locality: PreviewAvailability
        if dataless || values.ubiquitousItemDownloadingStatus == .notDownloaded { locality = .nonlocal }
        else if values.isUbiquitousItem == false { locality = .local }
        else if values.isUbiquitousItem == true,
                values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded { locality = .local }
        else { locality = .unknown }
        let downloadState: CloudDownloadState
        switch values.ubiquitousItemDownloadingStatus {
        case .current: downloadState = .current
        case .downloaded: downloadState = .downloaded
        case .notDownloaded: downloadState = .notDownloaded
        default: downloadState = .unknown
        }
        return MetadataSupplement(allocatedBytes: values.totalFileAllocatedSize.map(Int64.init), locality: locality,
            cloud: .init(membership: values.isUbiquitousItem, downloadState: downloadState,
                uploaded: values.ubiquitousItemIsUploaded, uploading: values.ubiquitousItemIsUploading,
                downloading: values.ubiquitousItemIsDownloading, conflicts: values.ubiquitousItemHasUnresolvedConflicts))
    }
}

public struct FileObservation: Sendable, Identifiable {
    /// Row identity includes the path; resource identity permits hardlink de-duplication.
    public let id: String
    public let resourceID: String
    public let url: URL
    public let kind: ObservationKind
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?
    public let previewAvailability: PreviewAvailability
    public let isDuplicateResource: Bool
    public let cloud: CloudMetadata
}

public struct ScanIssue: Sendable {
    public enum Reason: String, Sendable { case entryLimit, depthLimit, readFailed, metadataUnavailable, differentVolume }
    public let url: URL
    public let reason: Reason
}

public struct ScanResult: Sendable {
    public let scope: URL
    public let observedAt: Date
    public let observations: [FileObservation]
    /// Totals count repeated file identities once. They are not reclaimable-space estimates.
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    public let allocatedUnknownCount: Int
    public let volumeCapacityBytes: Int64?
    public let volumeAvailableBytes: Int64?
    public let issues: [ScanIssue]
    public var isComplete: Bool { issues.isEmpty }
}

/// Serial actor isolation keeps blocking enumeration off MainActor, without a task per entry.
public actor FolderScanner {
    private let maximumEntries: Int
    private let supplement: any MetadataSupplementReading
    public init(supplement: any MetadataSupplementReading = FoundationMetadataSupplement(), maximumEntries: Int = 100_000) {
        self.maximumEntries = min(max(1, maximumEntries), 100_000)
        self.supplement = supplement
    }

    /// Explicit caller action only. Recheck locality and identity without reading content.
    public func previewURL(for observation: FileObservation) throws -> URL {
        var current = stat()
        guard observation.kind == .file,
              lstat(observation.url.path, &current) == 0,
              current.st_mode & S_IFMT == S_IFREG,
              "\(current.st_dev):\(current.st_ino)" == observation.resourceID,
              try supplement.read(observation.url).locality == .local else {
            throw CocoaError(.fileReadNoPermission)
        }
        return observation.url
    }

    public func scan(_ scope: URL) throws -> ScanResult {
        var observations: [FileObservation] = []
        var issues: [ScanIssue] = []
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var allocationUnknown = 0
        var counted = Set<String>()
        var rootMetadata = stat()
        guard scope.isFileURL, lstat(scope.path, &rootMetadata) == 0,
              (rootMetadata.st_mode & S_IFMT) == S_IFDIR else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard (try? scope.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else {
            throw CocoaError(.fileReadNoPermission)
        }
        let manager = FileManager()
        let enumerationErrors = EnumerationErrors()
        guard let entries = manager.enumerator(at: scope, includingPropertiesForKeys: [.isPackageKey], options: [.skipsPackageDescendants], errorHandler: { url, _ in
            enumerationErrors.urls.append(url)
            return true
        }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        for case let url as URL in entries {
            try Task.checkCancellation()
            guard observations.count < maximumEntries else {
                issues.append(.init(url: scope, reason: .entryLimit))
                break
            }
            guard url.standardizedFileURL.pathComponents.starts(with: scope.standardizedFileURL.pathComponents) else {
                entries.skipDescendants()
                continue
            }
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else {
                issues.append(.init(url: url, reason: .readFailed))
                continue
            }
            let type = metadata.st_mode & S_IFMT
            let isDirectory = type == S_IFDIR
            let isFile = type == S_IFREG
            let isPackage = isDirectory && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
            let sameVolume = metadata.st_dev == rootMetadata.st_dev
            if isPackage || !sameVolume { entries.skipDescendants() }
            if !sameVolume { issues.append(.init(url: url, reason: .differentVolume)) }
            if entries.level > 64 {
                entries.skipDescendants()
                issues.append(.init(url: url, reason: .depthLimit))
                continue
            }
            let kind: ObservationKind = isPackage ? .package : isDirectory ? .folder : isFile ? .file : type == S_IFLNK ? .symbolicLink : .other
            let bytes = isFile && sameVolume ? Int64(metadata.st_size) : nil
            let identity = "\(metadata.st_dev):\(metadata.st_ino)"
            let duplicate = !counted.insert(identity).inserted
            var extra: MetadataSupplement?
            if isFile && sameVolume {
                do { extra = try supplement.read(url) }
                catch { issues.append(.init(url: url, reason: .metadataUnavailable)) }
            }
            if isFile && sameVolume && !duplicate {
                logical += bytes ?? 0
                if let amount = extra?.allocatedBytes { allocated += amount }
                else { allocationUnknown += 1 }
            }
            observations.append(.init(id: url.path, resourceID: identity, url: url, kind: kind,
                logicalBytes: bytes, allocatedBytes: extra?.allocatedBytes,
                previewAvailability: extra?.locality ?? .unknown, isDuplicateResource: duplicate, cloud: extra?.cloud ?? .unknown))
        }
        issues += enumerationErrors.urls.map { .init(url: $0, reason: .readFailed) }
        let volume = try? scope.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return ScanResult(scope: scope, observedAt: Date(), observations: observations.sorted { $0.url.path < $1.url.path },
            logicalBytes: logical, allocatedBytes: allocationUnknown == 0 ? allocated : nil, allocatedUnknownCount: allocationUnknown,
            volumeCapacityBytes: volume?.volumeTotalCapacity.map(Int64.init), volumeAvailableBytes: volume?.volumeAvailableCapacityForImportantUsage, issues: issues)
    }
}

/// FileManager invokes its enumeration error handler synchronously on this scanner actor.
/// The collector never escapes the scan or crosses executors.
private final class EnumerationErrors: @unchecked Sendable {
    var urls: [URL] = []
}
