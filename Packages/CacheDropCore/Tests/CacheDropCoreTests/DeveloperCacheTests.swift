import Foundation
import Testing
@testable import CacheDropCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropDevCaches-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func makeFolder(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative).appendingPathComponent("entry")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

@Test func eachDeveloperCacheIsACandidateOnlyWhenItsFolderExists() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: fixtureRules)
    #expect(catalog.discover(fixture: home).isEmpty)
    let folders = [
        "Library/Caches/Yarn": "yarn-cache", ".yarn/berry/cache": "yarn-cache",
        "Library/Caches/pnpm": "pnpm-cache",
        "Library/Caches/pip": "pip-cache",
        ".cargo/registry": "cargo-cache", ".cargo/git": "cargo-cache",
        ".gradle/caches": "gradle-cache", "Library/Caches/CocoaPods": "cocoapods-cache",
    ]
    for folder in folders.keys { try makeFolder(home, folder) }
    // uv's cache is a tool rule that uv itself names (`UVCacheTests`): without uv it's never offered, so never deleted.
    try makeFolder(home, ".cache/uv")
    let found = catalog.discover(fixture: home)
    #expect(Dictionary(found.map { ($0.url.path, $0.ruleID) }, uniquingKeysWith: { a, _ in a })
            == Dictionary(uniqueKeysWithValues: folders.map { (home.appendingPathComponent($0.key).path, $0.value) }))
    #expect(found.allSatisfy { $0.action == .delete && $0.logicalBytes == 100 })
    // Installed tools and their downloads stay out of reach.
    #expect(!found.contains { $0.url.path.hasPrefix(home.appendingPathComponent(".cargo/bin").path) })
}

private func owner(_ id: String) throws -> RuleOwner { try #require(fixtureRules.first { $0.id == id }?.owner) }

@Test func eachCommandLineCacheIsRefusedOnlyWhileItsOwnToolRuns() throws {
    let cases: [(String, [[String]], [[String]])] = [
        ("yarn-cache", [["node", "/usr/local/lib/node_modules/corepack/dist/yarn.js", "install"], ["node", "/p/.yarn/releases/yarn-4.5.0.cjs"], ["/opt/homebrew/bin/yarn"]],
                       [["node", "/p/node_modules/.bin/vite"], ["/usr/bin/yarnspinner"]]),
        ("pnpm-store", [["node", "/opt/homebrew/lib/node_modules/pnpm/bin/pnpm.cjs", "add"], ["/Users/me/Library/pnpm/pnpm", "i"]],
                       [["node", "server.js", "pnpm"]]),
        ("uv-cache", [["/Users/me/.local/bin/uv", "sync"], ["uvx", "ruff"]], [["/usr/bin/python3", "-m", "uvicorn", "app:app"]]),
        ("pip-cache", [["/usr/bin/python3", "-m", "pip", "install", "x"], ["/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/pip3.12", "install"], ["pip3"]],
                      [["/usr/bin/python3", "server.py"], ["/opt/homebrew/bin/pipx", "list"]]),
        ("cargo-cache", [["/Users/me/.cargo/bin/cargo", "build"], ["/Users/me/.rustup/toolchains/stable/bin/cargo-clippy"]],
                        [["/Users/me/.cargo/bin/rust-analyzer"], ["/Users/me/.cargo/bin/ripgrep"]]),
        ("gradle-cache", [["/usr/bin/java", "-Xmx2g", "-cp", "/Users/me/.gradle/wrapper/dists/gradle-8.10/lib/gradle-daemon-main-8.10.jar", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "8.10"],
                          ["/bin/sh", "./gradlew", "assemble"], ["java", "-classpath", "/p/gradle/wrapper/gradle-wrapper.jar", "org.gradle.wrapper.GradleWrapperMain"]],
                         [["/usr/bin/java", "-jar", "app.jar"]]),
        ("cocoapods-cache", [["/usr/bin/ruby", "/usr/local/bin/pod", "install"], ["/opt/homebrew/bin/pod", "update"]], [["/usr/bin/ruby", "server.rb"], ["/usr/bin/podman"]]),
    ]
    for (rule, running, unrelated) in cases {
        let owner = try owner(rule)
        for argv in running { #expect(owner.matches(argv), "\(rule) should see \(argv)") }
        for argv in unrelated { #expect(!owner.matches(argv), "\(rule) should ignore \(argv)") }
    }
}

@Test func ccacheIsNeverACandidateEvenWhenARuleNamesIt() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for folder in ["Library/Caches/ccache", ".ccache", ".cache/ccache", "Library/Caches/Yarn"] { try makeFolder(home, folder) }
    #expect(Catalog(rules: fixtureRules).discover(fixture: home).map(\.ruleID) == ["yarn-cache"])
    let greedy = Catalog(rules: [CleanupRule(id: "greedy", category: .developer, title: "Caches", detail: "", consequence: "", regen: .cache, action: .delete,
                                             locations: ["Library/Caches/ccache", ".ccache", ".cache/ccache", "Library/Caches/Yarn"], owner: nil)])
    #expect(greedy.discover(fixture: home).map(\.url.lastPathComponent) == ["Yarn"])
}

@Test func aFolderHoldingACcacheStoreIsRefusedJustBeforeActing() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/pip")
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home).first)
    try makeFolder(home, "Library/Caches/pip/ccache")
    #expect(CandidateCheck(catalog: catalog, running: FixtureNothingRunning()).check(candidate) == .protected("ccache"))
}

