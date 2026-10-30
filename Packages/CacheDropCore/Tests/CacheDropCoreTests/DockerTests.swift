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

/// What `docker system df -v --format json` prints for `report`: one JSON object, trimmed to a few of its fields.
/// The running container keeps postgres (1.5 GB); the exited one's image goes with the rest.
private let verboseReport = """
{"Images":[{"Containers":"1","Digest":"sha256:aa11bb22","ID":"sha256:5f2b4c1a9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b","Repository":"postgres","SharedSize":"0B","Size":"1.5GB","Tag":"latest","UniqueSize":"1.5GB"},\
{"Containers":"1","ID":"sha256:9a8b7c6d5e4f","Repository":"node","SharedSize":"0B","Size":"2GB","Tag":"22-slim","UniqueSize":"2GB"},\
{"Containers":"0","ID":"sha256:0c1d2e3f4a5b","Repository":"alpine","SharedSize":"0B","Size":"500MB","Tag":"3.19","UniqueSize":"500MB"}],\
"Containers":[{"ID":"599fd72b0022","Image":"postgres:latest","Names":"db","Size":"4.1kB","State":"running","Status":"Up 2 hours"},\
{"ID":"f57f2f889c09","Image":"node:22-slim","Names":"build","Size":"120MB","State":"exited","Status":"Exited (0) 3 days ago"}],\
"Volumes":[],"BuildCache":[]}
"""

/// A stand-in `docker` in the fixture that answers `system df` with `df`, `system df -v` with `verbose`, and logs every call;
/// the real docker is never run by tests.
private func fakeDocker(_ home: URL, df: String = "cat \"$(dirname \"$0\")/df.json\"", verbose: String = "cat \"$(dirname \"$0\")/dfv.json\"",
                        prune: String = "echo 'Total reclaimed space: 1GB'") throws -> URL {
    let tool = home.appendingPathComponent("tools/docker")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try report.write(to: home.appendingPathComponent("tools/df.json"), atomically: true, encoding: .utf8)
    try verboseReport.write(to: home.appendingPathComponent("tools/dfv.json"), atomically: true, encoding: .utf8)
    let script = """
    #!/bin/sh
    echo "$@" >> "$(dirname "$0")/calls"
    if test "$*" = "system df --format json"; then
    \(df)
    elif test "$*" = "system df -v --format json"; then
    \(verbose)
    else
    \(prune)
    fi
    """
    try script.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}
