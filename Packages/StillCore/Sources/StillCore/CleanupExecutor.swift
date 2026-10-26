import Foundation
import Darwin
import os

/// The volume's available space at one moment.
public struct CapacitySample: Sendable {
    public let available: Int64?
    public let total: Int64?
    public let volumeID: String?
    public let metric: String
    public let date: Date
    public init(available: Int64?, total: Int64?, volumeID: String?, metric: String, date: Date) {
        self.available = available; self.total = total; self.volumeID = volumeID; self.metric = metric; self.date = date
    }
    /// Reads the volume holding `url`, preferring available space for important usage.
    public static func read(_ url: URL) -> CapacitySample? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey]) else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage
        return CapacitySample(available: important ?? values.volumeAvailableCapacity.map(Int64.init), total: values.volumeTotalCapacity.map(Int64.init),
                              volumeID: values.volumeUUIDString, metric: important == nil ? "available" : "important", date: Date())
    }
}

/// Moves one item to the Trash and returns where it landed. Never deletes as a fallback.
public protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws -> URL?
}
/// The Finder Trash, through a coordinated write so other apps' file presenters see the move.
public struct FinderTrash: TrashMoving {
    public init() {}
    public func moveToTrash(_ url: URL) throws -> URL? {
        var coordinationError: NSError?, operationError: Error?, resulting: URL?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinated in
            do {
                var returned: NSURL?
                try FileManager.default.trashItem(at: coordinated, resultingItemURL: &returned)
                resulting = returned as URL?
            } catch { operationError = error }
        }
        if let error = operationError ?? coordinationError { throw error }
        return resulting
    }
}

/// A confirmed, frozen set of catalog candidates.
public struct CatalogApproval: Sendable, Identifiable {
    public let id: UUID
    public let candidates: [Candidate]
    public let approvedAt: Date
    /// Decision 16: run the whole flow, change nothing on disk.
    public let previewOnly: Bool
    public init(candidates: [Candidate], previewOnly: Bool, approvedAt: Date = Date()) {
        id = UUID(); self.candidates = candidates; self.previewOnly = previewOnly; self.approvedAt = approvedAt
    }
}

public struct CatalogExecutionResult: Sendable {
    public let batchID: UUID
    public let records: [CleanupRecord]
    public let previewOnly: Bool
    public let rejectedReplay: Bool
    public let journalFailure: String?
    /// What the scan sized before cleanup (allocated where known), for the approved items.
    public let estimatedBytes: Int64
    /// Sum of the available-space change read around each removed item; nil when any reading is missing.
    public var measuredFreedBytes: Int64? {
        let removed = records.filter { $0.state == .succeeded && $0.action != CleanupAction.trash.rawValue }
        guard !previewOnly else { return nil }
        var total: Int64 = 0
        for record in removed {
            guard let change = record.itemCapacity?.observedChange else { return nil }
            total += change
        }
        return total
    }
    /// Space held in Trash, never counted as freed.
    public var movedToTrashBytes: Int64 {
        records.filter { $0.state == .succeeded && $0.action == CleanupAction.trash.rawValue }.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }
    }
}

extension CleanupRecord {
    /// A pending record for one approved candidate, written when a run claims its batch.
    public init(batchID: UUID, approvedAt: Date, candidate: Candidate, previewOnly: Bool) {
        id = batchID.uuidString + "|" + candidate.id; self.batchID = batchID; originalURL = candidate.url
        resourceID = candidate.resourceID; logicalBytes = candidate.logicalBytes; allocatedBytes = candidate.allocatedBytes
        state = .pending; trashURL = nil; message = "Approved; not started"; observedAt = candidate.observedAt
        let parent = candidate.url.deletingLastPathComponent()
        var info = stat()
        scopeURL = parent; scopeResourceID = lstat(parent.path, &info) == 0 ? "\(info.st_dev):\(info.st_ino)" : ""
        volumeID = candidate.volumeID; downloadsURL = nil; downloadsResourceID = nil
        modifiedSeconds = candidate.modifiedSeconds; modifiedNanoseconds = candidate.modifiedNanoseconds
        action = candidate.action.rawValue; policyVersion = 2; self.approvedAt = approvedAt
        ruleID = candidate.ruleID; self.previewOnly = previewOnly
    }
}

