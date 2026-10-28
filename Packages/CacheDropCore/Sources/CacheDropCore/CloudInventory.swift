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
    public let cloudOnlyItemCount: Int
    public let cloudOnlyLogicalBytes: Int64?
    public let unknownStateCount: Int
    /// The disposable feasibility gate does not establish safe eviction/pinning.
    public var evictionAvailable: Bool { false }
    /// Overview's iCloud total reads "Unknown" while any file's membership or download state is unknown.
    public var totalIsUnknown: Bool { unknownMembershipCount > 0 || unknownStateCount > 0 }
    /// One plain line saying why the total is Unknown (#331); nil when it isn't. Counts only, never a file list.
    public var unknownReason: String? {
        func files(_ count: Int) -> String { count == 1 ? "1 file is" : "\(count) files are" }
        let parts = [unknownMembershipCount > 0 ? "whether " + files(unknownMembershipCount) + " in iCloud" : nil,
                     unknownStateCount > 0 ? "whether " + files(unknownStateCount) + " downloaded" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : "CacheDrop couldn't tell " + parts.joined(separator: ", or ") + "."
    }
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
            cloudOnlyItemCount: remote.count, cloudOnlyLogicalBytes: completeCloudCoverage ? sum(remote, \.logicalBytes) : nil,
            unknownStateCount: cloud.filter { !knownState.contains($0.resourceID) }.count)
    }
}
