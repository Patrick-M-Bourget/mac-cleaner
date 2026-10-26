import Foundation
import Darwin

private let chromeArchiveLimit = 20_000_000

final class ChromeJournalLease {
    let descriptor: Int32
    init(_ journal: URL) throws {
        let parent = journal.deletingLastPathComponent()
        _ = try directoryChain([parent])
        let path = parent.appendingPathComponent(".chrome-cleanup-lock")
        descriptor = open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ChromeCacheFailure("Cleanup records cannot be locked.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); throw ChromeCacheFailure("Another cache operation owns these cleanup records.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

extension ChromeCacheService {
    /// Completed history has a component budget; unresolved claims never expire.
    public func retainCompletedRecords(days: Int = 90, maximumBytes: Int = 20_000_000) throws -> Int {
        guard !executing else { throw ChromeCacheFailure("Cleanup is in progress.") }
        let lease = try ChromeJournalLease(journalURL)
        defer { withExtendedLifetime(lease) {} }
        let archive = try records()
        let retained = try retainedArchive(archive, days: days, maximumBytes: maximumBytes)
        if retained.count != archive.count { try persist(retained) }
        return archive.count - retained.count
    }

    /// Caller already owns the journal lease; never reacquire its flock in execution.
    private func retainedArchive(_ archive: [ChromeCacheRun], days: Int = 90, maximumBytes: Int = 20_000_000) throws -> [ChromeCacheRun] {
        let cutoff = environment.now().addingTimeInterval(-Double(min(90, max(0, days))) * 86400)
        let budget = min(chromeArchiveLimit, max(0, maximumBytes))
        let protected = archive.filter(\.unresolved)
        let newest = archive.filter { !$0.unresolved && $0.observedAt >= cutoff }.sorted {
            $0.observedAt == $1.observedAt ? $0.id.uuidString < $1.id.uuidString : $0.observedAt > $1.observedAt
        }
        var retained: [ChromeCacheRun] = []; var bytes = 2
        for run in newest {
            let cost = try JSONEncoder().encode(run).count + (retained.isEmpty ? 0 : 1)
            guard cost <= budget - min(bytes, budget) else { continue }
            retained.append(run); bytes += cost
        }
        return protected + retained
    }

    public func clearCompletedRecords(requireNoRecovery: Bool = false) throws -> Int {
        guard !executing else { throw ChromeCacheFailure("Cleanup is in progress.") }
        let lease = try ChromeJournalLease(journalURL)
        defer { withExtendedLifetime(lease) {} }
        let archive = try records()
        if requireNoRecovery, archive.contains(where: \.unresolved) { throw ChromeCacheFailure("Unresolved cleanup records must be preserved.") }
        let retained = archive.filter(\.unresolved)
        try persist(retained)
        return archive.count - retained.count
    }

    /// Missing records is an empty archive; unreadable/corrupt records throws and blocks work.
    public func records() throws -> [ChromeCacheRun] {
        var info = stat()
        if lstat(journalURL.path, &info) != 0 {
            if errno == ENOENT { return [] }
            throw ChromeCacheFailure("Chrome cleanup records are unreadable.")
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_size <= chromeArchiveLimit else { throw ChromeCacheFailure("Chrome cleanup records are unsafe or too large.") }
        let fd = open(journalURL.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ChromeCacheFailure("Chrome cleanup records cannot be read.") }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, ChromeObjectIdentity(opened) == ChromeObjectIdentity(info) else { throw ChromeCacheFailure("Cleanup records changed.") }
        let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: chromeArchiveLimit + 1) ?? Data()
        guard data.count <= chromeArchiveLimit else { throw ChromeCacheFailure("Cleanup record budget exceeded.") }
        return try JSONDecoder().decode([ChromeCacheRun].self, from: data)
    }
    func persist(_ records: [ChromeCacheRun]) throws {
        let parent = journalURL.deletingLastPathComponent()
        _ = try directoryChain([parent])
        let encoded = try JSONEncoder().encode(records)
        guard encoded.count <= chromeArchiveLimit else { throw ChromeCacheFailure("Chrome cleanup record budget reached.") }
        let temporary = parent.appendingPathComponent(".chrome-claim-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ChromeCacheFailure("Cannot save the cleanup claim. Nothing was started.") }
        defer { close(fd); unlink(temporary.path) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: encoded)
        guard fsync(fd) == 0, rename(temporary.path, journalURL.path) == 0 else { throw ChromeCacheFailure("Cleanup claim could not be committed.") }
        let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw ChromeCacheFailure("Cleanup claim durability is uncertain.") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw ChromeCacheFailure("Cleanup claim durability is uncertain.") }
    }
    public func execute(_ approval: ChromeCacheApproval, cancellation: CleanupCancellation) async -> ChromeCacheRun {
        let failed: (String) -> ChromeCacheRun = { reason in
            .init(id: UUID(), groups: approval.groups.map { .init(profileIdentifier: $0.profileIdentifier, status: .skipped, removedFiles: 0, removedBytes: 0, reason: reason) }, unresolved: false, approvedAt: approval.approvedAt, observedAt: self.environment.now())
        }
        guard !executing, approval.serviceID == serviceID, approval.generation == generation,
              approval.groupIDs.isSubset(of: Set(authorities.keys)) else { return failed("This approval is no longer current. Check again.") }
        executing = true; cancelled = false
        defer { executing = false; generation = UUID(); authorities = [:] }
        var archive: [ChromeCacheRun]
        let lease: ChromeJournalLease
        do { lease = try ChromeJournalLease(journalURL) } catch { return failed("Cleanup records cannot be claimed. Nothing was started.") }
        defer { withExtendedLifetime(lease) {} }
        do {
            archive = try records()
            guard !archive.contains(where: \.unresolved) else { return failed("An earlier cache cleanup has an unknown outcome. It will not be retried.") }
        } catch { return failed("Cleanup records are unavailable. Nothing was started.") }
        var run = ChromeCacheRun(id: UUID(), groups: approval.groups.map { .init(profileIdentifier: $0.profileIdentifier, status: .skipped, removedFiles: 0, removedBytes: 0, reason: "Not started.") }, unresolved: false, approvedAt: approval.approvedAt, observedAt: environment.now())
        // Claim each group before mutation. A crash leaves unknown, never replayable work.
        // Reserve bounded outcome/claim overhead before adding this run. Retention
        // can discard only completed history, never this run or unresolved facts.
        do {
            let reserve = try JSONEncoder().encode(run).count + 4096 + approval.groups.count * 1024
            archive = try retainedArchive(archive, maximumBytes: max(0, chromeArchiveLimit - reserve))
        } catch { return failed("Completed cleanup history could not be maintained. Nothing was started.") }
        archive.append(run)
        for (groupIndex, group) in approval.groups.enumerated() {
            var removed = 0; var bytes: Int64 = 0
            if cancelled || cancellation.isCancelled || Task.isCancelled {
                run.groups[groupIndex] = .init(profileIdentifier: group.profileIdentifier, status: .cancelled, removedFiles: 0, removedBytes: 0, reason: "Cancelled before starting this group.")
                continue
            }
            guard let authority = authorities[group.id] else { continue }
            run.unresolved = true
            run.groups[groupIndex] = .init(profileIdentifier: group.profileIdentifier, status: .unknown, removedFiles: 0, removedBytes: 0, reason: "Claimed; completion is not yet recorded.")
            archive[archive.count - 1] = run
            do { try persist(archive) } catch {
                run.groups[groupIndex] = .init(profileIdentifier: group.profileIdentifier, status: .unknown, removedFiles: 0, removedBytes: 0, reason: "The durable claim could not be saved. No cleanup started.")
                return run
            }
            var status: ChromeCacheGroupStatus = .succeeded; var reason: String?
            do {
                try environment.validateInstallation(at: authority.access.applicationURL)
                try validateMapping(authority.access)
                let state = try readChromeOwnership(authority.access.dataRootURL.appendingPathComponent("Local State"))
                guard !state.hasOverride, state.identifiers.contains(group.profileIdentifier) else { throw ChromeCacheFailure("Chrome profile ownership or cache configuration changed.") }
                try verifyChromeProfileMetadata(authority.access.dataRootURL.appendingPathComponent(group.profileIdentifier + "/Preferences"))
                guard try !environment.browserIsRunning(bundleURL: authority.access.applicationURL) else { throw ChromeCacheFailure("Chrome or a helper is running. Check again after quitting.") }
                let opened = try ChromeOpenGroup(chain: authority.chain)
                let leaves = try opened.entries()
                for leaf in leaves {
                    await Task.yield()
                    if cancelled || cancellation.isCancelled || Task.isCancelled { status = .cancelled; reason = "Unstarted entries were preserved."; break }
                    guard try !environment.browserIsRunning(bundleURL: authority.access.applicationURL) else { throw ChromeCacheFailure("Chrome or a helper became active. Unstarted entries were preserved.") }
                    bytes += try opened.remove(leaf); removed += 1
                }
            } catch { status = .failed; reason = (error as? ChromeCacheFailure)?.description ?? "Chrome metadata or access changed; unstarted work was preserved." }
            run.groups[groupIndex] = .init(profileIdentifier: group.profileIdentifier, status: status, removedFiles: removed, removedBytes: bytes, reason: reason)
            run.unresolved = false; archive[archive.count - 1] = run
            do { try persist(archive) } catch {
                run.unresolved = true
                run.groups[groupIndex] = .init(profileIdentifier: group.profileIdentifier, status: .unknown, removedFiles: removed, removedBytes: bytes, reason: "Work stopped because its outcome could not be saved. No automatic retry.")
                return run
            }
            if status != .succeeded { break }
        }
        archive[archive.count - 1] = run
        do { try persist(archive) } catch { run.unresolved = true }
        return run
    }
}
