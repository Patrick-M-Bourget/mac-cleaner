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
    public static func capture(executable: URL, arguments: [String], timeout: TimeInterval, outputLimit: Int = 16_384, environment: [String: String]? = nil) throws -> (status: Int32, output: String) {
        let (status, output) = try launch(executable: executable, arguments: arguments, timeout: timeout, outputLimit: outputLimit, keepTail: true, environment: environment)
        return (status, String(decoding: output, as: UTF8.self))
    }

    private static func launch(executable: URL, arguments: [String], timeout: TimeInterval, outputLimit: Int, keepTail: Bool, environment: [String: String]?) throws -> (Int32, Data) {
        guard executable.isFileURL, executable.path.hasPrefix("/"), timeout > 0, outputLimit > 0,
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw ToolPreviewError.unavailable }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        process.environment = environment ?? ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "C", "LC_ALL": "C", "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_BOOTSNAP": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_AUTOREMOVE": "1", "HOMEBREW_NO_SUDO": "1"]
        try process.run()
        try? pipe.fileHandleForWriting.close()
        defer {
            if process.isRunning { process.terminate(); kill(process.processIdentifier, SIGKILL) }
            try? pipe.fileHandleForReading.close()
        }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { throw ToolPreviewError.failed }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard keepTail || data.count + count <= outputLimit else { throw ToolPreviewError.outputLimit }
                data.append(contentsOf: buffer.prefix(count))
                if data.count > outputLimit { data.removeFirst(data.count - outputLimit) }
            } else if count == 0 && !process.isRunning { break }
            else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK { throw ToolPreviewError.failed }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw keepTail ? ToolTimeout(output: String(decoding: data, as: UTF8.self)) : ToolPreviewError.timeout }
            if count <= 0 { usleep(5_000) }
        }
        return (process.terminationStatus, data)
    }
}

/// A tool action stopped at its time limit, with what it printed until then.
public struct ToolTimeout: Error { public let output: String }
