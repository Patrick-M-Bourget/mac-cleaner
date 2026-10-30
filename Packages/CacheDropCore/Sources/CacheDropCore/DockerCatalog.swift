import Foundation
import Darwin

/// Docker (#112). Each prune kind is its own rule, run through the tool action. Docker must be running,
/// so the rules have no owner to close. Volumes are never pruned: they hold databases and app data.
/// Sizes are what each prune removes, read from `docker system df` (#407), shown as estimates.
extension BuiltInCatalog {
    static let dockerExecutables = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", NSHomeDirectory() + "/.docker/bin/docker"]
    /// `effect` is the consequence: what the command removes and what stays. The review shows the exact command, from `arguments`, under the files.
    private static func docker(_ kind: DockerPruneKind, id: String, title: String, detail: String, effect: String, regen: RegenClass, arguments: [String]) -> CleanupRule {
        let tool = ToolCommand(executables: dockerExecutables, arguments: arguments, timeout: 600, daemonBacked: true)
        // `.docker` is the CLI's own folder; it anchors the rule in the home folder. The command never touches it.
        return CleanupRule(id: id, category: .developer, title: title, detail: detail, consequence: effect,
                           regen: regen, action: .tool, locations: [".docker"], owner: nil, tool: tool, items: .docker(kind))
    }
    /// Stopped containers come first (#393, Decision 85): `image prune -a` keeps every image a container uses, stopped ones
    /// included, so pruning images first would leave behind an image only a stopped container used. The run follows this order.
    static let dockerRules = [
        docker(.stoppedContainers, id: "docker-containers", title: "Stopped Docker containers",
               detail: "Containers that aren’t running. Size is an estimate.",
               effect: "Stopped containers go with any changes made inside them; running containers and volumes are kept.",
               regen: .build, arguments: ["container", "prune", "-f"]),
        docker(.images, id: "docker-images", title: "Docker images",
               detail: "Images no running container uses. Size is an estimate.",
               effect: "Images no container uses go, and Docker downloads or builds them again when needed.",
               regen: .cache, arguments: ["image", "prune", "-a", "-f"]),
        docker(.buildCache, id: "docker-build-cache", title: "Docker build cache",
               detail: "Layers Docker kept to speed up builds. Size is an estimate.",
               effect: "All unused build cache goes, and Docker rebuilds it on the next build.",
               regen: .build, arguments: ["builder", "prune", "-a", "-f"]),
    ]
}

/// The kinds of Docker data CacheDrop offers to prune, by their `Type` in `docker system df`. Volumes are never one.
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
    /// Everything the kind holds, shared layers counted once; nil when it reports "N/A".
    public let sizeBytes: Int64?
    /// What the kind's prune removes (#407), set by `DockerDiskUsage.read`; nil when it isn't known.
    public internal(set) var prunableBytes: Int64? = nil
}

/// One image in `docker system df -v`.
struct DockerImage: Decodable, Equatable {
    let id: String, repository: String, tag: String, digest: String
    let sizeBytes: Int64?

    enum CodingKeys: String, CodingKey { case id = "ID", repository = "Repository", tag = "Tag", digest = "Digest", size = "Size" }
    init(from decoder: any Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(String.self, forKey: .id); repository = try row.decode(String.self, forKey: .repository)
        tag = try row.decode(String.self, forKey: .tag); digest = try row.decodeIfPresent(String.self, forKey: .digest) ?? ""
        sizeBytes = DockerDiskUsage.bytes(try row.decode(String.self, forKey: .size))
    }

    /// Whether a container naming `name` uses this image: its `repository:tag`, a bare repository meaning `latest`,
    /// `repository@digest`, or its ID, full or at least 12 characters of it, with or without `sha256:`.
    func matches(_ name: String) -> Bool {
        func hex(_ id: String) -> Substring { id.hasPrefix("sha256:") ? id.dropFirst(7) : Substring(id) }
        if name == repository + ":" + tag || (tag == "latest" && name == repository) { return true }
        if let at = name.firstIndex(of: "@") {
            let pinned = name[name.index(after: at)...]
            return name[..<at] == repository && !digest.isEmpty && pinned == digest
        }
        return hex(name).count >= 12 && hex(id).hasPrefix(hex(name))
    }
}

