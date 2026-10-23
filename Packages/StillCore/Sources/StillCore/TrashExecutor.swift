import Foundation
import Darwin

public enum CleanupTargetState: String, Codable, Sendable { case pending, intent, succeeded, failed, skipped, cancelled, unknown }
public struct CleanupRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let batchID: UUID
    public let originalURL: URL
    public let resourceID: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    public var state: CleanupTargetState
    public var trashURL: URL?
    public var message: String
    public let observedAt: Date
    public let scopeURL: URL
    public let scopeResourceID: String
    public let volumeID: String?
    public let downloadsURL: URL
    public let downloadsResourceID: String
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let action: String
    public let policyVersion: Int
    public var outcomeRecordedAt: Date?
    public let approvedAt: Date
    public init(batch: CleanupApproval, target: PlannedTarget) {
        id = batch.id.uuidString + "|" + target.id; batchID = batch.id; originalURL = target.url
        resourceID = target.resourceID; logicalBytes = target.logicalBytes; allocatedBytes = target.allocatedBytes
        state = .pending; trashURL = nil; message = "Approved target; operation not started"; observedAt = target.observedAt
        scopeURL = target.scopeCanonicalURL; scopeResourceID = target.scopeResourceID; volumeID = target.volumeID
        downloadsURL = target.downloadsRoot.url; downloadsResourceID = target.downloadsRoot.resourceID
        modifiedSeconds = target.modifiedSeconds; modifiedNanoseconds = target.modifiedNanoseconds
        action = batch.action; policyVersion = 1; approvedAt = batch.approvedAt
    }
}
public protocol CleanupJournaling: Sendable {
    func claim(_ batch: CleanupApproval) throws -> Bool
    func intent(_ record: CleanupRecord) throws
    func outcome(_ record: CleanupRecord) throws
    func records() throws -> [CleanupRecord]
}
public protocol TrashOperating: Sendable {
    /// Must preserve the source on failure; no permanent-delete fallback.
    func trash(_ target: PlannedTarget) throws -> URL?
}
public struct CleanupExecutionResult: Sendable {
    public let batchID: UUID
    public let targets: [CleanupRecord]
    public let rejectedReplay: Bool
    public let journalFailure: String?
    public let plannedLogicalBytes: Int64
    init(batch: CleanupApproval, targets: [CleanupRecord], rejectedReplay: Bool, journalFailure: String?) {
        batchID = batch.id; self.targets = targets; self.rejectedReplay = rejectedReplay; self.journalFailure = journalFailure
        var seen = Set<String>()
        plannedLogicalBytes = batch.targets.filter { seen.insert($0.resourceID).inserted }.reduce(0) { $0 + $1.logicalBytes }
    }
    public var trashHeldAllocatedBytes: Int64? {
        guard !targets.contains(where: { $0.state == .unknown || $0.state == .intent }) else { return nil }
        let successes = unique(targets.filter { $0.state == .succeeded })
        guard successes.allSatisfy({ $0.allocatedBytes != nil }) else { return nil }
        return successes.reduce(0) { $0 + ($1.allocatedBytes ?? 0) }
    }
    private func unique(_ records: [CleanupRecord]) -> [CleanupRecord] {
        var seen = Set<String>(); return records.filter { seen.insert($0.resourceID).inserted }
    }
}
public enum CleanupValidationError: Error { case changedOrProtected }

/// Validation uses descriptor-relative ancestry and never opens file contents.
public enum CleanupTargetValidation {
    public static func check(_ target: PlannedTarget) throws {
        let invalid = CleanupValidationError.changedOrProtected
        let root = target.downloadsRoot
        let rootParts = root.url.pathComponents, parts = target.url.pathComponents
        let scopeParts = target.scopeCanonicalURL.pathComponents
        guard target.url.isFileURL, parts.starts(with: rootParts), parts.starts(with: scopeParts),
              scopeParts.starts(with: rootParts), parts.count > rootParts.count else { throw invalid }
        let rootFD = openCanonicalDirectory(root.url)
        guard rootFD >= 0 else { throw invalid }
        defer { close(rootFD) }
        var info = stat()
        guard fstat(rootFD, &info) == 0, identity(info) == root.resourceID else { throw invalid }
        var scopeInfo = stat()
        guard lstat(target.scopeCanonicalURL.path, &scopeInfo) == 0, scopeInfo.st_mode & S_IFMT == S_IFDIR, identity(scopeInfo) == target.scopeResourceID else { throw invalid }
        let device = info.st_dev
        let protectedExtensions = Set(["app", "bundle", "framework", "xcarchive", "dsym", "photoslibrary", "photolibrary", "musiclibrary", "library", "backupbundle", "sparsebundle", "band", "logicx", "db", "sqlite", "sqlite3"])
        var parent = rootFD
        var opened: [Int32] = []
        defer { for fd in opened.reversed() { close(fd) } }
        let relative = Array(parts.dropFirst(rootParts.count))
        for (index, part) in relative.enumerated() {
            guard ![".", "..", ".git", ".Trash", "Backups.backupdb"].contains(part),
                  !protectedExtensions.contains(URL(fileURLWithPath: part).pathExtension.lowercased()) else { throw invalid }
            guard fstatat(parent, part, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_dev == device else { throw invalid }
            if index < relative.count - 1 {
                guard info.st_mode & S_IFMT == S_IFDIR else { throw invalid }
                let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw invalid }
                var openedInfo = stat()
                guard fstat(next, &openedInfo) == 0, identity(openedInfo) == identity(info) else { close(next); throw invalid }
                opened.append(next); parent = next
            } else {
                guard info.st_mode & S_IFMT == S_IFREG, identity(info) == target.resourceID,
                      Int64(info.st_size) == target.logicalBytes,
                      Int64(info.st_mtimespec.tv_sec) == target.modifiedSeconds,
                      Int64(info.st_mtimespec.tv_nsec) == target.modifiedNanoseconds,
                      info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND | SF_DATALESS) == 0,
                      info.st_mode & 0o444 != 0, faccessat(parent, part, R_OK, 0) == 0,
                      faccessat(parent, ".", W_OK | X_OK, 0) == 0 else { throw invalid }
            }
        }
        // Metadata-only cloud predicate; identity checked again after the path-based metadata call.
        guard !FileManager.default.isUbiquitousItem(at: target.url),
              try target.url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString == target.volumeID else { throw invalid }
        var final = stat()
        guard lstat(target.url.path, &final) == 0, identity(final) == target.resourceID,
              final.st_mode & S_IFMT == S_IFREG, final.st_size == info.st_size,
              final.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw invalid }
    }
    private static func openCanonicalDirectory(_ url: URL) -> Int32 {
        var parent = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { return -1 }
        for component in url.pathComponents.dropFirst() {
            guard component != ".", component != ".." else { close(parent); return -1 }
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(parent)
            guard next >= 0 else { return -1 }
            parent = next
        }
        return parent
    }
    private static func identity(_ info: stat) -> String { "\(info.st_dev):\(info.st_ino)" }
}