/// A stand-in tool script inside the fixture; the real brew is never run by tests.
private func fakeTool(_ home: URL, _ script: String) throws -> URL {
    let tool = home.appendingPathComponent("tools/brew")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    // `brew --cache`, asked at discovery (#170), names the usual folder; `script` is what any other call runs.
    let answer = "[ \"$*\" = --cache ] && { echo '\(home.path)/Library/Caches/Homebrew'; exit 0; }\n"
    try ("#!/bin/sh\n" + answer + script + "\n").write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}

@Test func homebrewAppearsOnlyWhenBrewIsInstalledAndItsCacheExists() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: fixtureRules)
    let brew = try fakeTool(home, "exit 0")
    let installed = onlyTool("brew", brew)
    #expect(catalog.discover(fixture: home, locateTool: installed).isEmpty)
    try makeFolder(home, "Library/Caches/Homebrew", bytes: 2000)
    #expect(catalog.discover(fixture: home, locateTool: { _ in nil }).isEmpty)
    let candidate = try #require(catalog.discover(fixture: home, locateTool: installed).first)
    #expect(candidate.ruleID == "homebrew")
    #expect(candidate.action == .tool)
    #expect(candidate.toolURL == brew)
    #expect(candidate.logicalBytes == 2000)
    let rule = try #require(catalog.rule("homebrew"))
    #expect(rule.tool?.commandLine == "brew cleanup -s")
    #expect(rule.tool?.executables == ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
}

/// A fake volume whose available space grows by what each item frees.
/// The Homebrew rule pointed at a fake brew, optionally with a shorter time limit.
private func homebrewRun(_ home: URL, script: String, timeout: TimeInterval? = nil, volume: FixtureVolume = FixtureVolume(), dryRun: Bool = false) async throws -> CatalogExecutionResult {
    let brew = try fakeTool(home, script)
    var rules = fixtureRules
    if let timeout, let index = rules.firstIndex(where: { $0.id == "homebrew" }) {
        let rule = rules[index], tool = try #require(rule.tool)
        rules[index] = CleanupRule(id: rule.id, category: rule.category, title: rule.title, detail: rule.detail, consequence: rule.consequence, regen: rule.regen, action: rule.action, locations: rule.locations, owner: rule.owner,
                                   tool: ToolCommand(executables: tool.executables, arguments: tool.arguments, timeout: timeout, deletesLocationAfter: tool.deletesLocationAfter))
    }
    let catalog = Catalog(rules: rules)
    let candidate = try #require(catalog.discover(fixture: home, locateTool: onlyTool("brew", brew)).first)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: volume.read, trash: TrashNeverUsed())
    return await run.execute(CatalogApproval(candidates: [candidate], dryRun: dryRun))
}

@Test func homebrewRunsCleanupThenRemovesItsCacheAndReportsOutputAndMeasuredSpace() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew", bytes: 2000)
    let volume = FixtureVolume()
    volume.freedPerRead = [0, 8192]
    let marker = home.appendingPathComponent("ran")
    let result = try await homebrewRun(home, script: "echo \"$@\" > '\(marker.path)'\necho 'Removing: /opt/homebrew/Cellar/node/20.1 (2,000 files, 60MB)'", volume: volume)
    let record = try #require(result.records.first)
    #expect(record.state == .succeeded)
    #expect(record.action == "tool")
    #expect(try String(contentsOf: marker, encoding: .utf8) == "cleanup -s\n")
    #expect(record.toolOutput?.contains("Removing: /opt/homebrew/Cellar/node/20.1") == true)
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew").path))
    #expect(result.measuredFreedBytes == 8192)
    let reopened = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    #expect(try reopened.records().first?.toolOutput == record.toolOutput)
}

