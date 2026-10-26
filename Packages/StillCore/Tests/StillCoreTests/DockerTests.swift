import Foundation
import Testing
@testable import StillCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillDocker-\(UUID())")
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
    #expect(catalog.rule("docker-build-cache")?.tool?.commandLine == "docker builder prune -f")
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
private func dockerRun(_ home: URL, docker: URL, choose ruleIDs: Set<String>, volume: FakeVolume = FakeVolume(), previewOnly: Bool = false) async throws -> CatalogExecutionResult {
    let catalog = Catalog(rules: fixtureRules)
    let chosen = catalog.discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil }).filter { ruleIDs.contains($0.ruleID) }
    try #require(chosen.count == ruleIDs.count)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: EverythingRunning()), measure: volume.read, trash: TrashNeverUsed())
    return await run.execute(CatalogApproval(candidates: chosen, previewOnly: previewOnly))
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
    #expect(Set(calls(home).dropFirst()) == ["image prune -a -f", "builder prune -f", "container prune -f"])
    #expect(result.estimatedBytes == 2_500_000_000 + 1_234_000_000 + 120_000_000)
}

@Test func previewOnlyLogsTheDockerCommandWithoutRunningIt() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let result = try await dockerRun(home, docker: docker, choose: ["docker-build-cache"], previewOnly: true)
    let record = try #require(result.records.first)
    #expect(record.state == .skipped)
    #expect(record.message.hasPrefix("Preview only: would run docker builder prune -f (1.23 GB)"))
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
