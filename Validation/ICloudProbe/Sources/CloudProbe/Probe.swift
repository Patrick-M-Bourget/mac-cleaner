import Foundation

/// Observations are tri-state. Missing metadata is never equivalent to a safe value.
public struct CloudObservation: Codable, Sendable {
    public var isCloud: Bool?
    public var status: String?
    public var uploaded: Bool?
    public var uploading: Bool?
    public var downloading: Bool?
    public var conflicts: Bool?
    public var syncError: Bool?
    public init(isCloud: Bool?, status: String?, uploaded: Bool?, uploading: Bool?, downloading: Bool?, conflicts: Bool?, syncError: Bool?) {
        self.isCloud = isCloud; self.status = status; self.uploaded = uploaded
        self.uploading = uploading; self.downloading = downloading; self.conflicts = conflicts; self.syncError = syncError
    }
}
public struct CapabilityReport: Codable, Sendable {
    public let eviction: String
    public let reasons: [String]
    public let observation: CloudObservation
}
public enum CloudProbe {
    public static func assess(_ item: CloudObservation) -> CapabilityReport {
        var reasons = ["pinning-not-validated"]
        if item.isCloud != true { reasons.append("cloud-membership-unconfirmed") }
        if item.status == "notDownloaded" { reasons.append("already-placeholder") }
        else if item.status == "downloaded" { reasons.append("local-copy-stale") }
        else if item.status != "current" { reasons.append("download-status-unknown") }
        if item.uploaded != true { reasons.append("upload-incomplete-or-unknown") }
        if item.uploading != false || item.downloading != false { reasons.append("transfer-active-or-unknown") }
        if item.conflicts != false { reasons.append("conflicts-or-unknown") }
        if item.syncError != false { reasons.append("sync-error-or-unknown") }
        return CapabilityReport(eviction: "unsupported", reasons: reasons, observation: item)
    }
}

public enum ProbeError: Error { case disposableScopeRequired }
extension CloudProbe {
    /// A deliberately bounded, nonrecursive metadata probe; no content reads or mutation APIs.
    /// Caller must explicitly opt in and prepare disposable.txt beneath StillCloudProbe-<id>.
    public static func inspectDisposable(_ url: URL) throws -> CapabilityReport {
        let item = url.standardizedFileURL
        let parent = item.deletingLastPathComponent()
        guard item.isFileURL, item.lastPathComponent == "disposable.txt",
              parent.lastPathComponent.hasPrefix("StillCloudProbe-"),
              item.resolvingSymlinksInPath() == item else { throw ProbeError.disposableScopeRequired }
        let values = try item.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemUploadingErrorKey,
            .ubiquitousItemDownloadingErrorKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ProbeError.disposableScopeRequired }
        let status: String?
        switch values.ubiquitousItemDownloadingStatus {
        case .current: status = "current"
        case .downloaded: status = "downloaded"
        case .notDownloaded: status = "notDownloaded"
        default: status = nil
        }
        return assess(.init(isCloud: values.isUbiquitousItem, status: status,
            uploaded: values.ubiquitousItemIsUploaded, uploading: values.ubiquitousItemIsUploading,
            downloading: values.ubiquitousItemIsDownloading, conflicts: values.ubiquitousItemHasUnresolvedConflicts,
            syncError: values.ubiquitousItemUploadingError != nil || values.ubiquitousItemDownloadingError != nil))
    }
}