/// The fixture's candidates with `docker` as the only tool, discovered on a thread of its own: discovery waits on each
/// `docker` call, and these tests make several, so they must not hold a Swift concurrency thread (#200, `onOwnThread`).
private func discoveredOffThePool(_ home: URL, _ docker: URL) async throws -> [Candidate] {
    try await onOwnThread { Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil }) }
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
    // One `system df` for all three kinds, and its `-v` list since a container is running; nothing else is run while scanning.
    #expect(calls(home) == ["system df --format json", "system df -v --format json"])
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
    echo '{"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"2","Type":"Images"}'
    echo '{"Active":"0","Reclaimable":"N/A","Size":"N/A","TotalCount":"3","Type":"Build Cache"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Containers"}'
    """)
    let found = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: { $0.executables.contains("/usr/local/bin/docker") ? docker : nil })
    #expect(found.map(\.ruleID) == ["docker-build-cache"])
    #expect(found.map(SizeEstimate.init) == [.unknown])
}

/// #407: `builder prune -a` removes the whole build cache, so it is sized by its total, never by Reclaimable, which read
/// 12.29 kB for this same 642.8 MB cache on a real run (#376).
@Test func theBuildCacheIsSizedByItsTotalSinceThePruneRemovesAllOfIt() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, df: """
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Images"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Containers"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Local Volumes"}'
    echo '{"Active":"0","Reclaimable":"12.29kB","Size":"642.8MB","TotalCount":"11","Type":"Build Cache"}'
    """)
    let found = try await discoveredOffThePool(home, docker)
    #expect(found.map(\.ruleID) == ["docker-build-cache"])
    #expect(found.first?.estimatedBytes == 642_800_000)
}

/// #407: `image prune -a` runs after the stopped containers go (Decision 85), so with no container running it removes every
/// image, including one Reclaimable counts as in use by a stopped container (13.66 MB estimated, 348.8 MB removed on #376).
@Test func withNoContainerRunningEveryImageIsCounted() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, df: """
    echo '{"Active":"1","Reclaimable":"13.66MB (3%)","Size":"362.5MB","TotalCount":"2","Type":"Images"}'
    echo '{"Active":"0","Reclaimable":"4.096kB (100%)","Size":"4.096kB","TotalCount":"1","Type":"Containers"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Local Volumes"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}'
    """)
    let found = try await discoveredOffThePool(home, docker)
    let byRule = Dictionary(uniqueKeysWithValues: found.map { ($0.ruleID, $0.estimatedBytes) })
    #expect(byRule == ["docker-images": 362_500_000, "docker-containers": 4_096])
    // Nothing runs, so nothing is kept: the plain `system df` is enough.
    #expect(calls(home) == ["system df --format json"])
}

/// #407: with a container running, `image prune -a` keeps the images running containers use and removes the rest, so
/// images are every image's size less those. Shapes from a real Docker Desktop 29.9.2 run.
@Test func imagesARunningContainerUsesAreTheOnlyOnesLeftOut() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home, df: """
    echo '{"Active":"2","Reclaimable":"11.86MB (37%)","Size":"31.69MB","TotalCount":"3","Type":"Images"}'
    echo '{"Active":"1","Reclaimable":"4.096kB (50%)","Size":"8.192kB","TotalCount":"2","Type":"Containers"}'
    echo '{"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Local Volumes"}'
    echo '{"Active":"0","Reclaimable":"100MB","Size":"113.6MB","TotalCount":"4","Type":"Build Cache"}'
    """, verbose: """
    echo '{"Images":[{"Containers":"1","CreatedAt":"2026-04-16 19:53:24 -0400 EDT","CreatedSince":"6 months ago","Digest":"","ID":"sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc","Repository":"alpine","SharedSize":"0B","Size":"13.7MB","Tag":"3.20","UniqueSize":"13.66MB"},{"Containers":"0","CreatedAt":"2025-10-08 07:10:40 -0400 EDT","CreatedSince":"12 months ago","Digest":"","ID":"sha256:6baf43584bcb78f2e5847d1de515f23499913ac9f12bdf834811a3145eb11ca1","Repository":"alpine","SharedSize":"0B","Size":"11.9MB","Tag":"3.19","UniqueSize":"11.86MB"},{"Containers":"1","CreatedAt":"2023-05-18 18:34:17 -0400 EDT","CreatedSince":"3 years ago","Digest":"","ID":"sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662","Repository":"busybox","SharedSize":"0B","Size":"6.14MB","Tag":"1.36","UniqueSize":"6.139MB"}],"Containers":[{"Command":"\\"true\\"","CreatedAt":"2026-10-29 13:28:58 -0400 EDT","HealthStatus":"none","ID":"f57f2f889c094f3e4be74babf3023056d199f0ebd74acfcce0b8c4bd6fd3edc0","Image":"busybox:1.36","Labels":"desktop.docker.io/ports.scheme=v2","LocalVolumes":"0","Mounts":"","Names":"cd-stopped","Networks":"bridge","Platform":null,"Ports":"","RunningFor":"2 seconds ago","Size":"4.1kB","State":"created","Status":"Created"},{"Command":"\\"sleep 3600\\"","CreatedAt":"2026-10-29 13:28:58 -0400 EDT","HealthStatus":"none","ID":"599fd72b00222737605657c7d1fb4a4fb926340c1be882590317cc2717ae4835","Image":"alpine:3.20","Labels":"desktop.docker.io/ports.scheme=v2","LocalVolumes":"0","Mounts":"","Names":"cd-running","Networks":"bridge","Platform":null,"Ports":"","RunningFor":"2 seconds ago","Size":"4.1kB","State":"running","Status":"Up 2 seconds"}],"Volumes":[],"BuildCache":[{"CacheType":"regular","CreatedAt":"2026-10-29 17:28:59.418305256 +0000 UTC","CreatedSince":"1 second ago","Description":"","ID":"0oxs9y37g2l3zvuf6v7owml5e","InUse":"false","LastUsedAt":"2026-10-29 17:29:00.767080507 +0000 UTC","LastUsedSince":"Less than a second ago","Parent":"","Shared":"true","Size":"13.6MB","UsageCount":"1"}]}'
    """)
    let found = try await discoveredOffThePool(home, docker)
    let byRule = Dictionary(uniqueKeysWithValues: found.map { ($0.ruleID, $0.estimatedBytes) })
    // 31.69 MB of images less alpine:3.20's 13.7 MB, which the running container keeps.
    #expect(byRule["docker-images"] == 17_990_000)
    // 113.6 MB of build cache less the 13.6 MB record Docker marks shared, which stays with alpine:3.20.
    #expect(byRule["docker-build-cache"] == 100_000_000)
    #expect(calls(home) == ["system df --format json", "system df -v --format json"])
}

/// A running container whose image can't be found in the list falls back to Reclaimable, which can only count too little.
@Test func aRunningImageThatCantBeMatchedFallsBackToReclaimable() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try verboseReport.replacingOccurrences(of: "\"Image\":\"postgres:latest\"", with: "\"Image\":\"mysql:8\"")
        .write(to: home.appendingPathComponent("unmatched.json"), atomically: true, encoding: .utf8)
    let docker = try fakeDocker(home, verbose: "cat '\(home.path)/unmatched.json'")
    let found = try await discoveredOffThePool(home, docker)
    #expect(found.first { $0.ruleID == "docker-images" }?.estimatedBytes == 2_500_000_000)
    #expect(found.count == 3)
}

/// With a container running, a `-v` list that can't be read leaves images and build cache at an unknown size, never a guess
/// that could be too much or read as gone (Decision 45). Stopped containers keep their size.
@Test func aListThatCantBeReadLeavesImagesAndBuildCacheUnknown() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for verbose in ["echo json", "exit 1"] {
        let docker = try fakeDocker(home, verbose: verbose)
        let found = try await discoveredOffThePool(home, docker)
        let byRule = Dictionary(uniqueKeysWithValues: found.map { ($0.ruleID, $0) })
        #expect(byRule["docker-images"].map(SizeEstimate.init) == .unknown, "\(verbose)")
        #expect(byRule["docker-build-cache"].map(SizeEstimate.init) == .unknown, "\(verbose)")
        #expect(byRule["docker-containers"]?.estimatedBytes == 120_000_000, "\(verbose)")
    }
}

/// `container prune` leaves paused and restarting containers, so their images stay too; exited, created and dead ones go.
@Test func aPausedContainersImageStays() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try verboseReport.replacingOccurrences(of: "\"State\":\"exited\"", with: "\"State\":\"paused\"")
        .write(to: home.appendingPathComponent("paused.json"), atomically: true, encoding: .utf8)
    let docker = try fakeDocker(home, verbose: "cat '\(home.path)/paused.json'")
    let found = try await discoveredOffThePool(home, docker)
    // 4 GB less postgres (1.5 GB) and node (2 GB): only alpine:3.19 goes.
    #expect(found.first { $0.ruleID == "docker-images" }?.estimatedBytes == 500_000_000)
}

/// The image a running container names may be its tag, a bare repository meaning `latest`, a short or full ID, or a digest.
/// Anything else isn't the kept image, so images fall back to Reclaimable.
@Test func aRunningContainersImageIsFoundByTagIDOrDigest() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let names = ["postgres:latest": true, "postgres": true, "5f2b4c1a9e8d": true, "sha256:5f2b4c1a9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b": true,
                 "postgres@sha256:aa11bb22": true, "postgres:16": false, "5f2b": false, "postgres@sha256:cc33": false]
    try report.replacingOccurrences(of: "\"Reclaimable\":\"2.5GB (62%)\"", with: "\"Reclaimable\":\"2GB (50%)\"")
        .write(to: home.appendingPathComponent("df2.json"), atomically: true, encoding: .utf8)
    for (name, found) in names {
        try verboseReport.replacingOccurrences(of: "\"Image\":\"postgres:latest\"", with: "\"Image\":\"\(name)\"")
            .write(to: home.appendingPathComponent("named.json"), atomically: true, encoding: .utf8)
        let docker = try fakeDocker(home, df: "cat '\(home.path)/df2.json'", verbose: "cat '\(home.path)/named.json'")
        let images = try await discoveredOffThePool(home, docker)
            .first { $0.ruleID == "docker-images" }
        // 4 GB less postgres's 1.5 GB when it's found; Reclaimable's 2 GB when it isn't.
        #expect(images?.estimatedBytes == (found ? 2_500_000_000 : 2_000_000_000), "\(name)")
    }
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
    /// After this many readings, the volume can't be read.
    var readable = Int.max
    func read(_ url: URL) -> CapacitySample? {
        lock.lock(); defer { lock.unlock() }
        guard readable > 0 else { return nil }
        readable -= 1
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
    #expect(calls(home) == ["system df --format json", "system df -v --format json", "image prune -a -f"])
    // The folder that anchors the rule is never touched.
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".docker").path))
}

@Test func eachChosenKindRunsItsOwnCommandAndTheEstimateCountsAllOfThem() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let result = try await dockerRun(home, docker: docker, choose: ["docker-images", "docker-build-cache", "docker-containers"])
    #expect(result.records.allSatisfy { $0.state == .succeeded })
    #expect(Set(calls(home).dropFirst(2)) == ["image prune -a -f", "builder prune -a -f", "container prune -f"])
    #expect(result.estimatedBytes == 2_500_000_000 + 1_234_000_000 + 120_000_000)
}

/// #393: `image prune -a` keeps every image a container uses, stopped ones included, so stopped containers go first.
/// Otherwise an image only a stopped container used would survive the run that removes that container.
@Test func stoppedContainersArePrunedBeforeImages() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let result = try await dockerRun(home, docker: docker, choose: ["docker-images", "docker-build-cache", "docker-containers"])
    #expect(result.records.map(\.ruleID) == ["docker-containers", "docker-images", "docker-build-cache"])
    #expect(Array(calls(home).dropFirst(2)) == ["container prune -f", "image prune -a -f", "builder prune -a -f"])
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
    #expect(calls(home) == ["system df --format json", "system df -v --format json"])
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
    #expect(run.plannedBytes == 2_500_000_000 + 120_000_000)
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
    // Docker's three prunes share ~/.docker: one line for the folder, not one per rule (#482).
    #expect(running.coverageChanges.count == 1 && running.coverageChanges.first?.kind == .newlyReadable)
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

/// The review shows each tool rule's exact command under its files, from the rule's own `tool`, so the two never drift; the
/// consequence says only what goes and what stays, never the command again (#462, Decision 92).
@Test func everyToolRuleShowsTheExactCommandItRuns() {
    for rule in fixtureRules where rule.action == .tool {
        let command = try? #require(rule.tool?.commandLine)
        #expect(command?.isEmpty == false, "\(rule.id)")
        #expect(!rule.consequence.contains("`"), "\(rule.id): \(rule.consequence)")
    }
    #expect(fixtureRules.first { $0.id == "docker-build-cache" }?.tool?.commandLine == "docker builder prune -a -f")
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
    #expect(record.message.hasPrefix("Stopped waiting when you canceled. docker image prune -a -f hands its work to a background service, which may still be finishing"))
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
    try report.replacingOccurrences(of: "\"Size\":\"4GB\"", with: "\"Size\":\"1.5GB\"")
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
    let atAMinute = report.replacingOccurrences(of: "\"Size\":\"4GB\"", with: "\"Size\":\"2.5GB\"")
        .replacingOccurrences(of: "\"Reclaimable\":\"1.234GB\",\"Size\":\"1.234GB\"", with: "\"Reclaimable\":\"0B\",\"Size\":\"0B\"")
    // At 5 minutes: the images are gone too.
    let atFive = atAMinute.replacingOccurrences(of: "\"Size\":\"2.5GB\"", with: "\"Size\":\"1.5GB\"")
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

/// #407: images measured again while `-v` can't be read are unmeasured, never gone, though `system df` answered.
@Test func aStoppedImagePruneWhoseListCantBeReadLaterIsntGone() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep()
    let docker = try fakeDocker(home, prune: "sleep \(length)")
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-images"], timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    // Reclaimable now reads 0 for images a stopped container uses, as on #376, so falling back to it would read as gone.
    let noList = try fakeDocker(home, verbose: "exit 1", prune: "exit 1")
    try report.replacingOccurrences(of: "\"Reclaimable\":\"2.5GB (62%)\"", with: "\"Reclaimable\":\"0B (0%)\"")
        .write(to: home.appendingPathComponent("tools/df.json"), atomically: true, encoding: .utf8)
    let catalog = done.catalog, locate: @Sendable (ToolCommand) -> URL? = { $0.executables.contains("/usr/local/bin/docker") ? noList : nil }
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { _ in true }) { candidates in
        catalog.measuredAgain(candidates, in: catalog.only(candidates).discovery(fixture: home, locateTool: locate))
    }
    #expect(later.records.first?.laterMeasurement?.finding == .unmeasured)
    #expect(later.records.first?.outcomeTitle != "Removed")
}

/// A prune that finished isn't measured again; its run waits only to read the disk once more (#411). A dry run doesn't wait.
/// A cancelled wait measures nothing and records nothing.
@Test func aFinishedPruneIsOnlyReadAgainAndACancelledWaitRecordsNothing() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let finished = try await dockerRunning(home, docker: docker, choose: ["docker-images"])
    #expect(finished.result.records.first?.state == .succeeded && finished.result.records.first?.mayStillBeFinishing == nil)
    let waited = Counter()
    let untouched = await finished.run.measureAgainLater(finished.result, of: finished.approval, wait: { _ in waited.increment(); return true }) { _ in
        Issue.record("measured an item whose tool finished"); return [:]
    }
    #expect(waited.value == 1 && untouched.records.first?.laterMeasurement == nil)
    #expect(untouched.records.first?.settledCapacity != nil)
    let dryRun = try await dockerRunning(home, docker: docker, choose: ["docker-images"], previewOnly: true)
    #expect(!dryRun.run.measuresLater(dryRun.result) && finished.run.measuresLater(finished.result))

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

/// #411: Docker hands freed space back to macOS after the prune returns (about 30 s on #376's real run), so a minute after
/// a run whose Docker prunes completed, the disk's free space is read once more. Results show it under the measured freed
/// space, which doesn't change; the last Docker item's record keeps it for History.
@Test func aMinuteAfterCompletedPrunesTheDisksFreeSpaceIsReadOnceMore() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let volume = FakeVolume()
    // Before and after each prune, then a minute later.
    volume.freedPerRead = [0, 100, 0, 200, 2_000_000]
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-images", "docker-build-cache"], volume: volume)
    #expect(done.result.records.allSatisfy { $0.state == .succeeded && $0.laterMeasurementText == nil })
    // Results say a check is coming until it's done.
    #expect(done.run.settles(done.result) && done.result.settledLine(checked: false) == nil)
    let waits = Delays()
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { waits.append($0); return true }) { _ in
        Issue.record("Nothing was stopped, so nothing is measured again"); return [:]
    }
    #expect(waits.values == [.seconds(60)])
    let byRule = Dictionary(uniqueKeysWithValues: later.records.map { ($0.ruleID ?? "", $0) })
    #expect(later.settledLine(checked: true) == "2 MB more free a minute later")
    #expect(!done.run.settles(later))
    #expect(later.measuredFreedBytes == 300)
    // No row repeats it in Results. The build cache is pruned last, so its record carries the reading for History.
    #expect(later.records.allSatisfy { $0.laterMeasurementText == nil })
    #expect(byRule["docker-images"]?.settledText == nil)
    #expect(byRule["docker-build-cache"]?.settledText == "A minute later, the disk had 2 MB more free.")
    let journaled = try #require(try done.journal.records().first { $0.ruleID == "docker-build-cache" })
    #expect(journaled.settledText == "A minute later, the disk had 2 MB more free.")
}

/// #411: a stopped prune and a completed one in the same run share the one wait. When the disk has no more free space a
/// minute later, the line says so, never a size.
@Test func aStoppedAndACompletedPruneShareTheMinutesWait() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep()
    // Only the image prune outlasts the time limit.
    let docker = try fakeDocker(home, prune: "case \"$*\" in image*) sleep \(length);; *) echo 'Total reclaimed space: 1GB';; esac")
    let volume = FakeVolume()
    // Before the images (stopped, so no after), before and after the build cache, then a minute later: 50 bytes less free.
    volume.freedPerRead = [0, 0, 100, -50]
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-images", "docker-build-cache"], volume: volume, timeout: 0.5)
    survivorsAfterSettling(length).forEach { kill($0, SIGKILL) }
    let byRule = Dictionary(uniqueKeysWithValues: done.result.records.map { ($0.ruleID ?? "", $0) })
    #expect(byRule["docker-images"]?.mayStillBeFinishing == true && byRule["docker-build-cache"]?.state == .succeeded)
    let waits = Delays()
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { waits.append($0); return true }) { candidates in
        Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, LaterMeasurement.Finding.gone) })
    }
    #expect(waits.values == [.seconds(60)])
    let after = Dictionary(uniqueKeysWithValues: later.records.map { ($0.ruleID ?? "", $0) })
    #expect(after["docker-images"]?.laterMeasurement?.finding == .gone)
    #expect(later.settledLine(checked: true) == "No more free space a minute later")
    #expect(after["docker-build-cache"]?.settledText == "A minute later, the disk had no more free space.")
}

/// #411: an item cleaned after the last Docker prune (simulators and Android come after Docker) freed space the run already
/// counted, so the minute's reading is against the run's last reading, never the Docker item's.
@Test func theMinutesReadingIsAgainstTheRunsLastReading() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches/Yarn"), withIntermediateDirectories: true)
    try Data(count: 4096).write(to: home.appendingPathComponent("Library/Caches/Yarn/package.tgz"))
    let catalog = Catalog(rules: fixtureRules)
    let found = try await discoveredOffThePool(home, docker)
    let cache = try #require(found.first { $0.ruleID == "docker-build-cache" }), yarn = try #require(found.first { $0.ruleID == "yarn-cache" })
    let volume = FakeVolume()
    // Before and after the build cache, before and after Yarn's cache (5 kB freed), then a minute later 2 MB more.
    volume.freedPerRead = [0, 100, 0, 5_000, 2_000_000]
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NothingRunning()), measure: volume.read, trash: TrashNeverUsed())
    let approval = CatalogApproval(candidates: [cache, yarn], previewOnly: false)
    let result = await run.execute(approval)
    #expect(result.records.map(\.state) == [.succeeded, .succeeded])
    let later = await run.measureAgainLater(result, of: approval, wait: { _ in true }) { _ in [:] }
    #expect(later.settledLine(checked: true) == "2 MB more free a minute later")
}
/// No owner is running, so an owned rule such as Yarn's is cleaned.
private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }

/// #411: the review sheet says before the run, once, that Docker's space reaches macOS a little after its prune, so
/// Results' "check again" isn't a surprise. Nothing else gets the note.
@Test func theReviewSheetSaysDockersSpaceArrivesAfterThePrune() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let catalog = Catalog(rules: fixtureRules)
    let found = try await discoveredOffThePool(home, docker)
    #expect(catalog.dockerReviewNote(for: found) == "Space from Docker reaches macOS up to a minute after it finishes.")
    #expect(catalog.dockerReviewNote(for: found.filter { !$0.ruleID.hasPrefix("docker-") }) == nil)
    // Docker not running has its own notice instead of rows (#376), so the consequence doesn't repeat it.
    #expect(catalog.rule("docker-images")?.consequence.contains("Docker must be running") == false)
}

/// #411: a reading a minute later that can't be made still answers Results' "check again", never leaving it unresolved.
@Test func aMinutesReadingThatCantBeMadeSaysSo() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let volume = FakeVolume()
    // Before and after the prune; the minute's reading fails.
    volume.readable = 2
    let done = try await dockerRunning(home, docker: docker, choose: ["docker-build-cache"], volume: volume)
    let later = await done.run.measureAgainLater(done.result, of: done.approval, wait: { _ in true }) { _ in [:] }
    #expect(later.records.first?.settledText == nil)
    #expect(later.settledLine(checked: false) == nil)
    #expect(later.settledLine(checked: true) == "Couldn’t check the disk again a minute later")
}

/// #418: other activity can move free space the other way while Docker's space hasn't arrived yet (−274 KB on the owner's
/// run), so the measured freed space shown is never below 0. The sum itself is kept.
@Test func measuredFreedSpaceIsNeverShownBelowZero() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let docker = try fakeDocker(home)
    let volume = FakeVolume()
    volume.freedPerRead = [0, -274_000]
    let result = try await dockerRun(home, docker: docker, choose: ["docker-build-cache"], volume: volume)
    #expect(result.measuredFreedBytes == -274_000)
    #expect(MeasuredFreedSpace.shown(result.measuredFreedBytes) == 0)
    #expect(MeasuredFreedSpace.shown(300) == 300 && MeasuredFreedSpace.shown(nil) == nil)
}

/// #419: one short line per plan row (Decision 25).
@Test func dockerRowsHaveOneShortLineOfDetail() {
    let catalog = Catalog(rules: fixtureRules)
    #expect(catalog.rule("docker-containers")?.detail == "Containers that aren’t running. Size is an estimate.")
    #expect(catalog.rule("docker-images")?.detail == "Images no running container uses. Size is an estimate.")
    #expect(catalog.rule("docker-build-cache")?.detail == "Layers Docker kept to speed up builds. Size is an estimate.")
}

/// #420: `.docker` only anchors Docker's rules; the prunes work inside Docker's VM, so their rows show no location, path
/// or Reveal in Finder. Every other rule's folder is what it cleans.
@Test func dockerRulesShowNoFolder() {
    let catalog = Catalog(rules: fixtureRules)
    let docker = catalog.rules.filter { $0.id.hasPrefix("docker-") }, others = catalog.rules.filter { !$0.id.hasPrefix("docker-") }
    #expect(docker.count == 3 && docker.allSatisfy { !$0.showsFolder })
    #expect(others.allSatisfy { $0.showsFolder })
}
