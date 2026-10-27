import Foundation
import Testing
@testable import CacheDropCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropDocker-\(UUID())")
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".docker"), withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}

/// What `docker system df --format json` prints: one JSON object per line.
private let report = """
{"Active":"1","Reclaimable":"2.5GB (62%)","Size":"4GB","TotalCount":"5","Type":"Images"}
{"Active":"1","Reclaimable":"120MB (40%)","Size":"300MB","TotalCount":"3","Type":"Containers"}
{"Active":"1","Reclaimable":"6GB (50%)","Size":"12GB","TotalCount":"2","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"1.234GB","Size":"1.234GB","TotalCount":"40","Type":"Build Cache"}
"""

/// A stand-in `docker` in the fixture that answers `system df` with `df` and logs every call;
/// the real docker is never run by tests.
private func fakeDocker(_ home: URL, df: String = "cat \"$(dirname \"$0\")/df.json\"", prune: String = "echo 'Total reclaimed space: 1GB'") throws -> URL {
    let tool = home.appendingPathComponent("tools/docker")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try report.write(to: home.appendingPathComponent("tools/df.json"), atomically: true, encoding: .utf8)
    let script = """
    #!/bin/sh
    echo "$@" >> "$(dirname "$0")/calls"
    if test "$*" = "system df --format json"; then
    \(df)
    else
    \(prune)
    fi
    """
    try script.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}
private func calls(_ home: URL) -> [String] {
    ((try? String(contentsOf: home.appendingPathComponent("tools/calls"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}

@Test func eachDockerPruneKindIsItsOwnCandidateSizedFromSystemDf() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discovery(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    let byRule = Dictionary(uniqueKeysWithValues: found.candidates.map { ($0.ruleID, $0) })
    #expect(Set(byRule.keys) == ["docker-images", "docker-build-cache", "docker-containers"])
    #expect(byRule["docker-images"]?.estimatedBytes == 2_500_000_000)
    #expect(byRule["docker-build-cache"]?.estimatedBytes == 1_234_000_000)
    #expect(byRule["docker-containers"]?.estimatedBytes == 120_000_000)
    #expect(found.candidates.allSatisfy { $0.action == .tool && $0.sizeIsEstimate && $0.sizeComplete && $0.toolURL == docker })
    #expect(found.notes.isEmpty)
    // One `system df` for all three kinds; nothing else is run while scanning.
    #expect(calls(home) == ["system df --format json"])
    #expect(catalog.rule("docker-images")?.tool?.commandLine == "docker image prune -a -f")
    #expect(catalog.rule("docker-build-cache")?.tool?.commandLine == "docker builder prune -a -f")
    #expect(catalog.rule("docker-containers")?.tool?.commandLine == "docker container prune -f")
    #expect(catalog.rule("docker-images")?.tool?.executables == ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", NSHomeDirectory() + "/.docker/bin/docker"])
}

@Test func dockerIsLeftOutWithANoticeWhenItsDaemonDoesntAnswer() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, df: "echo 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?' >&2; exit 1")
    let found = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    #expect(!found.candidates.contains { $0.ruleID.hasPrefix("docker-") })
    #expect(found.notes.map(\.text) == ["Docker isn’t running, so its space isn’t shown. Open Docker, then scan again."])
    #expect(calls(home) == ["system df --format json"])
}

@Test func dockerOffersNothingAndRunsNothingWhenTheCLIIsntInstalled() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try fakeDocker(home)
    let found = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: { _ in nil })
    #expect(found.candidates.isEmpty && found.notes.isEmpty)
    #expect(calls(home).isEmpty)
}

@Test func unreadableDockerOutputIsANoticeNeverZero() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, df: "echo json; echo json")
    let found = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    #expect(found.candidates.isEmpty)
    #expect(found.notes.map(\.text) == ["Couldn’t read Docker’s disk usage, so its space isn’t shown."])
}

@Test func aKindWithNothingToReclaimIsntOfferedAndAnUnknownSizeStaysUnknown() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, df: """
    echo '{"Active":"2","Reclaimable":"0B (0%)","Size":"4GB","TotalCount":"2","Type":"Images"}'
    echo '{"Active":"0","Reclaimable":"N/A","Size":"N/A","TotalCount":"3","Type":"Build Cache"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Containers"}'
    """)
    let found = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    #expect(found.map(\.ruleID) == ["docker-build-cache"])
    #expect(found.map(SizeEstimate.init) == [.unknown])
}

