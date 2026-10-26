import Foundation
import Darwin

public struct DockerStorageCategory: Sendable {
    public let name: String
    public let total: Int
    public let active: Int
    public let daemonSize: String?
    public let daemonReclaimable: String?
    public var persistentData: Bool { name == "Local Volumes" }
}
public struct DockerInventory: Sendable {
    public let version: String
    public let categories: [DockerStorageCategory]
    public let runtimeQualified: Bool
    /// Daemon metrics cannot establish host disk-image allocation.
    public let hostAllocatedBytes: Int64? = nil
    public static func parseRuntime(clientVersion: String, serverVersion: String, output: String) throws -> DockerInventory {
        let fixture = try parseFixture(version: "fixture-only-1", output: output)
        guard fixture.categories.count == 4, fixture.categories.allSatisfy({ category in
            [category.daemonSize, category.daemonReclaimable].compactMap { $0 }.allSatisfy { value in
                value.utf8.count <= 80 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789.BkMGTPEi %()-").contains($0) }
            }
        }) else { throw ToolPreviewError.invalidOutput }
        return .init(version: "CLI \(clientVersion) / Engine \(serverVersion)", categories: fixture.categories, runtimeQualified: false)
    }
    public static func parseFixture(version: String, output: String) throws -> DockerInventory {
        guard version == "fixture-only-1" else { throw ToolPreviewError.invalidOutput }
        struct Row: Decodable {
            let category: String; let total: String; let active: String; let size: String; let reclaimable: String
            enum CodingKeys: String, CodingKey { case category = "Type", total = "TotalCount", active = "Active", size = "Size", reclaimable = "Reclaimable" }
        }
        let rows = try output.split(separator: "\n").map { try JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
        guard !rows.isEmpty, rows.count <= 4, Set(rows.map(\.category)).count == rows.count else { throw ToolPreviewError.invalidOutput }
        let categories = try rows.map { row -> DockerStorageCategory in
            guard ["Images", "Containers", "Local Volumes", "Build Cache"].contains(row.category), let total = Int(row.total), let active = Int(row.active), total >= 0, active >= 0, active <= total else { throw ToolPreviewError.invalidOutput }
            return .init(name: row.category, total: total, active: active, daemonSize: ["N/A", ""].contains(row.size) ? nil : row.size, daemonReclaimable: ["N/A", ""].contains(row.reclaimable) ? nil : row.reclaimable)
        }
        return .init(version: version, categories: categories, runtimeQualified: false)
    }
}

public struct DockerDiskImage: Sendable {
    public let url: URL
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?
    public let virtualCapacityBytes: Int64? = nil
    public let ownershipVerified = false
    public static func readSelected(_ url: URL) throws -> DockerDiskImage {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ToolPreviewError.unavailable }
        return .init(url: url, logicalBytes: values.fileSize.map(Int64.init), allocatedBytes: values.totalFileAllocatedSize.map(Int64.init))
    }
}

