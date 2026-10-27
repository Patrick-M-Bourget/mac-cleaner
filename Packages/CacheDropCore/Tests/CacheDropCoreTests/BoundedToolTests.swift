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
@Test func aToolThatFinishesLeavesWhatItDetachedAlone() throws {
    let marker = uniqueSleep()
    let tool = try treeTool("sleep \"$1\" >/dev/null 2>&1 &\necho done")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let result = try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 5)
    let left = survivors(marker)
    left.forEach { kill($0, SIGKILL) }
    #expect(result.status == 0)
    #expect(result.output == "done\n")
    #expect(left.count == 1)
}

/// When a test cancelled, so a stop is timed from the cancel rather than from a start a busy test run may delay.
final class CancelTime: @unchecked Sendable {
    private let lock = NSLock()
    private var at: TimeInterval = .infinity
    func mark() { lock.lock(); at = ProcessInfo.processInfo.systemUptime; lock.unlock() }
    var value: TimeInterval { lock.lock(); defer { lock.unlock() }; return at }
}

@Test func aCancelledToolIsStoppedWithEveryProcessItStartedAndReturnsItsOutputSoFar() throws {
    let marker = uniqueSleep()
    let tool = try treeTool("echo started\nsleep \"$1\" &\nsleep \"$1\"")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation(), cancelledAt = CancelTime()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { cancelledAt.mark(); cancellation.cancel() }
    let error = #expect(throws: ToolCancelled.self) { try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 60, cancellation: cancellation) }
    let sinceCancel = ProcessInfo.processInfo.systemUptime - cancelledAt.value
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
    let tool = try treeTool("p=$$\n( while :; do case \"$(ps -o stat= -p $p)\" in Z*) break;; esac; sleep 0.01; done; touch '\(exited.path)'; sleep \"$1\" ) &\necho done\nexit 0")
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    let cancellation = CleanupCancellation()
    DispatchQueue.global().async { if waitForFile(exited) { cancellation.cancel() } }
    let result = try BoundedTool.capture(executable: tool, arguments: [marker], timeout: 20, cancellation: cancellation)
    let left = survivorsAfterSettling(marker)
    left.forEach { kill($0, SIGKILL) }
    #expect(cancellation.isCancelled)
    #expect(result.status == 0)
    #expect(result.output == "done\n")
    #expect(left.isEmpty)
}
