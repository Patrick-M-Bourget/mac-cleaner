import Foundation

public enum CloudDownloadState: String, Sendable {
    case current, downloaded, notDownloaded, unknown
}

/// Observed flags describe this moment only; they do not establish server durability or pinning.
public struct CloudMetadata: Sendable {
    public let membership: Bool?
    public let downloadState: CloudDownloadState
    public let uploaded: Bool?
    public let uploading: Bool?
    public let downloading: Bool?
    public let conflicts: Bool?
    /// Set to Keep Downloaded. Nil when it couldn't be read, which counts as kept.
    public let pinned: Bool?
    public init(membership: Bool?, downloadState: CloudDownloadState = .unknown,
                uploaded: Bool? = nil, uploading: Bool? = nil, downloading: Bool? = nil, conflicts: Bool? = nil, pinned: Bool? = nil) {
        self.membership = membership
        self.downloadState = downloadState
        self.uploaded = uploaded
        self.uploading = uploading
        self.downloading = downloading
        self.conflicts = conflicts
        self.pinned = pinned
    }
    public static let unknown = CloudMetadata(membership: nil)
}

public struct CloudInventoryReport: Sendable {
    public let observedAt: Date
    public let isComplete: Bool
    public let items: [FileObservation]
    public let unknownMembershipCount: Int
    public let localItemCount: Int
    public let localAllocatedBytes: Int64?
    public let observedLocalAllocatedBytes: Int64?
    public let cloudOnlyItemCount: Int
    public let cloudOnlyLogicalBytes: Int64?
    public let cloudOnlyAllocatedBytes: Int64?
    public let unknownStateCount: Int
    /// The disposable feasibility gate does not establish safe eviction/pinning.
    public var evictionAvailable: Bool { false }
}

public extension ScanResult {
    var cloudInventory: CloudInventoryReport {
        var seen = Set<String>()
        let files = observations.filter { $0.kind == .file && seen.insert($0.resourceID).inserted }
        let cloud = files.filter { $0.cloud.membership == true }
        let local = cloud.filter { $0.previewAvailability == .local && ($0.cloud.downloadState == .current || $0.cloud.downloadState == .downloaded) }
        let remote = cloud.filter { $0.previewAvailability == .nonlocal && $0.cloud.downloadState == .notDownloaded }
        let knownState = Set((local + remote).map(\.resourceID))
        func sum(_ items: [FileObservation], _ keyPath: KeyPath<FileObservation, Int64?>) -> Int64? {
            var total: Int64 = 0
            for item in items {
                guard let value = item[keyPath: keyPath] else { return nil }
                total += value
            }
            return total
        }
        let completeCloudCoverage = isComplete && !hasUnmeasuredContents
        return CloudInventoryReport(observedAt: observedAt, isComplete: completeCloudCoverage, items: cloud,
            unknownMembershipCount: files.filter { $0.cloud.membership == nil }.count,
            localItemCount: local.count, localAllocatedBytes: completeCloudCoverage ? sum(local, \.allocatedBytes) : nil,
            observedLocalAllocatedBytes: sum(local, \.allocatedBytes),
            cloudOnlyItemCount: remote.count, cloudOnlyLogicalBytes: completeCloudCoverage ? sum(remote, \.logicalBytes) : nil,
            cloudOnlyAllocatedBytes: completeCloudCoverage ? sum(remote, \.allocatedBytes) : nil,
            unknownStateCount: cloud.filter { !knownState.contains($0.resourceID) }.count)
    }
}