@Test func dryRunLogsTheCommandWithoutRunningIt() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew")
    let marker = home.appendingPathComponent("ran")
    let result = try await homebrewRun(home, script: "touch '\(marker.path)'", dryRun: true)
    let record = try #require(result.records.first)
    #expect(record.state == .skipped)
    #expect(record.message.hasPrefix("Dry run: would run brew cleanup -s, then delete the folder"))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
    #expect(result.measuredFreedBytes == nil)
}

@Test func aToolThatRunsPastItsTimeLimitIsStoppedAndTheFolderKept() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew")
    // A stand-in brew that starts its own child, like the real one does.
    let length = uniqueSleep(), lifetime = MarkedProcessLifetime(length), pids = home.appendingPathComponent("pids")
    let script = "echo started\n\(recordPid("$$", in: pids))\nsleep \(length) &\n\(recordPid("$!", in: pids))\nexec sleep \(length)"
    let result = try await homebrewRun(home, script: script, timeout: childStartedLimit)
    let left = stillRunning(recordedPids(pids))
    // Stopped at the limit, not left to finish its sleep: the tool, timed alone, lived the limit plus the stop's grace at most.
    #expect(lifetime.seconds < childStartedLimit + BoundedTool.stopGrace + 1)
    left.forEach { kill($0, SIGKILL) }
    #expect(recordedPids(pids).count == 2, "The stand-in starts its child before the time limit")
    #expect(left.isEmpty)
    let record = try #require(result.records.first)
    #expect(record.state == .failed)
    #expect(record.message == "Stopped at the 2-second time limit. brew cleanup -s may have cleaned part of it; the folder was left in place.")
    #expect(record.partlyRemoved == true)
    #expect(record.toolOutput == "started")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
}

/// A running tool holds no Swift concurrency thread (#200): with as many tools running at once as the pool has threads,
/// another async task still runs. Run under LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 to hold the pool to that width.
/// The tools wait for a release file; the async task writes it once it sees them all running. If the pool is held,
/// it never gets to, and a plain thread releases them after a long wait so the test ends, failing.
@Test func aRunningToolLeavesTheConcurrencyPoolFree() async throws {
    let shared = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: shared) }
    let release = shared.appendingPathComponent("release"), releasedByFallback = shared.appendingPathComponent("released-by-fallback")
    let count = ProcessInfo.processInfo.activeProcessorCount
    let homes = try (0..<count).map { _ in try fixtureHome() }
    defer { homes.forEach { try? FileManager.default.removeItem(at: $0) } }
    for home in homes { try makeFolder(home, "Library/Caches/Homebrew") }
    Thread {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while !FileManager.default.fileExists(atPath: release.path), ProcessInfo.processInfo.systemUptime < deadline { usleep(50_000) }
        if !FileManager.default.fileExists(atPath: release.path) {
            FileManager.default.createFile(atPath: releasedByFallback.path, contents: nil)
            FileManager.default.createFile(atPath: release.path, contents: nil)
        }
    }.start()
    try await withThrowingTaskGroup(of: CatalogExecutionResult.self) { group in
        for home in homes {
            let script = "touch '\(home.appendingPathComponent("running").path)'\nwhile [ ! -e '\(release.path)' ]; do sleep 0.05; done"
            group.addTask { try await homebrewRun(home, script: script, timeout: 60) }
        }
        group.addTask {
            while !homes.allSatisfy({ FileManager.default.fileExists(atPath: $0.appendingPathComponent("running").path) }) { try await Task.sleep(nanoseconds: 20_000_000) }
            FileManager.default.createFile(atPath: release.path, contents: nil)
            return CatalogExecutionResult(batchID: UUID(), records: [], dryRun: false, rejectedReplay: false, journalFailure: nil, estimatedBytes: 0)
        }
        for try await result in group { #expect(result.records.allSatisfy { $0.state == .succeeded }) }
    }
    #expect(!FileManager.default.fileExists(atPath: releasedByFallback.path))
}