/// One executor for catalog candidates: claim, then per item record intent, recheck, act, record the outcome.
public actor CleanupExecutor {
    private static let log = Logger(subsystem: "Still", category: "cleanup")
    private let journal: any CleanupJournaling
    private let check: CandidateCheck
    private let measure: @Sendable (URL) -> CapacitySample?
    private let cancellation: CleanupCancellation
    private let trashMover: any TrashMoving
    private var running = false
    public init(journal: any CleanupJournaling, check: CandidateCheck, measure: @escaping @Sendable (URL) -> CapacitySample? = CapacitySample.read, trash: any TrashMoving = FinderTrash(), cancellation: CleanupCancellation = CleanupCancellation()) {
        self.journal = journal; self.check = check; self.measure = measure; self.trashMover = trash; self.cancellation = cancellation
    }
    public nonisolated func cancel() { cancellation.cancel() }

    public func execute(_ approval: CatalogApproval, progress: @Sendable (CleanupExecutionProgress) async -> Void = { _ in }) async -> CatalogExecutionResult {
        var seen = Set<String>()
        let estimate = approval.candidates.filter { seen.insert($0.resourceID).inserted }.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }
        func result(_ records: [CleanupRecord], replay: Bool = false, failure: String? = nil) -> CatalogExecutionResult {
            CatalogExecutionResult(batchID: approval.id, records: records, previewOnly: approval.previewOnly, rejectedReplay: replay, journalFailure: failure, estimatedBytes: estimate)
        }
        guard !running else { return result([], replay: true) }
        running = true
        defer { running = false }
        let total = approval.candidates.count
        let pending = approval.candidates.map { CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: $0, previewOnly: approval.previewOnly) }
        await progress(.init(resolved: 0, total: total, last: nil))
        do { guard try journal.claim(batchID: approval.id, records: pending) else { return result([], replay: true) } }
        catch { return result([], failure: "Could not record the cleanup. Nothing was changed.") }
        var records: [CleanupRecord] = [], failure: String?
        for (candidate, initial) in zip(approval.candidates, pending) {
            await Task.yield()
            var record = initial
            if cancellation.isCancelled || failure != nil {
                record.state = .cancelled; record.message = "Not started"
                if failure == nil { do { try journal.outcome(record) } catch { failure = "Cancellation outcome could not be recorded" } }
                records.append(record); await progress(.init(resolved: records.count, total: total, last: record)); continue
            }
            record.state = .intent; record.message = "Started; outcome not yet recorded"
            do { try journal.intent(record) }
            catch { record.state = .cancelled; record.message = "Could not record the start; not changed"; failure = record.message; records.append(record); await progress(.init(resolved: records.count, total: total, last: record)); continue }
            await perform(candidate, previewOnly: approval.previewOnly, into: &record)
            do { try journal.outcome(record) }
            catch { record.state = .unknown; record.message = "Outcome could not be recorded. Review recovery; do not repeat automatically."; failure = record.message }
            if record.state == .unknown { failure = record.message }
            records.append(record)
            await progress(.init(resolved: records.count, total: total, last: record))
        }
        return result(records, failure: failure)
    }

    private func perform(_ candidate: Candidate, previewOnly: Bool, into record: inout CleanupRecord) async {
        let command = check.catalog.rule(candidate.ruleID)?.tool
        let verb = switch candidate.action {
        case .delete: "delete"
        case .trash: "move to Trash"
        case .tool: "run " + (command?.commandLine ?? "its tool") + (command?.deletesLocationAfter == true ? ", then delete the folder" : "")
        }
        if let refusal = check.check(candidate) {
            record.state = .skipped; record.message = refusal.reason
            Self.log.info("Skipped \(candidate.url.path, privacy: .public): \(refusal.reason, privacy: .public)")
            return
        }
        if previewOnly {
            let size = ByteCountFormatter.string(fromByteCount: candidate.allocatedBytes ?? candidate.logicalBytes, countStyle: .decimal)
            record.state = .skipped; record.message = CleanupRecord.previewPrefix + " would \(verb) (\(size)). Checks passed; nothing changed."
            Self.log.info("Preview only: would \(verb, privacy: .public) \(candidate.url.path, privacy: .public), \(size, privacy: .public)")
            return
        }
        let before = measure(candidate.url.deletingLastPathComponent())
        switch candidate.action {
        case .delete: delete(candidate, into: &record)
        case .trash: trash(candidate, into: &record)
        case .tool: await runTool(candidate, command, into: &record)
        }
        if record.state == .succeeded, let before, let after = measure(candidate.url.deletingLastPathComponent()) {
            record.itemCapacity = CleanupCapacityObservation(beforeAvailable: before.available, afterAvailable: after.available, beforeTotal: before.total, afterTotal: after.total, beforeVolumeID: before.volumeID, afterVolumeID: after.volumeID, beforeMetric: before.metric, afterMetric: after.metric, beforeDate: before.date, afterDate: after.date)
        }
        let state = record.state.rawValue
        Self.log.info("\(state, privacy: .public) \(verb, privacy: .public) \(candidate.url.path, privacy: .public)")
    }

    /// Runs the rule's fixed command off the actor with its time limit, then deletes the folder if the rule says so.
    private func runTool(_ candidate: Candidate, _ command: ToolCommand?, into record: inout CleanupRecord) async {
        guard let command, let executable = candidate.toolURL else { record.state = .skipped; record.message = CheckRefusal.changed.reason; return }
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try BoundedTool.capture(executable: executable, arguments: command.arguments, timeout: command.timeout) }
        }.value
        let name = command.commandLine
        switch outcome {
        case .success(let (status, output)):
            record.toolOutput = Self.trimmed(output)
            guard status == 0 else { record.state = .failed; record.message = "\(name) exited with status \(status). The folder was left in place."; return }
            guard command.deletesLocationAfter else { record.state = .succeeded; record.message = "Ran \(name)"; return }
            var info = stat()
            if lstat(candidate.url.path, &info) != 0, errno == ENOENT { record.state = .succeeded; record.message = "Ran \(name); it removed the folder itself"; return }
            delete(candidate, into: &record)
            if record.state == .succeeded { record.message = "Ran \(name) and permanently removed the folder" }
            else { record.message = "Ran \(name). " + record.message }
        case .failure(let error as ToolTimeout):
            record.toolOutput = Self.trimmed(error.output)
            record.state = .failed
            record.message = "Stopped at the \(Int(command.timeout.rounded(.up)))-second time limit. \(name) may have cleaned part of it; the folder was left in place."
        case .failure(ToolPreviewError.unavailable):
            record.state = .skipped; record.message = "\(name) is no longer installed."
        case .failure:
            record.state = .failed; record.message = "Couldn’t run \(name). Nothing was changed."
        }
    }

    /// The last 40 lines, so the journal and results stay small.
    private static func trimmed(_ output: String) -> String? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let text = lines.suffix(40).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Renames the checked item aside atomically, confirms it is the same item, then removes it.
    private func delete(_ candidate: Candidate, into record: inout CleanupRecord) {
        let parent = candidate.url.deletingLastPathComponent()
        let aside = parent.appendingPathComponent(".still-deleting-" + UUID().uuidString)
        guard rename(candidate.url.path, aside.path) == 0 else {
            record.state = .failed; record.message = "Couldn’t remove it (\(String(cString: strerror(errno)))). Left unchanged."; return
        }
        var info = stat()
        guard lstat(aside.path, &info) == 0, "\(info.st_dev):\(info.st_ino)" == candidate.resourceID else {
            if rename(aside.path, candidate.url.path) == 0 { record.state = .skipped; record.message = CheckRefusal.changed.reason }
            else { record.state = .unknown; record.message = "Changed while starting; left at \(aside.path). Review it before cleaning again." }
            return
        }
        do {
            try FileManager.default.removeItem(at: aside)
            record.state = .succeeded; record.message = "Permanently removed"
        } catch {
            record.state = .failed; record.message = "Removed in part. The rest is at \(aside.path)."
        }
    }

    /// Moves the checked item to the Trash, then confirms the item that landed there is the one approved.
    private func trash(_ candidate: Candidate, into record: inout CleanupRecord) {
        func unchanged() -> Bool {
            var info = stat()
            return lstat(candidate.url.path, &info) == 0 && "\(info.st_dev):\(info.st_ino)" == candidate.resourceID
        }
        do {
            let resulting = try trashMover.moveToTrash(candidate.url)
            record.trashURL = resulting
            var moved = stat()
            if let resulting, lstat(resulting.path, &moved) != 0 || "\(moved.st_dev):\(moved.st_ino)" != candidate.resourceID {
                record.state = .unknown; record.message = "The item in the Trash isn’t the one approved. Review it before cleaning again."
                return
            }
            record.state = .succeeded; record.message = "Moved to Trash"
        } catch {
            record.state = unchanged() ? .failed : .unknown
            record.message = record.state == .failed ? "Couldn’t move it to Trash. Left unchanged." : "Move to Trash may be incomplete. Review it before cleaning again."
        }
    }
}
