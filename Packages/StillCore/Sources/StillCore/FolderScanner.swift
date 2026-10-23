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
        guard lstat(url.path, &information) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        // URL resource values can omit this optional key even for ordinary local files.
        // Use the explicit native predicate, never coalesce a missing flag to false.
        let membership = values.isUbiquitousItem ?? FileManager().isUbiquitousItem(at: url)
        var verified = stat()
        guard lstat(url.path, &verified) == 0,
              verified.st_ino == information.st_ino, verified.st_dev == information.st_dev,
              verified.st_mode & S_IFMT == information.st_mode & S_IFMT else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let dataless = information.st_flags & UInt32(SF_DATALESS) != 0
        let locality: PreviewAvailability
        if dataless || values.ubiquitousItemDownloadingStatus == .notDownloaded { locality = .nonlocal }
        else if membership == false { locality = .local }
        else if membership == true,
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
            cloud: .init(membership: membership, downloadState: downloadState,
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
    public enum Reason: String, Sendable { case entryLimit, issueLimit, depthLimit, readFailed, metadataUnavailable, differentVolume, accessDenied, accessRevoked, locationUnavailable }
    public let url: URL
    public let reason: Reason
    public var recovery: String {
        switch reason {
        case .accessDenied, .accessRevoked: "Choose this folder again, then recheck access."
        case .locationUnavailable: "Reconnect the volume or choose the folder again, then recheck."
        case .differentVolume: "Choose this volume explicitly to inspect it."
        case .entryLimit, .issueLimit, .depthLimit: "Choose a smaller folder and scan it explicitly."
        case .readFailed, .metadataUnavailable: "Recheck this location; unreadable bytes remain unknown."
        }
    }
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
    /// Known observed subtotal is not the complete scope size when coverage failed.
    public var totalLogicalBytes: Int64? { isComplete && !hasUnmeasuredContents ? logicalBytes : nil }
    public var totalAllocatedBytes: Int64? { isComplete && !hasUnmeasuredContents ? allocatedBytes : nil }
    public var hasUnmeasuredContents: Bool { observations.contains { $0.kind == .package || $0.kind == .other } }
    public let volumeAvailableMetric: String
}

