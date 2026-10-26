import Foundation
import Darwin
import Testing
import StillCore

private struct ChromeEnvironmentFixture: ChromeCacheEnvironment {
    let running: Bool
    func validateInstallation(at url: URL) throws {}
    func browserIsRunning(bundleURL: URL) throws -> Bool { running }
    func now() -> Date { Date(timeIntervalSince1970: 42) }
}
private func chromeFixture() throws -> (URL, ChromeCacheAccess) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillChrome-" + UUID().uuidString).resolvingSymlinksInPath()
    let data = root.appendingPathComponent("data")
    let group = data.appendingPathComponent("Default/Cache/Cache_Data")
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    try Data(#"{"profile":{"info_cache":{"Default":{"name":"Never collect this account"}}}}"#.utf8).write(to: data.appendingPathComponent("Local State"))
    try Data("{}".utf8).write(to: data.appendingPathComponent("Default/Preferences"))
    try Data("cache".utf8).write(to: group.appendingPathComponent("0123456789abcdef_0"))
    try Data("protected".utf8).write(to: data.appendingPathComponent("Default/Cookies"))
    return (root, ChromeCacheAccess(applicationURL: root.appendingPathComponent("Chrome.app"), dataRootURL: data, cacheRootURL: data, customLocation: true))
}
@Test func chromeInspectionReportsOnlyVerifiedProfileAndAssetCache() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
    let result = await service.inspect(access)
    #expect(result.unavailableReason == nil)
    #expect(result.groups.count == 1)
    #expect(result.groups.first?.profileIdentifier == "Default")
    #expect(result.groups.first?.estimatedBytes == 5)
}

@Test func chromeApprovedGroupIncludesLaterCacheButPreservesPersonalDataAndRecordsOutcome() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("journal.json")
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    let first = await service.inspect(access)
    let approval = try await service.approve(groupIDs: Set(first.groups.map(\.id)))
    try Data("later".utf8).write(to: access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data/fedcba9876543210_0"))
    let result = await service.execute(approval, cancellation: CleanupCancellation())
    #expect(result.groups.first?.status == .succeeded)
    #expect(result.groups.first?.removedFiles == 2)
    #expect(result.groups.first?.removedBytes == 10)
    #expect(try String(contentsOf: access.dataRootURL.appendingPathComponent("Default/Cookies"), encoding: .utf8) == "protected")
    let reloaded = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    #expect(try await reloaded.records().first?.id == result.id)
}

@Test func chromeRunningAndUnknownProfileLayoutsNeverCreateCleanupAuthority() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let running = ChromeCacheService(environment: ChromeEnvironmentFixture(running: true), journalURL: root.appendingPathComponent("journal.json"))
    let observed = await running.inspect(access)
    #expect(observed.availability == .running)
    #expect(observed.groups.isEmpty)
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
    try Data(#"{"profile":{"info_cache":{"../Downloads":{}}}}"#.utf8).write(to: access.dataRootURL.appendingPathComponent("Local State"))
    #expect(await service.inspect(access).availability == .unsupported)
    #expect(try Data(contentsOf: access.dataRootURL.appendingPathComponent("Default/Cookies")) == Data("protected".utf8))
}

@Test func chromeGroupIdentityIsStableAcrossCheckButOldApprovalExpires() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
    let first = await service.inspect(access)
    let approval = try await service.approve(groupIDs: Set(first.groups.map(\.id)))
    let second = await service.inspect(access)
    #expect(first.groups.map(\.id) == second.groups.map(\.id))
    let result = await service.execute(approval, cancellation: CleanupCancellation())
    #expect(result.groups.first?.status == .skipped)
    #expect(result.groups.first?.removedFiles == 0)
}

