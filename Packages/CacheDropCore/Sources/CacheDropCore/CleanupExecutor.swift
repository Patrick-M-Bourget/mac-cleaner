import Foundation
import Darwin
import os

/// A confirmed, frozen set of catalog candidates.
public struct CatalogApproval: Sendable, Identifiable {
    public let id: UUID
    public let candidates: [Candidate]
    public let approvedAt: Date
    /// Decision 27: the Settings dry-run switch runs the flow without changing anything on disk.
    public let dryRun: Bool
    public init(candidates: [Candidate], dryRun: Bool, approvedAt: Date = Date()) {
        id = UUID(); self.candidates = candidates; self.dryRun = dryRun; self.approvedAt = approvedAt
    }
}

extension Array where Element == CleanupRecord {
    /// True when the run moved something to the Trash and removed nothing else: nothing is freed until the Trash is emptied,
    /// so Results and History show no measured freed space (Decision 66).
    public var movedOnlyToTrash: Bool {
        let succeeded = filter { $0.state == .succeeded }
        return succeeded.contains { $0.cleanupAction == .trash } && succeeded.allSatisfy { $0.cleanupAction == .trash }
    }
    /// The sum of the available-space change read around each removed item; nil when any reading is missing. A Trash move
    /// frees nothing yet, and an item that finished after the stop (#209) freed its space where nothing measured it. Results,
    /// History and Empty from Trash all read it (#433).
    var measuredFreedBytes: Int64? {
        var total: Int64 = 0
        for record in self where record.state == .succeeded && record.cleanupAction != .trash && !record.finishedAfterStop {
            guard let change = record.itemCapacity?.observedChange else { return nil }
            total += change
        }
        return total
    }
}

/// How a measured freed space is shown (#418): never below 0. Other activity can move free space the other way while an
/// item's space hasn't reached macOS yet (Docker's, #411); Results' line under it says how it was measured (#577).
public enum MeasuredFreedSpace {
    public static func shown(_ measured: Int64?) -> Int64? { measured.map { max(0, $0) } }
}

public struct CatalogExecutionResult: Sendable {
    public let batchID: UUID
    public let records: [CleanupRecord]
    public let dryRun: Bool
    public let rejectedReplay: Bool
    public let journalFailure: String?
    /// What the scan sized before cleanup (allocated where known), for the approved items.
    public let estimatedBytes: Int64
    /// Sum of the available-space change read around each removed item; nil when any reading is missing.
    public var measuredFreedBytes: Int64? { dryRun ? nil : records.measuredFreedBytes }
    /// Results' line under the measured freed space once the disk was read again a minute after completed Docker prunes
    /// (#411). It isn't added to the measured freed space. Before the check (`checked` false) there is none; a check that
    /// couldn't read the disk says so, so Results' "check again" is always answered.
    public func settledLine(checked: Bool) -> String? {
        if let change = records.lazy.compactMap({ $0.settledCapacity?.observedChange }).first {
            return change > 0 ? SizeFormatter.text(change) + " more free a minute later" : "No more free space a minute later"
        }
        return checked ? "Couldn’t check the disk again a minute later" : nil
    }
    /// The candidates the run cleaned, or would have in a dry run, by id: they leave every page's selection (#349).
    public var cleanedCandidateIDs: [String] { records.filter { $0.state == .succeeded || $0.wasDryRun }.map(\.candidateID) }
    /// The rows the pages keep, dimmed, while the rescan after this run runs (#375): what they showed, minus what the run
    /// cleaned, so a cleaned item never shows as still there and the rest never vanish until the rescan replaces them.
    /// A dry run changed nothing, so it keeps every row.
    public func keptDuringRescan(_ shown: [Candidate]) -> [Candidate] {
        guard !dryRun else { return shown }
        let cleaned = Set(cleanedCandidateIDs)
        return shown.filter { !cleaned.contains($0.id) }
    }
    /// Whether the run may have changed what the Applications page lists (Decision 123, #556): an app, plug-in or file from a
    /// deleted app it may have acted on, or any other item that is, or holds, one of the `listing` paths the page lists (an
    /// app in Downloads). Only an item the checks refused, or one never started, is known to be as it was; a dry run changed
    /// nothing.
    public func changesApplications(listing: [URL]) -> Bool {
        guard !dryRun else { return false }
        let acted = records.filter { $0.state != .skipped && $0.state != .pending }
        if acted.contains(where: { $0.ruleID.flatMap(AppRuleFamily.of(ruleID:)) != nil }) { return true }
        let listed = listing.map(\.standardizedFileURL.path)
        return acted.contains { record in
            let path = record.originalURL.standardizedFileURL.path
            return listed.contains { $0 == path || $0.hasPrefix(path + "/") }
        }
    }
    /// Space held in Trash, never counted as freed.
    public var movedToTrashBytes: Int64 {
        records.filter { $0.state == .succeeded && $0.cleanupAction == .trash }.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }
    }
}

