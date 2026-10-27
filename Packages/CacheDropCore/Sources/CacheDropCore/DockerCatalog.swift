import Foundation
import Darwin

/// Docker (#112). Each prune kind is its own rule, run through the tool action. Docker must be running,
/// so the rules have no owner to close. Volumes are never pruned: they hold databases and app data.
/// Sizes are the daemon's own "reclaimable" numbers from `docker system df`, shown as estimates.
extension BuiltInCatalog {
    static let dockerExecutables = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", NSHomeDirectory() + "/.docker/bin/docker"]
    /// `effect` says what the command does; the consequence starts with the exact command, from `arguments`, so the two never drift.
    private static func docker(_ kind: DockerPruneKind, id: String, title: String, detail: String, effect: String, regen: RegenClass, arguments: [String]) -> CleanupRule {
        let tool = ToolCommand(executables: dockerExecutables, arguments: arguments, timeout: 600)
        // `.docker` is the CLI's own folder; it anchors the rule in the home folder. The command never touches it.
        return CleanupRule(id: id, category: .developer, title: title, detail: detail, consequence: "Runs `\(tool.commandLine)`, " + effect + " Docker must be running.",
                           regen: regen, action: .tool, locations: [".docker"], owner: nil, tool: tool, items: .docker(kind))
    }
    static let dockerRules = [
        docker(.images, id: "docker-images", title: "Docker images",
               detail: "Images no container uses. The size is Docker’s own estimate.",
               effect: "which permanently removes every image no container uses. Docker downloads or builds them again when needed.",
               regen: .cache, arguments: ["image", "prune", "-a", "-f"]),
        docker(.buildCache, id: "docker-build-cache", title: "Docker build cache",
               detail: "Layers Docker kept to speed up builds. The size is Docker’s own estimate.",
               effect: "which permanently removes all unused build cache. The next build may take longer.",
               regen: .build, arguments: ["builder", "prune", "-a", "-f"]),
        docker(.stoppedContainers, id: "docker-containers", title: "Stopped Docker containers",
               detail: "Containers that aren’t running. The size is Docker’s own estimate.",
               effect: "which permanently removes stopped containers and any changes made inside them. Running containers and volumes are not touched.",
               regen: .build, arguments: ["container", "prune", "-f"]),
    ]
}

/// The kinds of Docker data Still offers to prune, by their `Type` in `docker system df`. Volumes are never one.
public enum DockerPruneKind: String, Sendable, Equatable {
    case images = "Images", buildCache = "Build Cache", stoppedContainers = "Containers"
}

/// One row of `docker system df`.
public struct DockerStorageCategory: Sendable, Equatable {
    public let name: String
    public let total: Int
    public let active: Int
    /// What Docker says it could reclaim; nil when it reports "N/A".
    public let reclaimableBytes: Int64?
}

public enum DockerDiskUsage {
    public static let arguments = ["system", "df", "--format", "json"]
    /// A short limit: discovery waits for it, and a daemon that doesn't answer is shown as not running.
    public static let timeout: TimeInterval = 15

    /// Parses `docker system df --format json`: one JSON object per line. Anything unrecognized throws.
    public static func parse(_ output: String) throws -> [DockerStorageCategory] {
        struct Row: Decodable {
            let category: String; let total: String; let active: String; let reclaimable: String
            enum CodingKeys: String, CodingKey { case category = "Type", total = "TotalCount", active = "Active", reclaimable = "Reclaimable" }
        }
        let lines = output.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard !lines.isEmpty, lines.count <= 8 else { throw ToolPreviewError.invalidOutput }
        let rows = try lines.map { try JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
        guard Set(rows.map(\.category)).count == rows.count else { throw ToolPreviewError.invalidOutput }
        return try rows.map { row in
            guard ["Images", "Containers", "Local Volumes", "Build Cache"].contains(row.category), let total = Int(row.total), let active = Int(row.active),
                  total >= 0, active >= 0, active <= total, row.reclaimable.utf8.count <= 80 else { throw ToolPreviewError.invalidOutput }
            return DockerStorageCategory(name: row.category, total: total, active: active, reclaimableBytes: bytes(row.reclaimable))
        }
    }

    /// Docker's human sizes, such as "2.5GB (62%)", "1.234kB" or "0B": decimal units, binary ones accepted too.
    static func bytes(_ text: String) -> Int64? {
        let size = text.split(separator: " ").first.map(String.init) ?? ""
        guard let split = size.firstIndex(where: { $0.isLetter }), let number = Double(size[..<split]), number >= 0, number.isFinite else { return nil }
        let units: [String: Double] = ["B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "PB": 1e15,
                                       "KiB": 1024, "MiB": 1_048_576, "GiB": 1_073_741_824, "TiB": 1_099_511_627_776]
        guard let unit = units[String(size[split...])], number * unit < 9e18 else { return nil }
        return Int64((number * unit).rounded())
    }

    /// Runs `docker system df` with the tool's own folder first on PATH, as tool actions run.
    static func read(_ docker: URL) -> Result<[DockerStorageCategory], ToolPreviewError> {
        var environment = BoundedTool.defaultEnvironment
        environment["PATH"] = docker.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        do { return .success(try parse(BoundedTool.run(executable: docker, arguments: arguments, timeout: timeout, outputLimit: 65_536, environment: environment))) }
        catch let error as ToolPreviewError { return .failure(error) }
        catch { return .failure(.invalidOutput) }
    }

    /// The notice shown instead of Docker's rows; never a size of 0.
    static func notice(_ error: ToolPreviewError) -> String {
        switch error {
        case .timeout: "Docker didn’t answer within \(Int(timeout)) seconds, so its space isn’t shown. Scan again once Docker is running."
        case .invalidOutput, .outputLimit: "Couldn’t read Docker’s disk usage, so its space isn’t shown."
        case .unavailable, .failed: "Docker isn’t running, so its space isn’t shown. Open Docker, then scan again."
        }
    }
}

extension Catalog {
    /// The candidate for one prune kind: the rule's `.docker` folder, sized by what Docker says it can reclaim.
    /// Nothing is offered for a kind with nothing to reclaim.
    func dockerCandidate(_ kind: DockerPruneKind, at url: URL, rule: CleanupRule, toolURL: URL?, usage: [DockerStorageCategory]) -> Candidate? {
        var info = stat()
        guard let row = usage.first(where: { $0.name == kind.rawValue }), row.total > 0, row.reclaimableBytes != 0,
              lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else { return nil }
        var found = candidate(rule, url, info, logical: row.reclaimableBytes ?? 0, allocated: nil, complete: row.reclaimableBytes != nil, lastUsed: nil, toolURL: toolURL)
        found.sizeIsEstimate = true
        return found
    }
}