public struct TrashOperationUncertain: Error, Sendable {
    public let resultingURL: URL?
    public init(resultingURL: URL?) { self.resultingURL = resultingURL }
}
public struct NativeTrashOperation: TrashOperating {
    public init() {}
    public func trash(_ target: PlannedTarget) throws -> URL? {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?, operationError: Error?, resulting: URL?
        coordinator.coordinate(writingItemAt: target.url, options: .forDeleting, error: &coordinationError) { coordinated in
            do {
                guard coordinated.standardizedFileURL == target.url.standardizedFileURL else { throw CleanupValidationError.changedOrProtected }
                try CleanupTargetValidation.check(target)
                var returned: NSURL?
                do { try FileManager.default.trashItem(at: coordinated, resultingItemURL: &returned) }
                catch {
                    guard (try? CleanupTargetValidation.check(target)) != nil else { throw TrashOperationUncertain(resultingURL: returned as URL?) }
                    throw error
                }
                resulting = returned as URL?
                if let resulting {
                    var moved = stat()
                    guard lstat(resulting.path, &moved) == 0, "\(moved.st_dev):\(moved.st_ino)" == target.resourceID else { throw TrashOperationUncertain(resultingURL: resulting) }
                }
            } catch { operationError = error }
        }
        if let error = operationError ?? coordinationError { throw error }
        return resulting
    }
}

public final class CleanupCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
public actor TrashExecutor {
    private let journal: any CleanupJournaling
    private let operation: any TrashOperating
    private let cancellation: CleanupCancellation
    private var running = false
    public init(journal: any CleanupJournaling, operation: any TrashOperating = NativeTrashOperation(), cancellation: CleanupCancellation = CleanupCancellation()) { self.journal = journal; self.operation = operation; self.cancellation = cancellation }
    public nonisolated func cancel() { cancellation.cancel() }
    public func execute(_ batch: CleanupApproval) async -> CleanupExecutionResult {
        guard !running else { return .init(batch: batch, targets: [], rejectedReplay: true, journalFailure: nil) }
        running = true
        defer { running = false }
        var records: [CleanupRecord] = [], failure: String?
        do {
            guard try journal.claim(batch) else { return .init(batch: batch, targets: [], rejectedReplay: true, journalFailure: nil) }
        } catch { return .init(batch: batch, targets: [], rejectedReplay: false, journalFailure: "Could not commit batch. No files were moved.") }
        for target in batch.targets {
            await Task.yield()
            var record = CleanupRecord(batch: batch, target: target)
            if cancellation.isCancelled || failure != nil {
                record.state = .cancelled; record.message = "Not started"
                if failure == nil {
                    do { try journal.outcome(record) } catch { failure = "Cancellation outcome could not be committed" }
                }
                records.append(record); continue
            }
            record.state = .intent; record.message = "Operation intent recorded; outcome unresolved"
            do { try journal.intent(record) }
            catch { record.state = .cancelled; record.message = "Intent could not be committed; no operation started"; failure = record.message; records.append(record); continue }
            let access = target.scope.startAccessingSecurityScopedResource()
            do {
                try CleanupTargetValidation.check(target)
                do {
                    record.trashURL = try operation.trash(target); record.state = .succeeded
                    record.message = record.trashURL == nil ? "Moved to Trash; resulting location unavailable" : "Moved to Trash"
                } catch let uncertain as TrashOperationUncertain { record.state = .unknown; record.trashURL = uncertain.resultingURL; record.message = "Native outcome is uncertain; do not repeat automatically" }
                catch is CleanupValidationError { record.state = .skipped; record.message = "Target changed before native Trash; not moved" }
                catch {
                    if (try? CleanupTargetValidation.check(target)) != nil {
                        record.state = .failed; record.message = "Trash operation failed; original still matches"
                    } else {
                        record.state = .unknown; record.message = "Operation threw and the original no longer matches; outcome unknown"
                    }
                }
            } catch { record.state = .skipped; record.message = "Changed, unavailable or protected target; not moved" }
            if access { target.scope.stopAccessingSecurityScopedResource() }
            do { try journal.outcome(record) }
            catch {
                record.state = .unknown; record.message = "Outcome could not be committed. Review recovery; do not repeat automatically."
                failure = record.message
            }
            if record.state == .unknown { failure = record.message }
            records.append(record)
        }
        return .init(batch: batch, targets: records, rejectedReplay: false, journalFailure: failure)
    }
}