extension CleanupRecord {
    /// A record's id: its batch, then the candidate it was approved for (`batchID|candidateID`).
    static func id(batchID: UUID, candidateID: String) -> String { batchID.uuidString + "|" + candidateID }
    /// The id of the candidate this record was approved for, read back from `id`.
    var candidateID: String { String(id.dropFirst(batchID.uuidString.count + 1)) }

    /// A pending record for one approved candidate, written when a run claims its batch.
    public init(batchID: UUID, approvedAt: Date, candidate: Candidate, dryRun: Bool) {
        id = Self.id(batchID: batchID, candidateID: candidate.id); self.batchID = batchID; originalURL = candidate.url
        resourceID = candidate.resourceID; logicalBytes = candidate.logicalBytes; allocatedBytes = candidate.allocatedBytes
        state = .pending; trashURL = nil; message = "Not started"; observedAt = candidate.observedAt
        let parent = candidate.url.deletingLastPathComponent()
        var info = stat()
        scopeURL = parent; scopeResourceID = lstat(parent.path, &info) == 0 ? info.resourceID : ""
        volumeID = candidate.volumeID; downloadsURL = nil; downloadsResourceID = nil
        modifiedSeconds = candidate.modifiedSeconds; modifiedNanoseconds = candidate.modifiedNanoseconds
        action = candidate.action.rawValue; policyVersion = 2; self.approvedAt = approvedAt
        ruleID = candidate.ruleID; self.dryRun = dryRun
        itemName = candidate.itemName; toolItem = candidate.toolItem
    }
}