/// Serial actor isolation keeps blocking enumeration off MainActor, without a task per entry.
public actor FolderScanner {
    private let maximumEntries: Int
    private let maximumIssues: Int
    private let supplement: any MetadataSupplementReading
    private let access: any ScanAccessChecking
    public init(supplement: any MetadataSupplementReading = FoundationMetadataSupplement(), maximumEntries: Int = 100_000, maximumIssues: Int = 1_000, access: any ScanAccessChecking = FoundationScanAccess()) {
        self.maximumEntries = min(max(1, maximumEntries), 100_000)
        self.maximumIssues = min(max(1, maximumIssues), 1_000)
        self.supplement = supplement
        self.access = access
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

    public func scan(_ scope: URL, cancellation: ScanCancellation? = nil, onProgress: (@Sendable (ScanProgress) -> Void)? = nil) throws -> ScanResult {
        try Self.enumerate(scope, maximumEntries: maximumEntries, maximumIssues: maximumIssues,
            supplement: supplement, access: access, cancellation: cancellation, onProgress: onProgress)
    }

    // Synchronous call from the scanner actor: remains on its executor, while the local
    // Foundation objects are confined to this nonisolated stack and autorelease pool.
    private nonisolated static func enumerate(_ scope: URL, maximumEntries: Int, maximumIssues: Int,
        supplement: any MetadataSupplementReading, access: any ScanAccessChecking,
        cancellation: ScanCancellation?, onProgress: (@Sendable (ScanProgress) -> Void)?) throws -> ScanResult {
        guard scope.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        func checkCancellation() throws {
            try Task.checkCancellation()
            if cancellation?.isCancellationRequested == true { throw CancellationError() }
        }
        try checkCancellation()
        var observations: [FileObservation] = []
        var issues: [ScanIssue] = []
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var allocationUnknown = 0
        var counted = Set<String>()
        let started = ProcessInfo.processInfo.systemUptime
        var visited = 0
        var lastProgressTime = started
        var lastProgressCount = 0
        func emitProgress(force: Bool = false) {
            guard let onProgress, observations.count > lastProgressCount else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard force || lastProgressCount == 0 || now - lastProgressTime >= 0.1 else { return }
            let start = max(lastProgressCount, observations.count - 256)
            onProgress(.init(scope: scope, visitedEntries: visited, retainedObservations: observations.count,
                knownLogicalSubtotal: logical, recentObservations: Array(observations[start...]), elapsed: now - started))
            lastProgressCount = observations.count; lastProgressTime = now
        }
        do { try access.check(scope) }
        catch { try checkCancellation(); return ScanResult(scope: scope, observedAt: Date(), observations: [], logicalBytes: 0, allocatedBytes: nil, allocatedUnknownCount: 0, volumeCapacityBytes: nil, volumeAvailableBytes: nil, issues: [.init(url: scope, reason: ScanIssue.classify(error))], volumeAvailableMetric: "Unavailable") }
        var rootMetadata = stat()
        guard scope.isFileURL, lstat(scope.path, &rootMetadata) == 0,
              (rootMetadata.st_mode & S_IFMT) == S_IFDIR else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard (try? scope.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else {
            throw CocoaError(.fileReadNoPermission)
        }
        let manager = FileManager()
        let enumerationErrors = EnumerationErrors(maximum: maximumIssues)
        guard let entries = manager.enumerator(at: scope, includingPropertiesForKeys: [.isPackageKey], options: [.skipsPackageDescendants], errorHandler: { url, error in
            if cancellation?.isCancellationRequested == true { return false }
            return enumerationErrors.append(.init(url: url, reason: ScanIssue.classify(error)))
        }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        while true {
            // Drain Foundation enumeration/resource metadata per entry. Retain a clean URL,
            // not the enumerator's prefetched NSURL and its cached metadata graph.
            let keepGoing = try autoreleasepool {
                try checkCancellation()
                guard let enumerated = entries.nextObject() as? URL else { return false }
                let url = URL(fileURLWithPath: enumerated.path)
                try checkCancellation()
                guard visited < maximumEntries else {
                    issues.append(.init(url: scope, reason: .entryLimit))
                    return false
                }
                guard issues.count < maximumIssues else {
                    issues.append(.init(url: scope, reason: .issueLimit))
                    return false
                }
                visited += 1
                guard url.standardizedFileURL.pathComponents.starts(with: scope.standardizedFileURL.pathComponents) else {
                    entries.skipDescendants()
                    return true
                }
                do { try access.check(url) }
                catch {
                    entries.skipDescendants()
                    issues.append(.init(url: url, reason: ScanIssue.classify(error)))
                    return true
                }
                var metadata = stat()
                guard lstat(url.path, &metadata) == 0 else {
                    issues.append(.init(url: url, reason: .readFailed))
                    return true
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
                    return true
                }
                let kind: ObservationKind = isPackage ? .package : isDirectory ? .folder : isFile ? .file : type == S_IFLNK ? .symbolicLink : .other
                let bytes = isFile && sameVolume ? Int64(metadata.st_size) : nil
                let identity = "\(metadata.st_dev):\(metadata.st_ino)"
                var extra: MetadataSupplement?
                if isFile && sameVolume {
                    do { extra = try supplement.read(url) }
                    catch { issues.append(.init(url: url, reason: ScanIssue.classify(error, fallback: .metadataUnavailable))) }
                }
                var afterMetadata = stat()
                guard lstat(url.path, &afterMetadata) == 0,
                      afterMetadata.st_dev == metadata.st_dev, afterMetadata.st_ino == metadata.st_ino,
                      afterMetadata.st_mode & S_IFMT == type else {
                    issues.append(.init(url: url, reason: .locationUnavailable))
                    return true
                }
                let duplicate = !counted.insert(identity).inserted
                if isFile && sameVolume && !duplicate {
                    logical += bytes ?? 0
                    if let amount = extra?.allocatedBytes { allocated += amount }
                    else { allocationUnknown += 1 }
                }
                try checkCancellation()
                observations.append(.init(id: url.path, resourceID: identity, url: url, kind: kind,
                    logicalBytes: bytes, allocatedBytes: extra?.allocatedBytes,
                    previewAvailability: extra?.locality ?? .unknown, isDuplicateResource: duplicate, cloud: extra?.cloud ?? .unknown))
                emitProgress()
                return true
            }
            if !keepGoing { break }
        }
        try checkCancellation()
        emitProgress(force: true)
        let combined = issues + enumerationErrors.issues
        if enumerationErrors.didStop || combined.count > maximumIssues {
            issues = Array(combined.prefix(maximumIssues))
            issues.append(.init(url: scope, reason: .issueLimit))
        } else { issues = combined }
        do { try access.check(scope) }
        catch { issues.append(.init(url: scope, reason: ScanIssue.classify(error))) }
        var finalRoot = stat()
        if lstat(scope.path, &finalRoot) != 0 || finalRoot.st_ino != rootMetadata.st_ino || finalRoot.st_dev != rootMetadata.st_dev {
            issues.append(.init(url: scope, reason: .locationUnavailable))
        }
        let volume = try? scope.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return ScanResult(scope: scope, observedAt: Date(), observations: observations.sorted { $0.url.path < $1.url.path },
            logicalBytes: logical, allocatedBytes: allocationUnknown == 0 ? allocated : nil, allocatedUnknownCount: allocationUnknown,
            volumeCapacityBytes: volume?.volumeTotalCapacity.map(Int64.init), volumeAvailableBytes: volume?.volumeAvailableCapacityForImportantUsage ?? volume?.volumeAvailableCapacity.map(Int64.init), issues: issues, volumeAvailableMetric: volume?.volumeAvailableCapacityForImportantUsage != nil ? "Important usage" : volume?.volumeAvailableCapacity != nil ? "Available capacity fallback" : "Unavailable")
    }
}

/// FileManager invokes its enumeration error handler synchronously on this scanner actor.
/// The collector never escapes the scan or crosses executors.
private final class EnumerationErrors: @unchecked Sendable {
    var issues: [ScanIssue] = []
    var didStop = false
    let maximum: Int
    init(maximum: Int) { self.maximum = maximum }
    func append(_ issue: ScanIssue) -> Bool {
        if issues.count < maximum { issues.append(issue) }
        if issues.count >= maximum { didStop = true; return false }
        return true
    }
}


extension ScanIssue {
    static func classify(_ error: any Error, fallback: Reason = .readFailed) -> Reason {
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain && value.code == NSFileReadNoPermissionError { return .accessDenied }
        if value.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(value.code) { return .accessDenied }
        if value.domain == NSCocoaErrorDomain && value.code == NSFileReadNoSuchFileError { return .locationUnavailable }
        if value.domain == NSPOSIXErrorDomain && [Int(ENOENT), Int(ENODEV), Int(ENXIO)].contains(value.code) { return .locationUnavailable }
        if let access = error as? ScanAccessFailure {
            switch access { case .denied: return .accessDenied; case .revoked: return .accessRevoked; case .unavailable: return .locationUnavailable }
        }
        return fallback
    }
}

public enum ScanAccessFailure: Error, Sendable { case denied, revoked, unavailable }


/// Permission/volume boundary. Returning success never grants broader scope or mutation authority.
public protocol ScanAccessChecking: Sendable { func check(_ url: URL) throws }
public struct FoundationScanAccess: ScanAccessChecking {
    public init() {}
    public func check(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
}