@Test func chromeReplacedGroupAndSymlinkLeavesStopWithoutDeletingPersonalFiles() async throws {
    for replacement in [false, true] {
        let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
        let observed = await service.inspect(access)
        let approval = try await service.approve(groupIDs: Set(observed.groups.map(\.id)))
        let group = access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data")
        if replacement {
            try FileManager.default.moveItem(at: group, to: group.appendingPathExtension("prior"))
            try FileManager.default.createDirectory(at: group, withIntermediateDirectories: false)
            try Data("personal".utf8).write(to: group.appendingPathComponent("0123456789abcdef_0"))
        } else {
            try FileManager.default.createSymbolicLink(at: group.appendingPathComponent("fedcba9876543210_0"), withDestinationURL: access.dataRootURL.appendingPathComponent("Default/Cookies"))
        }
        let result = await service.execute(approval, cancellation: CleanupCancellation())
        #expect(result.groups.first?.status == .failed)
        #expect(result.groups.first?.removedFiles == 0)
        #expect(try String(contentsOf: access.dataRootURL.appendingPathComponent("Default/Cookies"), encoding: .utf8) == "protected")
    }
}

@Test func chromeCancellationAndUnreadableJournalNeverStartRemoval() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("journal.json")
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    let observed = await service.inspect(access)
    let approval = try await service.approve(groupIDs: Set(observed.groups.map(\.id)))
    let cancellation = CleanupCancellation(); cancellation.cancel()
    let cancelled = await service.execute(approval, cancellation: cancellation)
    #expect(cancelled.groups.first?.status == .cancelled)
    #expect(cancelled.groups.first?.removedFiles == 0)
    let next = await service.inspect(access)
    let nextApproval = try await service.approve(groupIDs: Set(next.groups.map(\.id)))
    try Data("broken".utf8).write(to: journal)
    let stopped = await service.execute(nextApproval, cancellation: CleanupCancellation())
    #expect(stopped.groups.first?.status == .skipped)
    #expect(try Data(contentsOf: access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0")) == Data("cache".utf8))
}

@Test func chromeChangedProfileOwnershipStopsApprovedCacheBeforeRemoval() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
    let observed = await service.inspect(access)
    let approval = try await service.approve(groupIDs: Set(observed.groups.map(\.id)))
    try Data(#"{"profile":{"info_cache":{}}}"#.utf8).write(to: access.dataRootURL.appendingPathComponent("Local State"))
    let result = await service.execute(approval, cancellation: CleanupCancellation())
    #expect(result.groups.first?.status == .failed)
    #expect(result.groups.first?.removedFiles == 0)
    #expect(try Data(contentsOf: access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0")) == Data("cache".utf8))
}

private final class ChromeActivitySequence: ChromeCacheEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var observations = [false, false, false, true]
    func validateInstallation(at url: URL) throws {}
    func browserIsRunning(bundleURL: URL) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return observations.isEmpty ? true : observations.removeFirst()
    }
    func now() -> Date { Date(timeIntervalSince1970: 42) }
}
@Test func chromeHelperActivityStopsRemainingEntriesAndPersistsPartialOutcome() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let second = access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data/fedcba9876543210_0")
    try Data("later".utf8).write(to: second)
    let service = ChromeCacheService(environment: ChromeActivitySequence(), journalURL: root.appendingPathComponent("journal.json"))
    let observed = await service.inspect(access)
    let approval = try await service.approve(groupIDs: Set(observed.groups.map(\.id)))
    let result = await service.execute(approval, cancellation: CleanupCancellation())
    #expect(result.groups.first?.status == .failed)
    #expect(result.groups.first?.removedFiles == 1)
    #expect(try Data(contentsOf: second) == Data("later".utf8))
    #expect(try await service.records().first?.groups.first?.removedFiles == 1)
}
@Test func chromeUnknownClaimAndFailedClaimWritePreventReplay() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("journal.json")
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    let first = await service.inspect(access)
    _ = await service.execute(try await service.approve(groupIDs: Set(first.groups.map(\.id))), cancellation: CleanupCancellation())
    var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [[String: Any]])
    rows[0]["unresolved"] = true
    try JSONSerialization.data(withJSONObject: rows).write(to: journal)
    let leaf = access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0")
    try Data("preserve".utf8).write(to: leaf)
    let observed = await service.inspect(access)
    let result = await service.execute(try await service.approve(groupIDs: Set(observed.groups.map(\.id))), cancellation: CleanupCancellation())
    #expect(result.groups.first?.status == .skipped)
    #expect(try await service.records().first?.unresolved == true)
    let unwritable = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("missing/journal.json"))
    let checked = await unwritable.inspect(access)
    let stopped = await unwritable.execute(try await unwritable.approve(groupIDs: Set(checked.groups.map(\.id))), cancellation: CleanupCancellation())
    #expect(stopped.groups.first?.status == .skipped)
    #expect(stopped.groups.first?.removedFiles == 0)
    #expect(try Data(contentsOf: leaf) == Data("preserve".utf8))
}

