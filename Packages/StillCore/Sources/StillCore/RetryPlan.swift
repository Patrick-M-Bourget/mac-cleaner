import Foundation

/// A retry is a new session draft from complete fresh observations, never an executable journal.
public struct RetryPlan: Sendable {
    public let draft: PlanDraft
    public let completedCount: Int
    public let unavailableURLs: [URL]
    public var unavailableCount: Int { unavailableURLs.count }
    public static func prepare(records: [CleanupRecord], scans: [ScanResult], downloads: DownloadsRoot) -> RetryPlan {
        func key(_ record: CleanupRecord) -> String { record.originalURL.path + "|" + record.resourceID }
        let completed = Set(records.filter { $0.state == .succeeded }.map(key))
        var draft = PlanDraft(), unavailable: [URL] = [], considered = Set<String>()
        var coverage: [String: (scan: ScanResult, items: [String: FileObservation])] = [:]
        for scan in scans {
            guard let scope = try? DownloadsRoot(url: scan.scope) else { continue }
            let scopeKey = scope.url.path + "|" + scope.resourceID
            if let prior = coverage[scopeKey], prior.scan.observedAt > scan.observedAt { continue }
            coverage[scopeKey] = (scan, scan.isComplete ? Dictionary(scan.observations.map { ($0.url.path + "|" + $0.resourceID, $0) }, uniquingKeysWith: { first, _ in first }) : [:])
        }
        for record in records where record.state != .succeeded && !completed.contains(key(record)) {
            guard considered.insert(key(record)).inserted else { continue }
            guard record.action == "moveToTrash", record.policyVersion == 1,
                  record.downloadsURL == downloads.url, record.downloadsResourceID == downloads.resourceID,
                  let volume = record.volumeID,
                  let scope = try? DownloadsRoot(url: record.scopeURL), scope.resourceID == record.scopeResourceID,
                  let fresh = coverage[scope.url.path + "|" + scope.resourceID], fresh.scan.isComplete, fresh.scan.observedAt >= record.approvedAt,
                  let item = fresh.items[key(record)],
                  let candidate = try? PlanDraft.freshCandidate(item, in: fresh.scan, downloads: downloads),
                  candidate.volumeID == volume, candidate.logicalBytes == record.logicalBytes,
                  candidate.modifiedSeconds == record.modifiedSeconds, candidate.modifiedNanoseconds == record.modifiedNanoseconds,
                  (try? CleanupTargetValidation.check(candidate)) != nil else {
                unavailable.append(record.originalURL); continue
            }
            draft.includeRevalidatedRetry(candidate)
        }
        return .init(draft: draft, completedCount: completed.count, unavailableURLs: unavailable)
    }
}