@Test func volumesAreNeverACandidate() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    #expect(found.count == 3)
    #expect(!catalog.rules.contains { $0.tool?.arguments.contains("volume") == true || $0.tool?.arguments.contains("--volumes") == true })
    #expect(!catalog.rules.contains { $0.tool?.arguments.first == "system" })
}

@Test func dockerSizesAreReadAsDockerPrintsThem() {
    #expect(DockerDiskUsage.bytes("2.5GB (62%)") == 2_500_000_000)
    #expect(DockerDiskUsage.bytes("1.234kB") == 1_234)
    #expect(DockerDiskUsage.bytes("0B") == 0)
    #expect(DockerDiskUsage.bytes("1.5GiB") == 1_610_612_736)
    #expect(DockerDiskUsage.bytes("N/A") == nil)
    #expect(DockerDiskUsage.bytes("-1GB") == nil)
    #expect(DockerDiskUsage.bytes("12XB") == nil)
}

/// Docker's daemon is running whenever Docker can be pruned; only "unknown" would ever refuse, and Docker has no owner to close.
private struct EverythingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { true } }
/// A fake volume whose available space grows by what each item frees.
private final class FakeVolume: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Int64 = 1_000_000
    var freedPerRead: [Int64] = []
    func read(_ url: URL) -> CapacitySample? {
        lock.lock(); defer { lock.unlock() }
        if !freedPerRead.isEmpty { available += freedPerRead.removeFirst() }
        return CapacitySample(available: available, total: 10_000_000, volumeID: "fake-volume", metric: .important, date: Date())
    }
}
private func dockerRun(_ home: URL, docker: URL, choose ruleIDs: Set<String>, volume: FakeVolume = FakeVolume(), previewOnly: Bool = false,
                       timeout: TimeInterval? = nil, cancellation: CleanupCancellation = CleanupCancellation()) async throws -> CatalogExecutionResult {
    try await dockerRunning(home, docker: docker, choose: ruleIDs, volume: volume, previewOnly: previewOnly, timeout: timeout, cancellation: cancellation).result
}
/// A finished run with what measuring it again needs.
private struct DockerRun {
    let result: CatalogExecutionResult
    let run: CleanupExecutor
    let approval: CatalogApproval
    let catalog: Catalog
    let journal: SQLiteCleanupJournal
}
private func dockerRunning(_ home: URL, docker: URL, choose ruleIDs: Set<String>, volume: FakeVolume = FakeVolume(), previewOnly: Bool = false,
                           timeout: TimeInterval? = nil, cancellation: CleanupCancellation = CleanupCancellation()) async throws -> DockerRun {
    // A copy of each chosen rule with a shorter time limit, otherwise the same rule.
    let catalog = Catalog(rules: fixtureRules.map { rule in
        guard let timeout, ruleIDs.contains(rule.id) else { return rule }
        var copy = rule
        copy.tool?.timeout = timeout
        return copy
    })
    let chosen = catalog.discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil }).filter { ruleIDs.contains($0.ruleID) }
    try #require(chosen.count == ruleIDs.count)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: EverythingRunning()), measure: volume.read, trash: TrashNeverUsed(), cancellation: cancellation)
    let approval = CatalogApproval(candidates: chosen, previewOnly: previewOnly)
    return DockerRun(result: await run.execute(approval), run: run, approval: approval, catalog: catalog, journal: journal)
}

@Test func onlyTheChosenPruneRunsAndResultsShowItsOutputAndMeasuredSpace() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, prune: "echo 'Deleted Images:'; echo 'deleted: sha256:abc'; echo 'Total reclaimed space: 2.1GB'")
    let volume = FakeVolume()
    volume.freedPerRead = [0, 2_100_000]
    let result = try await dockerRun(home, docker: docker, choose: ["docker-images"], volume: volume)
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded)
    #expect(record.message == "Ran docker image prune -a -f")
    #expect(record.toolOutput?.contains("Total reclaimed space: 2.1GB") == true)
    #expect(result.measuredFreedBytes == 2_100_000)
    #expect(result.estimatedBytes == 2_500_000_000)
    #expect(calls(home) == ["system df --format json", "image prune -a -f"])
    // The folder that anchors the rule is never touched.
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".docker").path))
}

