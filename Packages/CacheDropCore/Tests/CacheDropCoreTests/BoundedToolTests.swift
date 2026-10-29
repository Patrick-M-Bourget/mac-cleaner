import Foundation
import Testing
@testable import CacheDropCore

/// A new empty temp folder, for files a stand-in tool writes to say it reached a point.
private func scratchFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bounded-tool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
/// A stand-in tool: a shell script whose children all carry `marker` on their command line.
private func treeTool(_ body: String) throws -> URL {
    let folder = try scratchFolder()
    let script = folder.appendingPathComponent("tool.sh")
    try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

/// The time limit for a test that stops a stand-in tool once it has started a child. A loaded Mac can take more than
/// half a second to spawn the stand-in's shell and its child (#337); a shorter limit stops the stand-in before it has one,
/// and the test fails without having tested stopping it.
let childStartedLimit: TimeInterval = 2

/// A sleep length unique to this test run, so its processes can be found by their argv.
func uniqueSleep() -> String { "29.\(Int.random(in: 100_000...999_999))" }

func survivors(_ marker: String) -> [pid_t] {
    (UserProcesses.pids() ?? []).filter { UserProcesses.arguments($0)?.contains(marker) == true }
}

/// Give launchd a moment to reap what the tool left behind before counting survivors.
/// Only for cleaning up: an assertion that nothing is left checks known pids (`stillRunning`), since a just-started
/// process's argv can't be read for a moment and a search can miss it (#191, #210).
func survivorsAfterSettling(_ marker: String) -> [pid_t] {
    for _ in 0..<20 where !survivors(marker).isEmpty { usleep(50_000) }
    return survivors(marker)
}

/// A shell line for a stand-in tool that appends a pid (`$$`, the shell's own, or `$!`, its last background job) to `file`.
func recordPid(_ which: String, in file: URL) -> String { "echo \(which) >> '\(file.path)'" }
/// The pids a stand-in tool recorded with `recordPid`.
func recordedPids(_ file: URL) -> [pid_t] {
    ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { pid_t($0) }
}
/// Which of `pids` still run after giving them a moment to exit.
func stillRunning(_ pids: [pid_t]) -> [pid_t] {
    for _ in 0..<20 where pids.contains(where: isRunning) { usleep(50_000) }
    return pids.filter(isRunning)
}

@Test func aTimedOutToolIsStoppedWithEveryProcessItStarted() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let pids = folder.appendingPathComponent("pids")
    let tool = try treeTool("echo started\n\(recordPid("$$", in: pids))\nsleep \"$1\" &\n\(recordPid("$!", in: pids))\nexec sleep \"$1\"")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let started = ProcessInfo.processInfo.systemUptime
    #expect(throws: ToolTimeout.self) { try BoundedTool.capture(executable: tool, arguments: [uniqueSleep()], timeout: childStartedLimit) }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let left = stillRunning(recordedPids(pids))
    left.forEach { kill($0, SIGKILL) }
    #expect(elapsed < childStartedLimit + BoundedTool.stopGrace + 1)
    #expect(recordedPids(pids).count == 2, "The stand-in starts its child before the time limit")
    #expect(left.isEmpty)
}

@Test func aToolThatIgnoresTheStopRequestIsKilledAfterTheGracePeriod() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let pids = folder.appendingPathComponent("pids")
    let tool = try treeTool("trap '' TERM\n\(recordPid("$$", in: pids))\nsleep \"$1\" &\n\(recordPid("$!", in: pids))\nwhile :; do sleep 0.1; done")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let started = ProcessInfo.processInfo.systemUptime
    #expect(throws: ToolPreviewError.timeout) { try BoundedTool.run(executable: tool, arguments: [uniqueSleep()], timeout: childStartedLimit) }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let left = stillRunning(recordedPids(pids))
    left.forEach { kill($0, SIGKILL) }
    #expect(elapsed < childStartedLimit + BoundedTool.stopGrace + 1)
    #expect(recordedPids(pids).count == 2, "The stand-in starts its child before the time limit")
    #expect(left.isEmpty)
}