/// Homebrew's cleanup followed by a plain delete (pnpm's metadata cache), run with `cancellation`.
private func cancellableRun(_ home: URL, brewScript: String, cancellation: CleanupCancellation, measure: @escaping @Sendable (URL) -> CapacitySample? = FixtureVolume().read) async throws -> CatalogExecutionResult {
    try makeFolder(home, "Library/Caches/Homebrew")
    try makeFolder(home, "Library/Caches/pnpm")
    let brew = try fakeTool(home, brewScript)
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discover(fixture: home, locateTool: onlyTool("brew", brew))
    let homebrew = try #require(found.first { $0.ruleID == "homebrew" })
    let pnpm = try #require(found.first { $0.ruleID == "pnpm-cache" })
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: measure, trash: TrashNeverUsed(), cancellation: cancellation)
    return await run.execute(CatalogApproval(candidates: [homebrew, pnpm], dryRun: false))
}

@Test func cancellingDuringAToolStopsItWithinTheGracePeriodAndRecordsItAsPartlyRemoved() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep(), running = home.appendingPathComponent("running"), pids = home.appendingPathComponent("pids")
    let cancellation = CleanupCancellation(), cancelledAt = CancelTime(), stopped = RecordedPidsGone(pids, count: 2)
    // Cancel once the stand-in brew, which starts its own child like the real one, is running.
    let watcher = CancelWhenFileAppears(running, cancel: cancellation, at: cancelledAt)
    defer { watcher.stop() }
    let script = "echo cleaning\n\(recordPid("$$", in: pids))\nsleep \(length) &\n\(recordPid("$!", in: pids))\ntouch '\(running.path)'\nexec sleep \(length)"
    let result = try await cancellableRun(home, brewScript: script, cancellation: cancellation)
    // Timed from the cancel until the tool's processes were gone, on a thread of its own: a busy run can take
    // seconds more to resume this test afterwards, which says nothing about how fast the tool was stopped (#224).
    let sinceCancel = cancelledAt.elapsed(until: stopped.at)
    let left = stillRunning(recordedPids(pids))
    left.forEach { kill($0, SIGKILL) }
    #expect(sinceCancel < BoundedTool.stopGrace + 1)
    #expect(recordedPids(pids).count == 2)
    #expect(left.isEmpty)
    let tool = try #require(result.records.first), next = try #require(result.records.last)
    #expect(tool.state == .failed)
    #expect(tool.partlyRemoved == true)
    #expect(tool.outcomeTitle == "Partly removed")
    #expect(tool.message == "Stopped when you canceled. brew cleanup -s may have cleaned part of it; the folder was left in place.")
    #expect(tool.toolOutput == "cleaning")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
    #expect(next.state == .cancelled && next.message == "Not started")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/pnpm/entry").path))
}

@Test func aCancelAfterAToolFinishedKeepsItsFolderAndStopsTheRun() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let length = uniqueSleep(), exited = home.appendingPathComponent("exited"), pids = home.appendingPathComponent("pids")
    let cancellation = CleanupCancellation()
    // The stand-in brew succeeds, leaving a child that holds its output open; the cancel lands once brew has exited (#195).
    let watcher = CancelWhenFileAppears(exited, cancel: cancellation)
    defer { watcher.stop() }
    let script = "p=$$\n( while :; do case \"$(ps -o stat= -p $p)\" in Z*|\"\") break;; esac; sleep 0.01; done; touch '\(exited.path)'; exec sleep \(length) ) &\n"
        + recordPid("$!", in: pids) + "\necho cleaned\nexit 0"
    let result = try await cancellableRun(home, brewScript: script, cancellation: cancellation)
    let left = stillRunning(recordedPids(pids))
    left.forEach { kill($0, SIGKILL) }
    #expect(cancellation.isCancelled)
    #expect(recordedPids(pids).count == 1)
    #expect(left.isEmpty)
    let tool = try #require(result.records.first), next = try #require(result.records.last)
    #expect(tool.state == .succeeded)
    #expect(tool.message == "Ran brew cleanup -s. Stopped before removing the folder, since you canceled.")
    #expect(tool.toolOutput == "cleaned")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
    #expect(next.state == .cancelled && next.message == "Not started")
}