/// One executor for catalog candidates: claim, then per item record intent, recheck, act, record the outcome.
public actor CleanupExecutor {
    private static let log = Logger(subsystem: "CacheDrop", category: "cleanup")
    private let journal: any CleanupJournaling
    private let check: CandidateCheck
    private let measure: @Sendable (URL) -> CapacitySample?
    private let cancellation: CleanupCancellation
    private let trashMover: any TrashMoving
    private let clock: @Sendable () -> Date
    private var running = false
    /// How old a reading of what processes have open may be before an item that needs the in-use check reads it again
    /// (SPEC section 4). A long step, such as a tool with a 600-second limit, would otherwise leave later items checked
    /// against what was open when the run began.
    public static let inUseReadingMaxAge: TimeInterval = 5
    public init(journal: any CleanupJournaling, check: CandidateCheck, measure: @escaping @Sendable (URL) -> CapacitySample? = CapacitySample.read, trash: any TrashMoving = FinderTrash(), cancellation: CleanupCancellation = CleanupCancellation(),
                clock: @escaping @Sendable () -> Date = Date.init) {
        self.journal = journal; self.check = check; self.measure = measure; self.trashMover = trash; self.cancellation = cancellation; self.clock = clock
    }
    public nonisolated func cancel() { cancellation.cancel() }

    /// Claims an approval once, then rechecks, journals and acts on each item, reporting dry-run or measured outcomes.
    public func execute(_ approval: CatalogApproval, progress: @Sendable (CleanupExecutionProgress) async -> Void = { _ in }) async -> CatalogExecutionResult {
        var seen = Set<String>()
        let estimate = approval.candidates.filter { seen.insert(check.catalog.spaceKey(of: $0)).inserted }.reduce(Int64(0)) { $0 + $1.estimatedBytes }
        func result(_ records: [CleanupRecord], replay: Bool = false, failure: String? = nil) -> CatalogExecutionResult {
            CatalogExecutionResult(batchID: approval.id, records: records, dryRun: approval.dryRun, rejectedReplay: replay, journalFailure: failure, estimatedBytes: estimate)
        }
        guard !running else { return result([], replay: true) }
        running = true
        defer { running = false }
        let total = approval.candidates.count
        let pending = approval.candidates.map { CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: $0, dryRun: approval.dryRun) }
        await progress(.init(resolved: 0, total: total, last: nil))
        do { guard try journal.claim(batchID: approval.id, records: pending) else { return result([], replay: true) } }
        catch { return result([], failure: "CacheDrop couldn’t save the cleanup before starting, so nothing was changed.") }
        var records: [CleanupRecord] = [], failure: String?
        // One reading of what processes have open serves many items, but never one older than `inUseReadingMaxAge`.
        var reading: (check: CandidateCheck, takenAt: Date)?
        for (candidate, initial) in zip(approval.candidates, pending) {
            await Task.yield()
            var record = initial
            if cancellation.isCancelled || failure != nil {
                record.state = .cancelled; record.message = "Not started"
                if failure == nil { do { try journal.outcome(record) } catch { failure = "CacheDrop couldn’t save that the cleanup stopped." } }
                records.append(record); await progress(.init(resolved: records.count, total: total, last: record)); continue
            }
            record.state = .intent; record.message = "Started · Outcome unknown"
            do { try journal.intent(record) }
            catch { record.state = .cancelled; record.message = "CacheDrop couldn’t save its progress, so it stopped. This item wasn’t changed."; failure = record.message; records.append(record); await progress(.init(resolved: records.count, total: total, last: record)); continue }
            if self.check.needsInUseCheck(candidate), reading.map({ clock().timeIntervalSince($0.takenAt) > Self.inUseReadingMaxAge }) ?? true {
                reading = (self.check.snapshotted(), clock())
            }
            await perform(candidate, check: reading?.check ?? self.check, dryRun: approval.dryRun, into: &record)
            do { try journal.outcome(record) }
            catch { record.state = .unknown; record.message = "CacheDrop couldn’t save what happened. Review the interrupted cleanup before cleaning again."; failure = record.message }
            if record.state == .unknown { failure = record.message }
            records.append(record)
            await progress(.init(resolved: records.count, total: total, last: record))
        }
        return result(records, failure: failure)
    }

    /// How long after a run a stopped daemon-backed tool's item is measured again (#190): long enough for a daemon to
    /// finish a typical removal, short enough that the results are still open.
    public static let laterMeasurementDelay: Duration = .seconds(60)
    /// When an item still shrinking at `laterMeasurementDelay` is measured the second and last time, after the run (#209):
    /// Docker's prunes can take minutes.
    public static let lastLaterMeasurementDelay: Duration = .seconds(300)

    /// Waits for real; false when the wait was cancelled.
    public static let sleeping: @Sendable (Duration) async -> Bool = { (try? await Task.sleep(for: $0)) != nil }

    /// After `result`, waits, checks free space after a completed Docker prune (#411), and remeasures stopped daemon-backed
    /// items with `measure`, recording the findings (#190). An item still shrinking compared with its size at the
    /// scan is measured once more at `lastLaterMeasurementDelay`; `update` gets the result in between (#209). The outcome
    /// recorded at the stop follows the measurement (#209): an item found gone becomes removed, finished after the stop;
    /// one with some of it left stays partly removed. Bounded: at most two waits per run and two measurements per item,
    /// never a retry. Returns `result` unchanged when nothing needs it, the wait was cancelled, or the journal couldn't record it.
    public func measureAgainLater(_ result: CatalogExecutionResult, of approval: CatalogApproval,
                                  wait: @Sendable (Duration) async -> Bool = CleanupExecutor.sleeping,
                                  update: @Sendable (CatalogExecutionResult) async -> Void = { _ in },
                                  measure: @Sendable ([Candidate]) async -> [String: LaterMeasurement.Finding]) async -> CatalogExecutionResult {
        let stopped = Set(result.records.filter(\.awaitsLaterMeasurement).map(\.id))
        let first = await measureAgain(stopped, in: result, of: approval, after: Self.laterMeasurementDelay, waiting: Self.laterMeasurementDelay,
                                       settling: settlingRecord(of: result)?.id, wait: wait, measure: measure)
        // Still shrinking: some went since the scan, and some is left.
        let shrinking = Set(first.records.filter { record in
            guard stopped.contains(record.id), case .remaining(let bytes)? = record.laterMeasurement?.finding else { return false }
            return bytes < (record.allocatedBytes ?? record.logicalBytes)
        }.map(\.id))
        guard !shrinking.isEmpty else { return first }
        await update(first)
        return await measureAgain(shrinking, in: first, of: approval, after: Self.lastLaterMeasurementDelay,
                                  waiting: Self.lastLaterMeasurementDelay - Self.laterMeasurementDelay, wait: wait, measure: measure)
    }

    /// Whether `measureAgainLater` has anything to do for `result`: a stopped daemon-backed item, or a completed Docker prune.
    public nonisolated func measuresLater(_ result: CatalogExecutionResult) -> Bool {
        result.records.contains(where: \.awaitsLaterMeasurement) || settlingRecord(of: result) != nil
    }

    /// Whether the disk is still to be read again a minute after `result`'s completed Docker prunes (#411): Results say a
    /// check is coming until it's done.
    public nonisolated func settles(_ result: CatalogExecutionResult) -> Bool { settlingRecord(of: result) != nil }

    /// The run's last completed Docker prune with its available space read (#411): Docker hands freed space back to macOS
    /// after the prune returns, so the disk is read once more a minute after the run and this record keeps what more was free.
    private nonisolated func settlingRecord(of result: CatalogExecutionResult) -> CleanupRecord? {
        guard !result.dryRun else { return nil }
        let last = result.records.last { record in
            record.state == .succeeded && record.mayStillBeFinishing != true && record.itemCapacity != nil && check.catalog.isDocker(record.ruleID)
        }
        return last?.settledCapacity == nil ? last : nil
    }

    /// One wait, then one measurement of the records `ids` names, journaled, and the disk's available space read again for
    /// the record `settling` names. A finding that couldn't be measured never replaces an earlier one.
    private func measureAgain(_ ids: Set<String>, in result: CatalogExecutionResult, of approval: CatalogApproval, after: Duration, waiting: Duration,
                              settling: String? = nil, wait: @Sendable (Duration) async -> Bool,
                              measure: @Sendable ([Candidate]) async -> [String: LaterMeasurement.Finding]) async -> CatalogExecutionResult {
        let candidates = approval.candidates.filter { ids.contains(CleanupRecord.id(batchID: approval.id, candidateID: $0.id)) }
        guard !candidates.isEmpty || settling != nil, await wait(waiting) else { return result }
        let findings = candidates.isEmpty ? [:] : await measure(candidates)
        let measuredAt = clock()
        var records = result.records
        if let index = records.firstIndex(where: { $0.id == settling }), let withReading = settled(records[index], after: records, of: approval) {
            // Shown only once the journal has it, as below.
            if (try? journal.outcome(withReading)) != nil { records[index] = withReading }
        }
        for index in records.indices where ids.contains(records[index].id) {
            var record = records[index]
            let finding = findings[record.candidateID] ?? .unmeasured
            if finding == .unmeasured, record.laterMeasurement != nil { continue }
            record.laterMeasurement = LaterMeasurement(measuredAt: measuredAt, finding: finding, afterSeconds: Int(after.components.seconds))
            if finding == .gone {
                record.state = .succeeded; record.partlyRemoved = nil; record.message = CleanupRecord.finishedAfterStopMessage
            }
            // Shown only once the journal has it, so Results and History never disagree.
            do { try journal.outcome(record); records[index] = record } catch { continue }
        }
        return CatalogExecutionResult(batchID: result.batchID, records: records, dryRun: result.dryRun, rejectedReplay: result.rejectedReplay,
                                      journalFailure: result.journalFailure, estimatedBytes: result.estimatedBytes)
    }

    /// `record` with the disk's available space now, against the run's last reading: items after Docker's (simulators,
    /// Android) freed space the run already counted. Nil without a reading.
    private func settled(_ record: CleanupRecord, after run: [CleanupRecord], of approval: CatalogApproval) -> CleanupRecord? {
        guard let after = run.last(where: { $0.itemCapacity != nil })?.itemCapacity, let candidate = approval.candidates.first(where: { $0.id == record.candidateID }),
              let now = self.measure(candidate.url.deletingLastPathComponent()) else { return nil }
        var settled = record
        settled.settledCapacity = after.continued(to: now)
        return settled
    }

    private func perform(_ candidate: Candidate, check: CandidateCheck, dryRun: Bool, into record: inout CleanupRecord) async {
        let command = check.catalog.rule(candidate.ruleID)?.tool
        let verb = switch candidate.action {
        case .delete: "delete"
        case .trash: "move to Trash"
        case .evict: "remove the local copy"
        case .guidance: "change nothing (guidance only)"
        case .tool: "run " + (command?.commandLine(for: candidate.toolArgument) ?? "its tool") + (command?.deletesLocationAfter == true ? ", then delete the folder" : "")
        }
        if let refusal = check.check(candidate) {
            record.state = .skipped; record.message = refusal.reason
            Self.log.info("Skipped \(candidate.url.path, privacy: .public): \(refusal.reason, privacy: .public)")
            return
        }
        if dryRun {
            let size = SizeEstimate(candidate).text
            record.state = .skipped; record.message = CleanupRecord.previewPrefix + " would \(verb) (\(size)). Checks passed; nothing changed."
            Self.log.info("Dry run: would \(verb, privacy: .public) \(candidate.url.path, privacy: .public), \(size, privacy: .public)")
            return
        }
        let before = measure(candidate.url.deletingLastPathComponent())
        switch candidate.action {
        case .delete: delete(candidate, into: &record)
        case .trash:
            trash(candidate, into: &record)
            if record.state == .succeeded, check.catalog.rule(candidate.ruleID)?.items == .androidVirtualDevices { trashIniFile(of: candidate, into: &record) }
        case .tool: await runTool(candidate, command, into: &record)
        case .evict: evict(candidate, into: &record)
        // The check refuses guidance first; this stays a refusal if it ever doesn't.
        case .guidance: record.state = .skipped; record.message = CheckRefusal.guidanceOnly.reason
        }
        if record.state == .succeeded, let before, let after = measure(candidate.url.deletingLastPathComponent()) {
            record.itemCapacity = CleanupCapacityObservation(from: before, to: after)
        }
        let state = record.state.rawValue
        Self.log.info("\(state, privacy: .public) \(verb, privacy: .public) \(candidate.url.path, privacy: .public)")
    }

    /// Runs the rule's fixed command off the actor with its time limit, then deletes the folder if the rule says so.
    private func runTool(_ candidate: Candidate, _ command: ToolCommand?, into record: inout CleanupRecord) async {
        guard let command, let executable = candidate.toolURL, let arguments = command.arguments(for: candidate.toolArgument) else {
            record.state = .skipped; record.message = CheckRefusal.changed.reason; return
        }
        let cancellation = self.cancellation
        // The tool's own folder goes first on PATH, so `#!/usr/bin/env node` tools such as pnpm find their runtime.
        var environment = BoundedTool.defaultEnvironment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        let outcome = await Self.onOwnThread { [environment] in
            Result { try BoundedTool.capture(executable: executable, arguments: arguments, timeout: command.timeout, environment: environment, cancellation: cancellation) }
        }
        let name = command.commandLine(for: candidate.toolArgument)
        switch outcome {
        case .success(let (status, output)):
            record.toolOutput = Self.trimmed(output)
            guard status == 0 else {
                // The tool may have removed some files before it failed.
                record.state = .failed; record.partlyRemoved = true
                record.message = "\(name) exited with status \(status). It may have cleaned part of it" + (candidate.isDirectory ? "; the folder was left in place." : "."); return
            }
            guard command.deletesLocationAfter else { record.state = .succeeded; record.message = "Ran \(name)"; return }
            // A cancel that landed as the tool finished starts no new destructive step (#195).
            guard !cancellation.isCancelled else { record.state = .succeeded; record.message = "Ran \(name). Stopped before removing the folder, since you canceled."; return }
            var info = stat()
            if lstat(candidate.url.path, &info) != 0, errno == ENOENT { record.state = .succeeded; record.message = "Ran \(name); it removed the folder itself"; return }
            delete(candidate, into: &record)
            if record.state == .succeeded { record.message = "Ran \(name) and deleted the folder" }
            else { record.message = "Ran \(name). " + record.message }
        case .failure(let error as ToolTimeout):
            Self.recordStopped(.timeLimit(seconds: Int(command.timeout.rounded(.up))), output: error.output, command: command, name: name, candidate: candidate, into: &record)
        case .failure(let error as ToolCancelled) where !error.started:
            record.state = .cancelled; record.message = "Stopped before \(name) started. Nothing was changed."
        case .failure(let error as ToolCancelled):
            Self.recordStopped(.cancelled, output: error.output, command: command, name: name, candidate: candidate, into: &record)
        case .failure(ToolDryRunError.unavailable):
            record.state = .skipped; record.message = "\(name) is no longer installed."
        case .failure:
            record.state = .failed; record.message = "Couldn’t run \(name). Nothing was changed."
        }
    }

    /// Runs `work`, which blocks for as long as a tool runs (up to its time limit), on a thread of its own and resumes with its result.
    /// Never on the Swift concurrency pool, whose few threads a long `brew cleanup` would otherwise hold (#200).
    private static func onOwnThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    /// What stopped a tool before it finished.
    private enum StopCause {
        case timeLimit(seconds: Int), cancelled
        /// How results say it: "Stopped at the 300-second time limit", "Stopped waiting when you canceled".
        var phrase: String {
            switch self {
            case .timeLimit(let seconds): "at the \(seconds)-second time limit"
            case .cancelled: "when you canceled"
            }
        }
    }
    /// A tool stopped before it finished (time limit or cancel) ran until then, so it may have removed some files;
    /// the folder is never deleted after it. A daemon-backed tool's work goes on without it (SPEC section 3),
    /// so only the wait stopped and the work may still be finishing.
    private static func recordStopped(_ cause: StopCause, output: String, command: ToolCommand, name: String, candidate: Candidate, into record: inout CleanupRecord) {
        record.toolOutput = trimmed(output)
        record.state = .failed; record.partlyRemoved = true
        if command.daemonBacked { record.mayStillBeFinishing = true }
        let effect = command.daemonBacked ? "Stopped waiting \(cause.phrase). \(name) hands its work to a background service, which may still be finishing"
                                          : "Stopped \(cause.phrase). \(name) may have cleaned part of it"
        record.message = effect + (candidate.isDirectory ? "; the folder was left in place." : ".")
    }

    /// The last 40 lines, so the journal and results stay small.
    private static func trimmed(_ output: String) -> String? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let text = lines.suffix(40).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Renames the checked item aside atomically, confirms it is the same item, then removes it. The rename goes
    /// through a descriptor for the parent opened from the scope root without following symlinks, so a folder
    /// swapped for a symlink after the check is never renamed.
    private func delete(_ candidate: Candidate, into record: inout CleanupRecord) {
        let parent = candidate.url.deletingLastPathComponent(), name = candidate.url.lastPathComponent
        let asideName = Catalog.deletionRemnantName(for: candidate.ruleID)
        let aside = parent.appendingPathComponent(asideName)
        let parentFD = candidate.scopeRoot.map { ScopeContainment.openParent(of: candidate.url, in: $0) } ?? -1
        guard parentFD >= 0 else { record.state = .skipped; record.message = CheckRefusal.changed.reason; return }
        defer { close(parentFD) }
        guard renameat(parentFD, name, parentFD, asideName) == 0 else {
            record.state = .failed; record.message = "Couldn’t remove it (\(String(cString: strerror(errno)))). Left unchanged."; return
        }
        var info = stat()
        guard fstatat(parentFD, asideName, &info, AT_SYMLINK_NOFOLLOW) == 0, info.resourceID == candidate.resourceID else {
            if renameat(parentFD, asideName, parentFD, name) == 0 { record.state = .skipped; record.message = CheckRefusal.changed.reason }
            else { record.state = .unknown; record.message = "Changed while starting; left at \(aside.path). Review it before cleaning again." }
            return
        }
        do {
            try FileManager.default.removeItem(at: aside)
            record.state = .succeeded; record.message = "Deleted"
        } catch {
            // Never "not changed": part of it is gone. The rest is offered again on the next scan, under the same rule.
            record.state = .failed; record.partlyRemoved = true
            record.message = "Partly removed. The rest is at \(aside.path); CacheDrop offers it again on the next scan."
        }
    }

    /// Confirms the item is still the approved one, inside its scope, just before moving it to the Trash, then
    /// confirms the item that landed in the Trash is the one approved. A swap in the moment between that last check
    /// and `trashItem` is an accepted race: the Trash is recoverable, and the check after the move reports it.
    private func trash(_ candidate: Candidate, into record: inout CleanupRecord) {
        func unchanged() -> Bool {
            var info = stat()
            return lstat(candidate.url.path, &info) == 0 && info.resourceID == candidate.resourceID
        }
        guard unchanged(), let root = candidate.scopeRoot, ScopeContainment.contains(candidate.url, in: root) else {
            record.state = .skipped; record.message = CheckRefusal.changed.reason; return
        }
        do {
            let resulting = try trashMover.moveToTrash(candidate.url)
            record.trashURL = resulting
            var moved = stat()
            if let resulting, lstat(resulting.path, &moved) != 0 || moved.resourceID != candidate.resourceID {
                record.state = .unknown; record.message = "The item in the Trash isn’t the one you chose. Review it before cleaning again."
                return
            }
            record.state = .succeeded; record.message = "Moved to Trash"
        } catch {
            record.state = unchanged() ? .failed : .unknown
            record.message = record.state == .failed ? "Couldn’t move it to Trash. Left unchanged." : "Move to Trash may be incomplete. Review it before cleaning again."
        }
    }

    /// An Android virtual device's `<name>.ini` follows its folder to the Trash, so Android Studio doesn't list a broken device.
    private func trashIniFile(of candidate: Candidate, into record: inout CleanupRecord) {
        let ini = AndroidSDK.iniFile(of: candidate.url)
        var info = stat()
        guard lstat(ini.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { return }
        do { _ = try trashMover.moveToTrash(ini); record.message = "Moved to Trash with \(ini.lastPathComponent)" }
        catch { record.message = "Moved to Trash. Couldn’t move \(ini.lastPathComponent); Android Studio may list the device as broken." }
    }

    /// Removes only local copies: the file or package itself, or each qualifying file in a folder, each read again
    /// just before it is evicted. The originals stay in iCloud. Downloads stay blocked throughout.
    private func evict(_ candidate: Candidate, into record: inout CleanupRecord) {
        let cloud = check.cloud
        guard let rule = check.catalog.rule(candidate.ruleID) else { record.state = .skipped; record.message = CheckRefusal.changed.reason; return }
        let units = candidate.isDirectory && (try? candidate.url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
            ? Catalog.cloudCopies(in: candidate.url, rule: rule, cloud: cloud, exclusions: check.exclusions, volumeID: candidate.volumeID).units
            : [candidate.url]
        var removed = 0, failed = 0, lastRefusal: CheckRefusal?
        Catalog.withoutDownloads {
            for unit in units {
                if let refusal = cloud.metadata(unit).evictionRefusal { lastRefusal = refusal; continue }
                do { try cloud.evict(unit); removed += 1 } catch { failed += 1 }
            }
        }
        let originals = units.count == 1 ? " The original stays in iCloud." : " The originals stay in iCloud."
        switch (removed, failed) {
        case (0, 0): record.state = .skipped; record.message = (lastRefusal ?? .notDownloaded).reason
        case (0, _): record.state = .failed; record.message = "Couldn’t remove the local copy. Nothing was changed."
        case (_, 0): record.state = .succeeded; record.message = units.count == 1 ? "Removed local copy." + originals : "Removed local copies of \(removed) files." + originals
        default: record.state = .failed; record.partlyRemoved = true; record.message = "Removed local copies of \(removed) files; couldn’t remove \(failed)." + originals
        }
    }
}
