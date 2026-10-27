import Foundation
import Darwin

public enum ToolPreviewError: Error { case unavailable, timeout, outputLimit, failed, invalidOutput }
/// Synchronous blocking system boundary. Call from a bounded background worker, never MainActor.
public enum BoundedTool {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval = 5, outputLimit: Int = 65_536, environment: [String: String]? = nil) throws -> String {
        let (status, output) = try launch(executable: executable, arguments: arguments, timeout: timeout, outputLimit: outputLimit, keepTail: false, environment: environment)
        guard status == 0 else { throw ToolPreviewError.failed }
        guard let output = String(data: output, encoding: .utf8) else { throw ToolPreviewError.invalidOutput }
        return output
    }

    /// For tool actions: returns the exit status and the last `outputLimit` bytes of combined output,
    /// so a long run is never killed for printing a lot. A timeout still stops it and throws, with the output so far.
    /// Minimal, predictable environment for every tool CacheDrop runs.
    public static let defaultEnvironment: [String: String] = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "C", "LC_ALL": "C", "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_BOOTSNAP": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_AUTOREMOVE": "1", "HOMEBREW_NO_SUDO": "1"]

    public static func capture(executable: URL, arguments: [String], timeout: TimeInterval, outputLimit: Int = 16_384, environment: [String: String]? = nil) throws -> (status: Int32, output: String) {
        let (status, output) = try launch(executable: executable, arguments: arguments, timeout: timeout, outputLimit: outputLimit, keepTail: true, environment: environment)
        return (status, String(decoding: output, as: UTF8.self))
    }

    /// How long a stopped tool and everything it started get to exit after SIGTERM before SIGKILL.
    static let stopGrace: TimeInterval = 2

    private static func launch(executable: URL, arguments: [String], timeout: TimeInterval, outputLimit: Int, keepTail: Bool, environment: [String: String]?) throws -> (Int32, Data) {
        guard executable.isFileURL, executable.path.hasPrefix("/"), timeout > 0, outputLimit > 0,
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw ToolPreviewError.unavailable }
        let tool = try ToolGroup(executable: executable.path, arguments: arguments, environment: environment ?? defaultEnvironment)
        var finished = false
        // Only a run that didn't finish (timeout, output limit, read error) is stopped; the read end closes either way,
        // so nothing waits on a pipe something the tool started still holds.
        defer { if !finished { tool.stop() }; close(tool.output) }
        let descriptor = tool.output
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard keepTail || data.count + count <= outputLimit else { throw ToolPreviewError.outputLimit }
                data.append(contentsOf: buffer.prefix(count))
                if data.count > outputLimit { data.removeFirst(data.count - outputLimit) }
            } else if count == 0 && tool.reap() { break }
            else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK { throw ToolPreviewError.failed }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw keepTail ? ToolTimeout(output: String(decoding: data, as: UTF8.self)) : ToolPreviewError.timeout }
            if count <= 0 { usleep(5_000) }
        }
        finished = true
        return (tool.status ?? -1, data)
    }
}

/// One tool run, started with `posix_spawn` as the leader of its own process group, so stopping it
/// reaches everything it started (shell children, `brew`'s subprocesses) unless they leave the group themselves.
/// Its combined stdout and stderr arrive on `output`, a non-blocking read end the caller closes.
private final class ToolGroup {
    let pid: pid_t
    let output: Int32
    /// The exit code, or the signal that ended it, once reaped (the same value `Process.terminationStatus` gives).
    private(set) var status: Int32?

    init(executable: String, arguments: [String], environment: [String: String]) throws {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { throw ToolPreviewError.failed }
        // Close-on-exec, so a tool another thread starts at the same time never inherits this pipe and holds it open.
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        defer { close(fds[1]) }
        guard fcntl(fds[0], F_SETFL, O_NONBLOCK) != -1 else { close(fds[0]); throw ToolPreviewError.failed }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Own process group (pgid = pid); only stdin/stdout/stderr are inherited; default signal handling and an empty mask.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all); sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setsigmask(&attributes, &none)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        guard result == 0 else { close(fds[0]); throw result == ENOENT || result == EACCES ? ToolPreviewError.unavailable : ToolPreviewError.failed }
        self.pid = pid
        self.output = fds[0]
    }

    /// Collects the leader's exit status if it has exited; true once it has.
    @discardableResult func reap() -> Bool {
        guard status == nil else { return true }
        var raw: Int32 = 0
        guard waitpid(pid, &raw, WNOHANG) == pid else { return false }
        let signal = raw & 0x7f
        status = signal == 0 ? (raw >> 8) & 0xff : signal
        return true
    }

    /// Whether anything is still running in the tool's process group.
    private var groupAlive: Bool { kill(-pid, 0) == 0 || errno != ESRCH }

    /// Stops the whole group: SIGTERM, up to `stopGrace` for everything to exit, then SIGKILL.
    func stop() {
        guard !reap() || groupAlive else { return }
        kill(-pid, SIGTERM)
        let deadline = ProcessInfo.processInfo.systemUptime + BoundedTool.stopGrace
        while ProcessInfo.processInfo.systemUptime < deadline {
            reap()
            if status != nil && !groupAlive { return }
            usleep(10_000)
        }
        kill(-pid, SIGKILL)
        if status == nil { var raw: Int32 = 0; _ = waitpid(pid, &raw, 0); status = raw & 0x7f }
    }
}

/// A tool action stopped at its time limit, with what it printed until then.
public struct ToolTimeout: Error { public let output: String }
