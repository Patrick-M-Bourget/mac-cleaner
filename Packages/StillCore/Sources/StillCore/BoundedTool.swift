import Foundation
import Darwin

public enum ToolPreviewError: Error { case unavailable, timeout, outputLimit, failed, invalidOutput }
/// Synchronous blocking system boundary. Call from a bounded background worker, never MainActor.
public enum BoundedTool {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval = 5, outputLimit: Int = 65_536, environment: [String: String]? = nil) throws -> String {
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
                guard data.count + count <= outputLimit else { throw ToolPreviewError.outputLimit }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 && !process.isRunning { break }
            else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK { throw ToolPreviewError.failed }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ToolPreviewError.timeout }
            if count <= 0 { usleep(5_000) }
        }
        guard process.terminationStatus == 0 else { throw ToolPreviewError.failed }
        guard let output = String(data: data, encoding: .utf8) else { throw ToolPreviewError.invalidOutput }
        return output
    }
}