@Test func eachChosenKindRunsItsOwnCommandAndTheEstimateCountsAllOfThem() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let result = try await dockerRun(home, docker: docker, choose: ["docker-images", "docker-build-cache", "docker-containers"])
    #expect(result.records.allSatisfy { $0.state == .succeeded })
    #expect(Set(calls(home).dropFirst()) == ["image prune -a -f", "builder prune -a -f", "container prune -f"])
    #expect(result.estimatedBytes == 2_500_000_000 + 1_234_000_000 + 120_000_000)
}

@Test func previewOnlyLogsTheDockerCommandWithoutRunningIt() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let result = try await dockerRun(home, docker: docker, choose: ["docker-build-cache"], previewOnly: true)
    let record = try #require(result.records.first)
    #expect(record.state == .skipped)
    #expect(record.message.hasPrefix("Dry run: would run docker builder prune -a -f (1.23 GB)"))
    #expect(result.measuredFreedBytes == nil)
    #expect(calls(home) == ["system df --format json"])
}

@Test func aPruneThatFailsBecauseDockerStoppedShowsItsOutput() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, prune: "echo 'Cannot connect to the Docker daemon. Is the docker daemon running?' >&2; exit 1")
    let result = try await dockerRun(home, docker: docker, choose: ["docker-containers"])
    let record = try #require(result.records.first)
    #expect(record.state == .failed)
    #expect(record.toolOutput?.contains("Cannot connect to the Docker daemon") == true)
}

@Test func overviewShowsDockerAsAnEstimateInRecommended() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let catalog = Catalog(rules: fixtureRules)
    let overview = CatalogOverview(catalog: catalog, candidates: catalog.discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil }))
    #expect(overview.recommended == .about(2_500_000_000 + 1_234_000_000 + 120_000_000))
    #expect(overview.rows.map(\.category) == [.developer])
}

@Test func historyCountsEachDockerPruneInThePlannedTotal() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let result = try await dockerRun(home, docker: docker, choose: ["docker-images", "docker-containers"])
    let run = try #require(CleanupHistorySnapshot(records: result.records).completedRuns.first)
    #expect(run.plannedLogicalBytes == 2_500_000_000 + 120_000_000)
}

@Test func dockerGoingDownThenUpIsCoverageNeverGrowth() async throws {
    let home = try fixtureHome(), store = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropDockerGrowth-\(UUID())")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: store) }
    let down = home.appendingPathComponent("tools/down")
    let docker = try fakeDocker(home, df: "if test -f \"$(dirname \"$0\")/down\"; then echo 'Cannot connect to the Docker daemon' >&2; exit 1; fi; cat \"$(dirname \"$0\")/df.json\"")
    let catalog = Catalog(rules: fixtureRules), recorder = GrowthScanRecorder(store: GrowthHistoryStore(directory: store, minimumBaselineAge: 0))
    func scan() async throws -> GrowthComparison {
        let token = try await recorder.beginCatalog(home: home, exclusionFingerprint: ExclusionPolicy().fingerprint)
        let discovery = catalog.discovery(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
        return try await recorder.completeCatalog(discovery, catalog: catalog, fullDiskAccess: .granted, token: token)
    }
    _ = try await scan()
    try Data().write(to: down)
    let stopped = try await scan()
    #expect(stopped.current?.groups.filter { $0.ruleID?.hasPrefix("docker-") == true }.allSatisfy { $0.measured == false } == true)
    #expect(stopped.logicalDelta == 0)
    #expect(Set(stopped.coverageChanges.map(\.kind)) == [.newlyUnreadable])
    try FileManager.default.removeItem(at: down)
    let running = try await scan()
    #expect(running.logicalDelta == 0)
    #expect(running.groups.first { $0.id == "category:developer" }?.logicalDelta ?? 0 == 0)
    #expect(running.coverageChanges.count == 3 && Set(running.coverageChanges.map(\.kind)) == [.newlyReadable])
}

@Test func dockerIsntRunningIsShownEvenWithoutItsFolder() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.removeItem(at: home.appendingPathComponent(".docker"))
    let docker = try fakeDocker(home, df: "echo 'Cannot connect to the Docker daemon' >&2; exit 1")
    let found = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    #expect(!found.candidates.contains { $0.ruleID.hasPrefix("docker-") })
    #expect(found.notes.map(\.text) == ["Docker isn’t running, so its space isn’t shown. Open Docker, then scan again."])
    #expect(found.notMeasured["docker-images"] == [".docker"])
}