public enum DockerInspector {
    public enum State: String, Sendable { case observed, unsupportedCLI, invalidEndpoint, unavailable, denied, timeout, invalidOutput }
    public struct Observation: Sendable {
        public let state: State
        public let inventory: DockerInventory?
        public let guidance: String
    }
    /// Runs a private copy of the selected CLI against an explicit local socket only.
    /// Never resolves a default context, reads personal configuration or starts Docker.
    public static func inspectSelected(executable: URL, socket: URL) -> Observation {
        var info = stat()
        guard executable.isFileURL else {
            return .init(state: .unsupportedCLI, inventory: nil, guidance: "Choose a local Docker CLI file. Nothing was executed.")
        }
        let descriptor = open(executable.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            return .init(state: .unsupportedCLI, inventory: nil, guidance: "Selected CLI is unavailable or a symbolic link. Choose the actual Docker CLI binary; nothing was executed.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size <= 128 * 1024 * 1024 else {
            return .init(state: .unsupportedCLI, inventory: nil, guidance: "Choose a regular Docker CLI file. Nothing was executed.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillDockerInspection-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { return .init(state: .unavailable, inventory: nil, guidance: "Private inspection workspace unavailable. Nothing was executed.") }
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = root.appendingPathComponent("docker")
        var copied = 0
        do {
            FileManager.default.createFile(atPath: snapshot.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let writer = try FileHandle(forWritingTo: snapshot)
            defer { try? writer.close() }
            while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
                copied += data.count
                guard copied <= 128 * 1024 * 1024 else { throw ToolPreviewError.outputLimit }
                try writer.write(contentsOf: data)
            }
        } catch { return .init(state: .unsupportedCLI, inventory: nil, guidance: "Selected CLI could not be copied. Nothing was executed.") }
        guard socket.isFileURL, socket.path.hasPrefix("/"), socket.path.utf8.count < 104,
              !socket.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              socket.path == socket.standardizedFileURL.path, socket.path == socket.resolvingSymlinksInPath().path,
              lstat(socket.path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK else {
            return .init(state: .invalidEndpoint, inventory: nil, guidance: "Enter an existing local Unix socket path without aliases or symbolic links. Still never connects to a default or remote endpoint.")
        }
        guard access(socket.path, R_OK | W_OK) == 0 else {
            return .init(state: .denied, inventory: nil, guidance: "Access to the selected socket is denied. Review its owner and access in Docker; Still does not elevate privileges or change permissions.")
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: snapshot.path)
            return try inspectRuntime(executable: snapshot, socket: socket, workspace: root)
        } catch ToolPreviewError.timeout {
            return .init(state: .timeout, inventory: nil, guidance: "Docker did not finish within the inspection time limit. Check the selected local runtime and try again explicitly.")
        } catch ToolPreviewError.invalidOutput {
            return .init(state: .invalidOutput, inventory: nil, guidance: "Unrecognized report format; no usage estimate was inferred.")
        } catch {
            return .init(state: .unavailable, inventory: nil, guidance: "The selected local daemon or CLI is unavailable. Still will not install Docker, start it, or request elevated access.")
        }
    }
    static func inspectRuntime(executable: URL, socket: URL, workspace: URL) throws -> Observation {
        let config = workspace.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": workspace.path, "TMPDIR": workspace.path, "LANG": "C", "LC_ALL": "C", "DOCKER_CONFIG": config.path]
        let prefix = ["--config", config.path, "--host", "unix://" + socket.path]
        let version = try BoundedTool.run(executable: executable, arguments: prefix + ["version", "--format", "{{json .}}"], environment: environment)
        struct Version: Decodable {
            struct Component: Decodable { let Version: String }
            let Client: Component
            let Server: Component
        }
        guard let versions = try? JSONDecoder().decode(Version.self, from: Data(version.utf8)) else { throw ToolPreviewError.invalidOutput }
        let output = try BoundedTool.run(executable: executable, arguments: prefix + ["system", "df", "--format", "json"], environment: environment)
        let inventory = try DockerInventory.parseRuntime(clientVersion: versions.Client.Version, serverVersion: versions.Server.Version, output: output)
        return .init(state: .observed, inventory: inventory, guidance: "Read-only observation of the selected local daemon. \(inventory.version). Host allocation and ownership remain unknown.")
    }
    static func inspectFixture(executable: URL) throws -> DockerInventory {
        let root = executable.deletingLastPathComponent()
        guard root.lastPathComponent.hasPrefix("StillDockerProbe-"), executable.lastPathComponent == "docker" else { throw ToolPreviewError.unavailable }
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": root.path, "DOCKER_CONFIG": root.appendingPathComponent("config").path, "LANG": "C", "LC_ALL": "C"]
        let version = try BoundedTool.run(executable: executable, arguments: ["--version"], environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version == "Docker version fixture-only-1" else { throw ToolPreviewError.invalidOutput }
        let output = try BoundedTool.run(executable: executable, arguments: ["--host", "unix://" + root.appendingPathComponent("daemon.sock").path, "system", "df", "--format", "json"], environment: environment)
        return try DockerInventory.parseFixture(version: "fixture-only-1", output: output)
    }
}
