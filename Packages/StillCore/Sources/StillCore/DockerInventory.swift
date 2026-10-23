import Foundation

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
    public static func inspectSelected(executable: URL) throws -> String {
        guard executable.isFileURL, executable.lastPathComponent == "docker", FileManager.default.isExecutableFile(atPath: executable.path) else { throw ToolPreviewError.unavailable }
        return "CLI selected; runtime ownership, daemon access and version are unqualified. No command was run. Docker Desktop can show its configured disk image and storage usage."
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