@Test func aFinishedToolReturnsItsStatusAndBothOutputStreams() throws {
    let tool = try treeTool("echo out\necho err >&2\nprintf '%s' \"$HOME|$LANG\"\nexit 3")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let result = try BoundedTool.capture(executable: tool, arguments: [], timeout: 5, environment: ["HOME": "/fixture", "LANG": "C"])
    #expect(result.status == 3)
    #expect(result.output == "out\nerr\n/fixture|C")
    #expect(try BoundedTool.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["a b", "c"], timeout: 5) == "a b c\n")
}

/// Only a timeout (or an output-limit stop) ends the tree; a run that finished is left as it was before.
/// The tool prints the pid of what it detached, so the test checks that process rather than searching argv for the
/// marker: mid-exec, a process's argv can't be read for a moment, and a search then found nothing (#191).
@Test func aToolThatFinishesLeavesWhatItDetachedAlone() throws {
    let marker = uniqueSleep()
    let tool = try treeTool("sleep \"$1\" >/dev/null 2>&1 &\necho $!")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let result = try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 5)
    let detached = try #require(pid_t(result.output.trimmingCharacters(in: .whitespacesAndNewlines)))
    let running = isRunning(detached)
    kill(detached, SIGKILL)
    #expect(result.status == 0)
    #expect(running)
}

/// Alive and not a zombie: a process the stop had signalled is gone or dying by the time `capture` returns.
func isRunning(_ pid: pid_t) -> Bool {
    var details = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size && details.pbi_status != SZOMB
}

@Test func aCancelledToolIsStoppedWithEveryProcessItStartedAndReturnsItsOutputSoFar() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let running = folder.appendingPathComponent("running"), pids = folder.appendingPathComponent("pids")
    let tool = try treeTool("echo started\n\(recordPid("$$", in: pids))\nsleep \"$1\" &\n\(recordPid("$!", in: pids))\ntouch '\(running.path)'\nexec sleep \"$1\"")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation(), cancelledAt = CancelTime()
    // Cancel once the tool has printed and is running, never after a fixed delay a slow machine may outlast.
    let watcher = CancelWhenFileAppears(running, cancel: cancellation, at: cancelledAt)
    defer { watcher.stop() }
    let error = #expect(throws: ToolCancelled.self) { try BoundedTool.capture(executable: tool, arguments: [uniqueSleep()], timeout: 60, cancellation: cancellation) }
    let sinceCancel = cancelledAt.elapsed
    let left = stillRunning(recordedPids(pids))
    left.forEach { kill($0, SIGKILL) }
    #expect(sinceCancel < BoundedTool.stopGrace + 1)
    #expect(recordedPids(pids).count == 2)
    #expect(left.isEmpty)
    #expect(error?.output == "started\n")
    #expect(error?.started == true)
}

@Test func aToolCancelledBeforeItStartsIsNeverLaunched() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let marker = folder.appendingPathComponent("ran")
    let tool = try treeTool("touch '\(marker.path)'")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation()
    cancellation.cancel()
    let error = #expect(throws: ToolCancelled.self) { try BoundedTool.capture(executable: tool, arguments: [], timeout: 5, cancellation: cancellation) }
    #expect(error?.started == false)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

/// The tool exited but something it started still holds the output open, so there's no EOF yet. A cancel then
/// reports the tool's own result, not a stop, and still ends what it left behind.
@Test func aCancelAfterTheToolExitedReturnsItsOwnResult() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let exited = folder.appendingPathComponent("exited"), pids = folder.appendingPathComponent("pids")
    // The child writes `exited` once its parent, the tool, is a zombie waiting to be reaped, then becomes the sleep.
    let tool = try treeTool("p=$$\n( while :; do case \"$(ps -o stat= -p $p)\" in Z*|\"\") break;; esac; sleep 0.01; done; touch '\(exited.path)'; exec sleep \"$1\" ) &\n\(recordPid("$!", in: pids))\necho done\nexit 0")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation()
    let watcher = CancelWhenFileAppears(exited, cancel: cancellation)
    defer { watcher.stop() }
    let result = try BoundedTool.capture(executable: tool, arguments: [uniqueSleep()], timeout: 20, cancellation: cancellation)
    let left = stillRunning(recordedPids(pids))
    left.forEach { kill($0, SIGKILL) }
    #expect(cancellation.isCancelled)
    #expect(recordedPids(pids).count == 1)
    #expect(result.status == 0)
    #expect(result.output == "done\n")
    #expect(left.isEmpty)
}
