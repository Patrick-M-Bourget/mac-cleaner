import Foundation

/// A retry is a new session draft from complete fresh observations, never an executable journal.
public struct RetryPlan: Sendable {
    public let draft: PlanDraft
    public let completedCount: Int
    public let unavailableCount: Int
    public static func prepare(records: [CleanupRecord], scans: [ScanResult], downloads: DownloadsRoot) -> RetryPlan {
        func key(_ record: CleanupRecord) -> String { record.originalURL.path + "|" + record.resourceID }
        let completed = Set(records.filter { $0.state == .succeeded }.map(key))
        var draft = PlanDraft(), unavailable = 0, considered = Set<String>()
        for record in records where record.state != .succeeded && !completed.contains(key(record)) {
            guard considered.insert(key(record)).inserted else { continue }
            guard record.action == "moveToTrash", record.policyVersion == 1,
                  record.downloadsURL == downloads.url, record.downloadsResourceID == downloads.resourceID,
                  let volume = record.volumeID,
                  let scope = try? DownloadsRoot(url: record.scopeURL), scope.resourceID == record.scopeResourceID,
                  let scan = scans.first(where: { scan in
                      guard scan.isComplete, let freshScope = try? DownloadsRoot(url: scan.scope) else { return false }
                      return freshScope.url == scope.url && freshScope.resourceID == scope.resourceID
                  }), let item = scan.observations.first(where: { $0.url.path == record.originalURL.path && $0.resourceID == record.resourceID }),
                  let candidate = try? PlanDraft.candidate(item, in: scan, downloads: downloads),
                  candidate.volumeID == volume, candidate.logicalBytes == record.logicalBytes,
                  candidate.modifiedSeconds == record.modifiedSeconds, candidate.modifiedNanoseconds == record.modifiedNanoseconds else {
                unavailable += 1; continue
            }
            do { try draft.select(item, in: scan, downloads: downloads) }
            catch { unavailable += 1 }
        }
        return .init(draft: draft, completedCount: completed.count, unavailableCount: unavailable)
    }
}