@Test func everyToolRuleShowsTheExactCommandItRuns() {
    for rule in fixtureRules where rule.action == .tool {
        // A command run per item names the item last (`ollama rm <model>`); its text names the command without it.
        let command = rule.tool.map { $0.itemPlaceholder == nil ? $0.commandLine : $0.commandLine(for: "").trimmingCharacters(in: .whitespaces) } ?? ""
        #expect(rule.consequence.contains("`" + command + "`"), "\(rule.id): \(command)")
    }
    #expect(fixtureRules.first { $0.id == "docker-build-cache" }?.consequence.hasPrefix("Runs `docker builder prune -a -f`") == true)
}

/// Docker's daemon does the pruning, outside the CLI's process group: stopping the CLI doesn't stop the work (#185).
@Test func aCancelledPruneSaysDockerMayStillBeFinishing() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep(), running = home.appendingPathComponent("running"), pids = home.appendingPathComponent("pids")
    let docker = try fakeDocker(home, prune: "echo pruning; \(recordPid("$$", in: pids)); touch '\(running.path)'; exec sleep \(length)")
    let cancellation = CleanupCancellation(), cancelledAt = CancelTime(), stopped = RecordedPidsGone(pids, count: 1)
    let watcher = CancelWhenFileAppears(running, cancel: cancellation, at: cancelledAt)
    defer { watcher.stop() }
    // A short time limit, so a cancel that never fires fails within seconds rather than when the stand-in's sleep ends.
    let result = try await dockerRun(home, docker: docker, choose: ["docker-images"], timeout: 5, cancellation: cancellation)
    // Timed from the cancel until the stand-in was gone, on a thread of its own: a busy run can take seconds more
    // to resume this test afterwards, which says nothing about how fast the CLI was stopped (#224).
    let sinceCancel = cancelledAt.elapsed(until: stopped.at)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    #expect(sinceCancel < BoundedTool.stopGrace + 1)
    let record = try #require(result.records.first)
    #expect(record.state == .failed && record.partlyRemoved == true)
    #expect(record.message.hasPrefix("Stopped waiting when you cancelled. docker image prune -a -f hands its work to a background service, which may still be finishing"))
    #expect(record.toolOutput == "pruning")
}

@Test func aTimedOutPruneSaysDockerMayStillBeFinishing() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep()
    let docker = try fakeDocker(home, prune: "sleep \(length)")
    let result = try await dockerRun(home, docker: docker, choose: ["docker-containers"], timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    let record = try #require(result.records.first)
    #expect(record.state == .failed && record.partlyRemoved == true)
    #expect(record.message.hasPrefix("Stopped waiting at the 1-second time limit. docker container prune -f hands its work to a background service, which may still be finishing"))
}

/// Which tools hand their work to a daemon is rule data: Docker's prunes, every simctl action and `ollama rm` (#189);
/// tools that do the work in their own process group are not.
@Test func onlyDaemonBackedToolsAreMarkedAsSuch() {
    let tools = Dictionary(uniqueKeysWithValues: fixtureRules.compactMap { rule in rule.tool.map { (rule.id, $0) } })
    let daemonBacked = Set(tools.filter { $0.value.daemonBacked }.keys)
    #expect(daemonBacked == ["docker-images", "docker-build-cache", "docker-containers", "simulator-runtimes", "simulator-devices", "xcode-simulators", "ollama-models"])
    #expect(tools["homebrew"]?.daemonBacked == false)
}