/// What the prunes leave behind, from `docker system df -v --format json`: one JSON object (#407).
struct DockerKept: Equatable {
    /// The images the containers `container prune` leaves use; nil when one of them isn't in the list.
    let imageBytes: Int64?
    /// Build cache Docker marks as shared with an image; it stays while that image does. Nil when a size can't be read.
    let sharedCacheBytes: Int64?

    /// `container prune` removes containers in these states; every other one stays, and so does its image.
    static let prunedStates: Set<String> = ["exited", "created", "dead"]

    /// Anything unrecognized throws.
    init(_ output: String) throws {
        struct Container: Decodable {
            let image: String, state: String
            enum CodingKeys: String, CodingKey { case image = "Image", state = "State" }
        }
        struct CacheRecord: Decodable {
            let shared: String, size: String
            enum CodingKeys: String, CodingKey { case shared = "Shared", size = "Size" }
        }
        struct Report: Decodable {
            let images: [DockerImage], containers: [Container], buildCache: [CacheRecord]?
            enum CodingKeys: String, CodingKey { case images = "Images", containers = "Containers", buildCache = "BuildCache" }
        }
        let report = try JSONDecoder().decode(Report.self, from: Data(output.utf8))
        // By ID, so an image two staying containers use counts once.
        var staying: [String: Int64] = [:], unmatched = false
        for container in report.containers where !Self.prunedStates.contains(container.state) {
            guard let image = report.images.first(where: { $0.matches(container.image) }), let size = image.sizeBytes else { unmatched = true; continue }
            staying[image.id] = size
        }
        imageBytes = unmatched ? nil : staying.values.reduce(0, +)
        let shared = (report.buildCache ?? []).filter { $0.shared == "true" }.map { DockerDiskUsage.bytes($0.size) }
        sharedCacheBytes = shared.contains(nil) ? nil : shared.compactMap { $0 }.reduce(0, +)
    }
}

public enum DockerDiskUsage {
    public static let arguments = ["system", "df", "--format", "json"]
    /// Per image, container and cache record; read only when a container stays after `container prune`, to learn what it keeps.
    static let verboseArguments = ["system", "df", "-v", "--format", "json"]
    /// A short limit: discovery waits for it, and a daemon that doesn't answer is shown as not running.
    public static let timeout: TimeInterval = 15

