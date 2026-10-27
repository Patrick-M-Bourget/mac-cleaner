import Foundation
import Darwin
import os

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
        let removed = records.filter { $0.state == .succeeded && $0.cleanupAction != .trash }
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
        records.filter { $0.state == .succeeded && $0.cleanupAction == .trash }.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }
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
        scopeURL = parent; scopeResourceID = lstat(parent.path, &info) == 0 ? info.resourceID : ""
        volumeID = candidate.volumeID; downloadsURL = nil; downloadsResourceID = nil
        modifiedSeconds = candidate.modifiedSeconds; modifiedNanoseconds = candidate.modifiedNanoseconds
        action = candidate.action.rawValue; policyVersion = 2; self.approvedAt = approvedAt
        ruleID = candidate.ruleID; self.previewOnly = previewOnly
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

    public func execute(_ approval: CatalogApproval, progress: @Sendable (CleanupExecutionProgress) async -> Void = { _ in }) async -> CatalogExecutionResult {
        var seen = Set<String>()
        let estimate = approval.candidates.filter { seen.insert(check.catalog.spaceKey(of: $0)).inserted }.reduce(Int64(0)) { $0 + $1.estimatedBytes }
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
        // One reading of what processes have open serves many items, but never one older than `inUseReadingMaxAge`.
        var reading: (check: CandidateCheck, takenAt: Date)?
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
            if self.check.needsInUseCheck(candidate), reading.map({ clock().timeIntervalSince($0.takenAt) > Self.inUseReadingMaxAge }) ?? true {
                reading = (self.check.snapshotted(), clock())
            }
            await perform(candidate, check: reading?.check ?? self.check, previewOnly: approval.previewOnly, into: &record)
            do { try journal.outcome(record) }
            catch { record.state = .unknown; record.message = "Outcome could not be recorded. Review recovery; do not repeat automatically."; failure = record.message }
            if record.state == .unknown { failure = record.message }
            records.append(record)
            await progress(.init(resolved: records.count, total: total, last: record))
        }
        return result(records, failure: failure)
    }

    private func perform(_ candidate: Candidate, check: CandidateCheck, previewOnly: Bool, into record: inout CleanupRecord) async {
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
        if previewOnly {
            let size = ByteCountFormatter.string(fromByteCount: candidate.estimatedBytes, countStyle: .decimal)
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
            record.itemCapacity = CleanupCapacityObservation(beforeAvailable: before.available, afterAvailable: after.available, beforeTotal: before.total, afterTotal: after.total, beforeVolumeID: before.volumeID, afterVolumeID: after.volumeID, beforeMetric: before.metric.rawValue, afterMetric: after.metric.rawValue, beforeDate: before.date, afterDate: after.date)
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
        let outcome = await Task.detached(priority: .userInitiated) {
            // The tool's own folder goes first on PATH, so `#!/usr/bin/env node` tools such as pnpm find their runtime.
            var environment = BoundedTool.defaultEnvironment
            environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
            return Result { try BoundedTool.capture(executable: executable, arguments: arguments, timeout: command.timeout, environment: environment, cancellation: cancellation) }
        }.value
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
            var info = stat()
            if lstat(candidate.url.path, &info) != 0, errno == ENOENT { record.state = .succeeded; record.message = "Ran \(name); it removed the folder itself"; return }
            delete(candidate, into: &record)
            if record.state == .succeeded { record.message = "Ran \(name) and permanently removed the folder" }
            else { record.message = "Ran \(name). " + record.message }
        case .failure(let error as ToolTimeout):
            Self.recordStopped("at the \(Int(command.timeout.rounded(.up)))-second time limit", output: error.output, command, name: name, candidate, into: &record)
        case .failure(let error as ToolCancelled) where !error.started:
            record.state = .cancelled; record.message = "Stopped before \(name) started. Nothing was changed."
        case .failure(let error as ToolCancelled):
            Self.recordStopped("when you cancelled", output: error.output, command, name: name, candidate, into: &record)
        case .failure(ToolPreviewError.unavailable):
            record.state = .skipped; record.message = "\(name) is no longer installed."
        case .failure:
            record.state = .failed; record.message = "Couldn’t run \(name). Nothing was changed."
        }
    }

    /// A tool stopped before it finished (time limit or cancel) ran until then, so it may have removed some files;
    /// the folder is never deleted after it. `reason` says what stopped it. A daemon-backed tool's work goes on without it (SPEC section 4),
    /// so only the wait stopped and the work may still be finishing.
    private static func recordStopped(_ reason: String, output: String, _ command: ToolCommand, name: String, _ candidate: Candidate, into record: inout CleanupRecord) {
        record.toolOutput = trimmed(output)
        record.state = .failed; record.partlyRemoved = true
        let effect = command.daemonBacked ? "Stopped waiting \(reason). \(name) hands its work to a background service, which may still be finishing"
                                          : "Stopped \(reason). \(name) may have cleaned part of it"
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
        let asideName = Catalog.leftoverName(for: candidate.ruleID)
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
            record.state = .succeeded; record.message = "Permanently removed"
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
                record.state = .unknown; record.message = "The item in the Trash isn’t the one approved. Review it before cleaning again."
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