/// #190: a stopped daemon-backed prune keeps "may still be finishing", then its item is measured again a little later,
/// as the scan measures it, and the journal records what went. The wait is injected, so no test sleeps for it.
@Test func aStoppedPruneIsMeasuredAgainLaterAndTheJournalRecordsWhatWent() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep()
    let docker = try fakeDocker(home, prune: "sleep \(length)")
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-images", "docker-containers"], timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    #expect(done.result.records.allSatisfy { $0.mayStillBeFinishing == true && $0.laterMeasurement == nil })
    // Meanwhile the daemon finished the images and half the containers.
    try report.replacingOccurrences(of: "\"Reclaimable\":\"2.5GB (62%)\"", with: "\"Reclaimable\":\"0B (0%)\"")
        .replacingOccurrences(of: "\"Reclaimable\":\"120MB (40%)\"", with: "\"Reclaimable\":\"50MB (20%)\"")
        .write(to: home.appendingPathComponent("tools/df.json"), atomically: true, encoding: .utf8)
    let waited = Counter()
    let catalog = done.catalog, locate: @Sendable (ToolCommand) -> URL? = { $0.executables.contains("/usr/local/bin/docker") ? docker : nil }
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { delay in waited.increment(); return delay == .seconds(60) }) { candidates in
        catalog.measuredAgain(candidates, in: catalog.only(candidates).discovery(fixture: home, locateTool: locate))
    }
    // The containers were still shrinking, so a second wait started; it was cancelled, so the 60-second finding stays.
    #expect(waited.value == 2)
    let byRule = Dictionary(uniqueKeysWithValues: later.records.map { ($0.ruleID ?? "", $0) })
    #expect(byRule["docker-images"]?.laterMeasurement?.finding == .gone)
    #expect(byRule["docker-containers"]?.laterMeasurement?.finding == .remaining(bytes: 50_000_000))
    #expect(byRule["docker-images"]?.laterMeasurementText == "Measured again a minute later: it’s gone (2.5 GB at the scan).")
    #expect(byRule["docker-containers"]?.laterMeasurementText == "Measured again a minute later: 70 MB of 120 MB went; 50 MB is left.")
    // #209: the outcome follows the measurement. Gone reads "Removed", finished after the stop; some left stays partly removed.
    let images = try #require(byRule["docker-images"]), containers = try #require(byRule["docker-containers"])
    #expect(images.state == .succeeded && images.partlyRemoved == nil && images.outcomeTitle == "Removed")
    #expect(images.message == "Finished after you stopped it.")
    #expect(!images.needsAttention)
    #expect(containers.state == .failed && containers.partlyRemoved == true && containers.outcomeTitle == "Partly removed")
    #expect(containers.message.contains("may still be finishing"))
    // The measured freed space stays what was measured during the run.
    #expect(later.measuredFreedBytes == done.result.measuredFreedBytes)
    let journaled = Dictionary(uniqueKeysWithValues: try done.journal.records().map { ($0.ruleID ?? "", $0) })
    #expect(journaled["docker-images"]?.laterMeasurement?.finding == .gone)
    #expect(journaled["docker-containers"]?.laterMeasurement?.finding == .remaining(bytes: 50_000_000))
    #expect(journaled["docker-images"]?.state == .succeeded && journaled["docker-images"]?.outcomeTitle == "Removed")
    #expect(journaled["docker-containers"]?.state == .failed)
}

/// #209 point 3: measured once at 60 s; an item still shrinking compared with its size at the scan is measured once more
/// at about 5 minutes, then never again. Items that are gone or unchanged at 60 s aren't measured again.
@Test func anItemStillShrinkingAtAMinuteIsMeasuredOnceMoreAtFiveMinutes() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep()
    let docker = try fakeDocker(home, prune: "sleep \(length)")
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-images", "docker-containers", "docker-build-cache"], timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    let df = home.appendingPathComponent("tools/df.json")
    // At a minute: the build cache is gone, the images are half done, the containers haven't changed.
    let atAMinute = report.replacingOccurrences(of: "\"Reclaimable\":\"2.5GB (62%)\"", with: "\"Reclaimable\":\"1GB (25%)\"")
        .replacingOccurrences(of: "\"Reclaimable\":\"1.234GB\"", with: "\"Reclaimable\":\"0B\"")
    // At 5 minutes: the images are gone too.
    let atFive = atAMinute.replacingOccurrences(of: "\"Reclaimable\":\"1GB (25%)\"", with: "\"Reclaimable\":\"0B (0%)\"")
    let waits = Delays()
    let updates = Delays()
    let catalog = done.catalog, locate: @Sendable (ToolCommand) -> URL? = { $0.executables.contains("/usr/local/bin/docker") ? docker : nil }
    let measured = Delays()
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { delay in
        waits.append(delay)
        try? (waits.values.count == 1 ? atAMinute : atFive).write(to: df, atomically: true, encoding: .utf8)
        return true
    }, update: { partial in
        updates.append(.seconds(partial.records.first { $0.ruleID == "docker-images" }?.laterMeasurement?.afterSeconds ?? 0))
    }) { candidates in
        measured.append(.seconds(candidates.count))
        return catalog.measuredAgain(candidates, in: catalog.only(candidates).discovery(fixture: home, locateTool: locate))
    }
    // 60 s after the run, then 240 s more: about 5 minutes after it. Only the images are measured the second time.
    #expect(waits.values == [.seconds(60), .seconds(240)])
    #expect(measured.values == [.seconds(3), .seconds(1)])
    // Results showed the 60-second findings before the second wait.
    #expect(updates.values == [.seconds(60)])
    let byRule = Dictionary(uniqueKeysWithValues: later.records.map { ($0.ruleID ?? "", $0) })
    let images = try #require(byRule["docker-images"]), cache = try #require(byRule["docker-build-cache"]), containers = try #require(byRule["docker-containers"])
    #expect(images.laterMeasurement?.finding == .gone && images.laterMeasurement?.afterSeconds == 300 && images.outcomeTitle == "Removed")
    #expect(images.laterMeasurementText == "Measured again 5 minutes later: it’s gone (2.5 GB at the scan).")
    #expect(cache.laterMeasurement?.afterSeconds == 60 && cache.outcomeTitle == "Removed")
    #expect(containers.laterMeasurement?.finding == .remaining(bytes: 120_000_000) && containers.laterMeasurement?.afterSeconds == 60)
    #expect(containers.laterMeasurementText == "Measured again a minute later: nothing went yet.")
    let journaled = try #require(try done.journal.records().first { $0.ruleID == "docker-images" })
    #expect(journaled.laterMeasurement?.afterSeconds == 300 && journaled.state == .succeeded)
}

