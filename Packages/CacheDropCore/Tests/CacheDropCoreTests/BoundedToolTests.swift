import Foundation
import Testing
@testable import CacheDropCore

/// A stand-in tool: a shell script whose children all carry `marker` on their command line.
private func treeTool(_ body: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bounded-tool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = folder.appendingPathComponent("tool.sh")
    try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

/// A sleep length unique to this test run, so its processes can be found by their argv.
func uniqueSleep() -> String { "29.\(Int.random(in: 100_000...999_999))" }

func survivors(_ marker: String) -> [pid_t] {
    (UserProcesses.pids() ?? []).filter { UserProcesses.arguments($0)?.contains(marker) == true }
}

/// Give launchd a moment to reap what the tool left behind before counting survivors.
func survivorsAfterSettling(_ marker: String) -> [pid_t] {
    for _ in 0..<20 where !survivors(marker).isEmpty { usleep(50_000) }
    return survivors(marker)
}

@Test func aTimedOutToolIsStoppedWithEveryProcessItStarted() throws {
    let marker = uniqueSleep()
    let tool = try treeTool("echo started\nsleep \"$1\" &\nsleep \"$1\"")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let started = ProcessInfo.processInfo.systemUptime
    #expect(throws: ToolTimeout.self) { try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 0.5) }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let left = survivorsAfterSettling(marker)
    left.forEach { kill($0, SIGKILL) }
    #expect(elapsed < 0.5 + 2 + 1)
    #expect(left.isEmpty)
}

@Test func aToolThatIgnoresTheStopRequestIsKilledAfterTheGracePeriod() throws {
    let marker = uniqueSleep()
    let tool = try treeTool("trap '' TERM\nsleep \"$1\" &\nwhile :; do sleep 0.1; done")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let started = ProcessInfo.processInfo.systemUptime
    #expect(throws: ToolPreviewError.timeout) { try BoundedTool.run(executable: tool, arguments: [marker], timeout: 0.5) }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let left = survivorsAfterSettling(marker)
    left.forEach { kill($0, SIGKILL) }
    #expect(elapsed < 0.5 + 2 + 1)
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
private func isRunning(_ pid: pid_t) -> Bool {
    var details = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size && details.pbi_status != SZOMB
}

@Test func aCancelledToolIsStoppedWithEveryProcessItStartedAndReturnsItsOutputSoFar() throws {
    let marker = uniqueSleep()
    let folder = try treeTool("true").deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    let running = folder.appendingPathComponent("running")
    let tool = try treeTool("echo started\ntouch '\(running.path)'\nsleep \"$1\" &\nsleep \"$1\"")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation(), cancelledAt = CancelTime()
    // Cancel once the tool has printed and is running, never after a fixed delay a slow machine may outlast.
    let watcher = CancelWhenFileAppears(running, cancel: cancellation, at: cancelledAt)
    defer { watcher.stop() }
    let error = #expect(throws: ToolCancelled.self) { try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 60, cancellation: cancellation) }
    let sinceCancel = cancelledAt.elapsed
    let left = survivorsAfterSettling(marker)
    left.forEach { kill($0, SIGKILL) }
    #expect(sinceCancel < BoundedTool.stopGrace + 1)
    #expect(left.isEmpty)
    #expect(error?.output == "started\n")
    #expect(error?.started == true)
}

@Test func aToolCancelledBeforeItStartsIsNeverLaunched() throws {
    let folder = try treeTool("true").deletingLastPathComponent()
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
    let marker = uniqueSleep()
    let folder = try treeTool("true").deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    let exited = folder.appendingPathComponent("exited")
    // The child writes `exited` once its parent, the tool, is a zombie waiting to be reaped.
    let tool = try treeTool("p=$$\n( while :; do case \"$(ps -o stat= -p $p)\" in Z*|\"\") break;; esac; sleep 0.01; done; touch '\(exited.path)'; sleep \"$1\" ) &\necho done\nexit 0")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation()
    let watcher = CancelWhenFileAppears(exited, cancel: cancellation)
    defer { watcher.stop() }
    let result = try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 20, cancellation: cancellation)
    let left = survivorsAfterSettling(marker)
    left.forEach { kill($0, SIGKILL) }
    #expect(cancellation.isCancelled)
    #expect(result.status == 0)
    #expect(result.output == "done\n")
    #expect(left.isEmpty)
}