    /// Parses `docker system df --format json`: one JSON object per line. Anything unrecognized throws.
    public static func parse(_ output: String) throws -> [DockerStorageCategory] {
        struct Row: Decodable {
            let category: String; let total: String; let active: String; let reclaimable: String; let size: String
            enum CodingKeys: String, CodingKey { case category = "Type", total = "TotalCount", active = "Active", reclaimable = "Reclaimable", size = "Size" }
        }
        let lines = output.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard !lines.isEmpty, lines.count <= 8 else { throw ToolPreviewError.invalidOutput }
        let rows = try lines.map { try JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
        guard Set(rows.map(\.category)).count == rows.count else { throw ToolPreviewError.invalidOutput }
        return try rows.map { row in
            guard ["Images", "Containers", "Local Volumes", "Build Cache"].contains(row.category), let total = Int(row.total), let active = Int(row.active),
                  total >= 0, active >= 0, active <= total, row.reclaimable.utf8.count <= 80, row.size.utf8.count <= 80 else { throw ToolPreviewError.invalidOutput }
            return DockerStorageCategory(name: row.category, total: total, active: active, reclaimableBytes: bytes(row.reclaimable), sizeBytes: bytes(row.size))
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

    /// Runs `docker system df` with the tool's own folder first on PATH, as tool actions run, and sets what each kind's prune
    /// removes (#407). Reclaimable leaves out what Docker counts as in use, which the `-a` prunes remove too. With no container
    /// left after `container prune` (Decision 85), every image and the whole build cache go. Otherwise `-v` says what stays:
    /// - images: all but those the staying containers use. Their sizes may share layers, so this can only count too little.
    ///   When a staying container's image isn't in the list, Reclaimable, which also counts too little;
    /// - build cache: all but what Docker marks shared with an image, which stays with it;
    /// - when `-v` can't be read, neither size is known, so it is never read as gone (Decision 45).
    /// Stopped containers are what Reclaimable says.
    static func read(_ docker: URL) -> Result<[DockerStorageCategory], ToolPreviewError> {
        var environment = BoundedTool.defaultEnvironment
        environment["PATH"] = docker.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        func run(_ arguments: [String], outputLimit: Int) throws -> String {
            try BoundedTool.run(executable: docker, arguments: arguments, timeout: timeout, outputLimit: outputLimit, environment: environment)
        }
        var rows: [DockerStorageCategory]
        do { rows = try parse(run(arguments, outputLimit: 65_536)) }
        catch let error as ToolPreviewError { return .failure(error) }
        catch { return .failure(.invalidOutput) }
        // Docker counts running, paused and restarting containers as Active: the ones `container prune` leaves.
        let active = rows.first { $0.name == DockerPruneKind.stoppedContainers.rawValue }?.active ?? 0
        // `-v` lists every image, container and cache record, so it gets a larger limit.
        let staying: Staying = active == 0 ? .nothing
            : (try? DockerKept(run(verboseArguments, outputLimit: 1_048_576))).map(Staying.kept) ?? .unreadable
        for index in rows.indices {
            let row = rows[index]
            switch (DockerPruneKind(rawValue: row.name), staying) {
            case (.buildCache, .nothing), (.images, .nothing): rows[index].prunableBytes = row.sizeBytes
            case (.buildCache, .kept(let kept)):
                rows[index].prunableBytes = row.sizeBytes.flatMap { size in kept.sharedCacheBytes.map { max(0, size - $0) } }
            case (.images, .kept(let kept)):
                // A staying container's image that isn't in the list: Reclaimable, never more.
                rows[index].prunableBytes = kept.imageBytes.map { staying in row.sizeBytes.map { max(0, $0 - staying) } } ?? row.reclaimableBytes
            case (.buildCache, .unreadable), (.images, .unreadable): rows[index].prunableBytes = nil
            case (.stoppedContainers, _), (nil, _): rows[index].prunableBytes = row.reclaimableBytes
            }
        }
        return .success(rows)
    }

    /// What stays after `container prune`: nothing, what `-v` says, or unknown because `-v` couldn't be read.
    private enum Staying { case nothing, kept(DockerKept), unreadable }

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
    /// The review sheet's one note when the run prunes Docker (#411): its space reaches macOS a little after the prune, so
    /// Results' "check again" isn't a surprise. Nil without a Docker item.
    public func dockerReviewNote(for candidates: [Candidate]) -> String? {
        candidates.contains { isDocker($0.ruleID) } ? "Space from Docker reaches macOS up to a minute after it finishes." : nil
    }

    /// Whether `ruleID` names one of Docker's prune rules.
    func isDocker(_ ruleID: String?) -> Bool { ruleID.flatMap(rule)?.isDocker == true }

    /// The candidate for one prune kind: the rule's `.docker` folder, sized by what its prune removes (#407).
    /// Nothing is offered for a kind with nothing to remove.
    func dockerCandidate(_ kind: DockerPruneKind, at url: URL, rule: CleanupRule, toolURL: URL?, usage: [DockerStorageCategory]) -> Candidate? {
        var info = stat()
        guard let row = usage.first(where: { $0.name == kind.rawValue }), row.total > 0 else { return nil }
        let bytes = row.prunableBytes
        guard bytes != 0, lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else { return nil }
        var found = candidate(rule, url, info, logical: bytes ?? 0, allocated: nil, complete: bytes != nil, lastUsed: nil, toolURL: toolURL)
        found.sizeIsEstimate = true
        return found
    }
}