/// A daemon that doesn't answer later is never read as "gone".
@Test func aStoppedPruneWhoseDaemonDoesntAnswerLaterIsUnmeasured() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep()
    let docker = try fakeDocker(home, prune: "sleep \(length)")
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-images"], timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    let down = try fakeDocker(home, df: "echo 'Cannot connect to the Docker daemon' >&2; exit 1", prune: "exit 1")
    let catalog = done.catalog, locate: @Sendable (ToolCommand) -> URL? = { $0.executables.contains("/usr/local/bin/docker") ? down : nil }
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { _ in true }) { candidates in
        catalog.measuredAgain(candidates, in: catalog.only(candidates).discovery(fixture: home, locateTool: locate))
    }
    #expect(later.records.first?.laterMeasurement?.finding == .unmeasured)
    #expect(later.records.first?.laterMeasurementText == "Couldn’t measure it again a minute later.")
}

/// Nothing to measure again means no wait; a cancelled wait measures nothing and records nothing.
@Test func onlyStoppedDaemonWorkIsMeasuredAgainAndACancelledWaitRecordsNothing() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let finished = try await dockerRunning(home, docker: docker, choose: ["docker-images"])
    #expect(finished.result.records.first?.state == .succeeded && finished.result.records.first?.mayStillBeFinishing == nil)
    let waited = Counter()
    let untouched = await finished.run.measureAgainLater(finished.result, of: finished.approval, wait: { _ in waited.increment(); return true }) { _ in
        Issue.record("measured an item whose tool finished"); return [:]
    }
    #expect(waited.value == 0 && untouched.records.first?.laterMeasurement == nil)

    let length = uniqueSleep()
    let slow = try fakeDocker(home, prune: "sleep \(length)")
    let stopped = try await dockerRunning(home, docker: slow, choose: ["docker-build-cache"], timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    let cancelled = await stopped.run.measureAgainLater(stopped.result, of: stopped.approval, wait: { _ in false }) { _ in
        Issue.record("measured after a cancelled wait"); return [:]
    }
    #expect(cancelled.records.first?.laterMeasurement == nil)
    // #209 point 2: quitting during the wait cancels it. The journal keeps "may still be finishing", and nothing
    // measures it on the next launch.
    let kept = try #require(try stopped.journal.records().first { $0.ruleID == "docker-build-cache" })
    #expect(kept.laterMeasurement == nil && kept.mayStillBeFinishing == true)
    #expect(kept.state == .failed && kept.outcomeTitle == "Partly removed" && kept.message.contains("may still be finishing"))
}
/// Durations collected from any thread, in order.
private final class Delays: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Duration] = []
    func append(_ delay: Duration) { lock.lock(); list.append(delay); lock.unlock() }
    var values: [Duration] { lock.lock(); defer { lock.unlock() }; return list }
}
/// Counts calls from any thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