@Test func chromeClearCompletedPreservesUnknownClaimsAndResetRefusesThem() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("journal.json")
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    let scan = await service.inspect(access)
    _ = await service.execute(try await service.approve(groupIDs: Set(scan.groups.map(\.id))), cancellation: CleanupCancellation())
    var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [[String: Any]])
    var unresolved = rows[0]; unresolved["unresolved"] = true; unresolved["id"] = UUID().uuidString
    rows.append(unresolved); try JSONSerialization.data(withJSONObject: rows).write(to: journal)
    do { _ = try await service.clearCompletedRecords(requireNoRecovery: true); Issue.record("Reset must refuse an unresolved claim") } catch {}
    #expect(try await service.records().count == 2)
    #expect(try await service.clearCompletedRecords() == 1)
    #expect(try await service.records().count == 1)
    #expect(try await service.records().first?.unresolved == true)
}

@Test func chromeActualMetadataPermissionDenialIsNotUnsupportedOrMeasuredZero() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let state = access.dataRootURL.appendingPathComponent("Local State")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: state.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: state.path) }
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
    let scan = await service.inspect(access)
    #expect(scan.availability == .denied)
    #expect(scan.groups.isEmpty)
}

@Test func chromeKnownProviderLocationsStayUnavailableAndQualifiedSecondProfileIsRecognized() async throws {
    let (root, original) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let provider = root.appendingPathComponent("Library/CloudStorage/OwnedChrome")
    try FileManager.default.createDirectory(at: provider.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original.dataRootURL, to: provider)
    let access = ChromeCacheAccess(applicationURL: original.applicationURL, dataRootURL: provider, cacheRootURL: provider, customLocation: true)
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: root.appendingPathComponent("journal.json"))
    let blocked = await service.inspect(access)
    #expect(blocked.availability == .unsupported)
    #expect(blocked.groups.isEmpty)
    try FileManager.default.moveItem(at: provider, to: original.dataRootURL)
    try FileManager.default.moveItem(at: original.dataRootURL.appendingPathComponent("Default"), to: original.dataRootURL.appendingPathComponent("Profile 1"))
    try Data(#"{"profile":{"info_cache":{"Profile 1":{}}}}"#.utf8).write(to: original.dataRootURL.appendingPathComponent("Local State"))
    let local = await service.inspect(original)
    #expect(local.groups.first?.profileIdentifier == "Profile 1")
    #expect(local.groups.first?.estimatedBytes == 5)
}

@Test func chromeRetentionExpiresCompletedHistoryButKeepsUnknownClaimIDsAndConsumedApproval() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("journal.json")
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    let inspected = await service.inspect(access)
    let approval = try await service.approve(groupIDs: Set(inspected.groups.map(\.id)))
    let completed = await service.execute(approval, cancellation: CleanupCancellation())
    var records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [[String: Any]])
    var expired = records[0]; let expiredID = UUID(); expired["id"] = expiredID.uuidString
    expired["observedAt"] = Date(timeIntervalSince1970: 42).addingTimeInterval(-91 * 86400).timeIntervalSinceReferenceDate
    var unresolved = expired; let claimID = UUID(); unresolved["id"] = claimID.uuidString; unresolved["unresolved"] = true
    records += [expired, unresolved]; try JSONSerialization.data(withJSONObject: records).write(to: journal)
    #expect(try await service.retainCompletedRecords() == 1)
    let retained = try await service.records()
    #expect(Set(retained.map(\.id)) == [completed.id, claimID])
    #expect(retained.first(where: { $0.id == claimID })?.unresolved == true)
    let leaf = access.cacheRootURL.appendingPathComponent("Default/Cache/Cache_Data/0123456789abcdef_0")
    try Data("later protected cache".utf8).write(to: leaf)
    let replay = await service.execute(approval, cancellation: CleanupCancellation())
    #expect(replay.groups.first?.status == .skipped)
    #expect(try Data(contentsOf: leaf) == Data("later protected cache".utf8))
}