@Test func cancellingJustBeforeAToolLaunchesRecordsItAsStoppedWithNothingChanged() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let ran = home.appendingPathComponent("ran")
    let cancellation = CleanupCancellation()
    // The space reading taken just before the tool starts is the last moment before launch.
    let result = try await cancellableRun(home, brewScript: "touch '\(ran.path)'", cancellation: cancellation,
                                          measure: { _ in cancellation.cancel(); return nil })
    #expect(!FileManager.default.fileExists(atPath: ran.path))
    let tool = try #require(result.records.first), next = try #require(result.records.last)
    #expect(tool.state == .cancelled)
    #expect(tool.partlyRemoved != true)
    #expect(tool.message == "Stopped before brew cleanup -s started. Nothing was changed.")
    #expect(tool.recoveryStateText == "Canceled · Not started")
    #expect(next.state == .cancelled && next.message == "Not started")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
}

@Test func aToolThatFailsKeepsTheFolderAndShowsItsOutput() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew")
    let result = try await homebrewRun(home, script: "echo 'Error: permission denied' >&2\nexit 1")
    let record = try #require(result.records.first)
    #expect(record.state == .failed)
    #expect(record.message.contains("exited with status 1"))
    #expect(record.toolOutput == "Error: permission denied")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/Homebrew/entry").path))
}

/// Projects can link into the pnpm store (global virtual store), so the store is only pruned, never deleted.
@Test func pnpmStoreIsPrunedWithItsOwnCommandAndTheFolderKept() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/pnpm/store", bytes: 3000)
    try makeFolder(home, "Library/Caches/pnpm", bytes: 500)
    let marker = home.appendingPathComponent("ran")
    let pnpm = try fakeTool(home, "echo \"$@\" > '\(marker.path)'")
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discover(fixture: home, locateTool: { $0.arguments.first == "store" ? pnpm : nil })
    let store = try #require(found.first { $0.url.lastPathComponent == "store" })
    #expect(store.ruleID == "pnpm-store")
    #expect(store.action == .tool)
    #expect(catalog.rule("pnpm-store")?.tool?.commandLine == "pnpm store prune")
    #expect(catalog.rule("pnpm-store")?.tool?.deletesLocationAfter == false)
    // pnpm's metadata cache holds no packages projects link to; deleting it stays a plain delete.
    let metadata = try #require(found.first { $0.url.path.hasSuffix("Library/Caches/pnpm") })
    #expect(metadata.ruleID == "pnpm-cache" && metadata.action == .delete)

    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: FixtureVolume().read, trash: TrashNeverUsed())
    let result = await run.execute(CatalogApproval(candidates: [store], dryRun: false))
    #expect(result.records.first?.state == .succeeded)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "store prune\n")
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/pnpm/store").path))
}

/// Tools installed as `#!/usr/bin/env node` scripts need their own folder on PATH to find node.
@Test func aToolRunsWithItsOwnFolderOnThePath() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFolder(home, "Library/Caches/Homebrew")
    let marker = home.appendingPathComponent("path")
    let result = try await homebrewRun(home, script: "echo \"$PATH\" > '\(marker.path)'")
    #expect(result.records.first?.state == .succeeded)
    let path = try String(contentsOf: marker, encoding: .utf8)
    #expect(path.hasPrefix(home.appendingPathComponent("tools").path + ":"))
    #expect(path.contains("/usr/bin"))
}

/// #545: Results names each DerivedData folder by its project. Xcode names the folder `<project>-<28 lowercase letters>`;
/// only that suffix goes, so a hyphen in the project’s own name stays and a folder without it keeps its name (never the rule’s title).
@Test func eachDerivedDataFolderIsNamedAfterItsProject() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let derived = "Library/Developer/Xcode/DerivedData/"
    let hash = "abcdefghijklmnopqrstuvwxyzab"
    let folders = ["MyApp-" + hash: "MyApp", "My-App-" + hash: "My-App", "ModuleCache.noindex": "ModuleCache.noindex",
                   "Short-abcdefghijklmnop": "Short-abcdefghijklmnop", "Upper-ABCDEFGHIJKLMNOPQRSTUVWXYZAB": "Upper-ABCDEFGHIJKLMNOPQRSTUVWXYZAB",
                   "-" + hash: "-" + hash]
    for folder in folders.keys { try makeFolder(home, derived + folder) }
    let found = Catalog(rules: fixtureRules).discover(fixture: home).filter { $0.ruleID == "xcode-derived-data" }
    #expect(Dictionary(uniqueKeysWithValues: found.map { ($0.url.lastPathComponent, $0.itemName ?? "(no name)") }) == folders)
}