@Test func chromeRetentionBudgetKeepsNewestCompletedRunAndExemptsUnknownRecords() async throws {
    let (root, access) = try chromeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("journal.json")
    let service = ChromeCacheService(environment: ChromeEnvironmentFixture(running: false), journalURL: journal)
    let scan = await service.inspect(access)
    let newest = await service.execute(try await service.approve(groupIDs: Set(scan.groups.map(\.id))), cancellation: CleanupCancellation())
    var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [[String: Any]])
    var older = rows[0]; older["id"] = UUID().uuidString; older["observedAt"] = Date(timeIntervalSince1970: 41).timeIntervalSinceReferenceDate
    var unknown = older; let claimID = UUID(); unknown["id"] = claimID.uuidString; unknown["unresolved"] = true
    rows = [older, unknown, rows[0]]; try JSONSerialization.data(withJSONObject: rows).write(to: journal)
    let newestBudget = try JSONEncoder().encode(newest).count + 2
    #expect(try await service.retainCompletedRecords(maximumBytes: newestBudget) == 1)
    let retained = try await service.records()
    #expect(Set(retained.map(\.id)) == [newest.id, claimID])
    #expect(retained.first(where: { $0.id == claimID })?.unresolved == true)
}


@Test(.enabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" && ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted"))
func chromeNativeUnreapedExitedChildIsNotBrowserActivity() throws {
    // Hosted-only system boundary: no personal browser or process observation.
    // Swift forbids fork(); supported posix_spawn owns an immediate-exit child
    // without Foundation.Process's automatic reaper. Keep it unreaped below.
    var child: pid_t = 0
    let binary = try #require(strdup("/usr/bin/true"))
    defer { free(binary) }
    var arguments: [UnsafeMutablePointer<CChar>?] = [binary, nil]
    var environment: [UnsafeMutablePointer<CChar>?] = [nil]
    let spawned = arguments.withUnsafeMutableBufferPointer { args in
        environment.withUnsafeMutableBufferPointer { env in
            posix_spawn(&child, "/usr/bin/true", nil, nil, args.baseAddress!, env.baseAddress!)
        }
    }
    try #require(spawned == 0 && child > 0)
    defer {
        var status: Int32 = 0
        var reaped = false
        for _ in 0..<100 {
            if waitpid(child, &status, WNOHANG) == child { reaped = true; break }
            usleep(10_000)
        }
        if !reaped { kill(child, SIGTERM); _ = waitpid(child, &status, 0) }
    }
    var exited = siginfo_t()
    var exitObserved = false
    for _ in 0..<100 {
        let result = waitid(P_PID, id_t(child), &exited, WEXITED | WNOWAIT | WNOHANG)
        if result == 0, exited.si_pid == child { exitObserved = true; break }
        usleep(10_000)
    }
    try #require(exitObserved, "Owned child must be exited and explicitly unreaped (WNOWAIT)")
    var details = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let infoResult = proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &details, size)
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let pathResult = proc_pidpath(child, &path, UInt32(path.count))
    print("DISPOSABLE_CHILD_OBSERVATION pid=\(child) waitPID=\(exited.si_pid) exitCode=\(exited.si_code) procInfoResult=\(infoResult) expectedInfoSize=\(size) parent=\(details.pbi_ppid) uid=\(details.pbi_uid) state=\(details.pbi_status) pathLookupResult=\(pathResult)")
    if infoResult == size { #expect(details.pbi_uid == getuid()) }
    #expect(try NativeChromeCacheEnvironment().browserIsRunning(bundleURL: URL(fileURLWithPath: "/__still_disposable_missing_browser__.app")) == false)
}
