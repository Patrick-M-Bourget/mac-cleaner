import Foundation
import Darwin

/// Build folders in your projects (#157): rebuildable build output inside folders the user picked, each recognised
/// only next to its project's marker (`node_modules` beside `package.json`). Offered per project, chosen one by one,
/// moved to Trash, never in Smart clean (`choosesItems`).
public enum ProjectBuilds {
    public static let ruleID = "project-builds"
    /// A project changed in this many days is being worked on, so its build folders are kept.
    public static let recentDays = 7

    public static let rule = CleanupRule(id: ruleID, category: .developer, title: "Build folders in your projects",
        detail: "node_modules, .build, target and other build output in folders you picked.",
        consequence: "Moved to Trash. The project rebuilds them on its next install or build; you can restore them from the Trash in Finder.",
        regen: .build, action: .trash, locations: [], owner: nil, fromPickedFolders: true)

    /// Each build folder kind and the files, any one of which marks its project. `*.xcodeproj` matches by extension.
    static let kinds: [(folder: String, markers: [String])] = [
        ("node_modules", ["package.json"]), (".next", ["package.json"]), ("dist", ["package.json"]),
        (".build", ["Package.swift"]),
        ("target", ["Cargo.toml", "pom.xml"]),
        ("build", ["build.gradle", "build.gradle.kts"]),
        (".venv", ["pyproject.toml", "requirements.txt", "setup.py"]), ("__pycache__", ["pyproject.toml", "requirements.txt", "setup.py"]),
        ("DerivedData", ["*.xcodeproj"]),
    ]
    /// The walk for projects stays bounded: this many folder levels below the picked folder, this many folders in all,
    /// and this many projects.
    static let depth = 8
    static let folderLimit = 20_000
    static let projectLimit = 500
    /// Files looked at to date a project; a bigger project can't be dated, so it is kept.
    static let datingLimit = 100_000
    /// Each build folder is sized for at most this long; a larger one shows "At least".
    static let sizingBudget: TimeInterval = 10

    /// The build folders directly inside `project` whose marker sits beside them: real folders the user owns, never symlinks.
    static func buildFolders(in project: URL) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: project.path) else { return [] }
        let present = Set(names)
        func marked(_ markers: [String]) -> Bool {
            markers.contains { marker in
                marker.hasPrefix("*.") ? names.contains { ($0 as NSString).pathExtension == String(marker.dropFirst(2)) } : present.contains(marker)
            }
        }
        return kinds.filter { present.contains($0.folder) && marked($0.markers) }.compactMap { kind in
            let url = project.appendingPathComponent(kind.folder)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else { return nil }
            return url
        }
    }

    /// The build folders in `scope`, a folder the user picked, grouped by project (`profile`) and dated by the project's
    /// last change (`lastUsed`). A project being worked on (`refusal(for:)`) offers nothing. Read-only.
    public static func candidates(in scope: URL, rule: CleanupRule = rule, exclusions: ExclusionPolicy = ExclusionPolicy(), home: URL,
                                  inUse: any InUseChecking = SystemInUseChecker(), now: Date = Date()) -> [Candidate] {
        guard let scopePath = realPath(scope.path) else { return [] }
        let scope = URL(fileURLWithPath: scopePath, isDirectory: true), catalog = Catalog(rules: [rule]), protection = Protection(rule)
        let sizer = KnownLocationSizer(timeBudget: sizingBudget), inUse = inUse.snapshot()
        var projects: [(URL, [URL])] = [], skipped = Set<String>(), folders = 0
        FileTree.walk(scope) { entry in
            guard Int32(entry.pointee.fts_info) == FTS_D else { return .continue }
            let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path)), level = Int(entry.pointee.fts_level)
            folders += 1
            guard folders <= folderLimit, projects.count < projectLimit else { return .stop }
            // Never inside a build folder, git's own data, a hidden folder, a package or a protected folder.
            if level > 0, skipped.contains(url.path) || url.lastPathComponent.hasPrefix(".") || url.lastPathComponent == "node_modules"
                || protection.protects(url.lastPathComponent) { return .skip }
            if UserFiles.protectedFolder(of: url, home: home) != nil { return .skip }
            let found = buildFolders(in: url)
            if !found.isEmpty { projects.append((url, found)); skipped.formUnion(found.map(\.path)) }
            return level < depth ? .continue : .skip
        }
        return projects.flatMap { project, found -> [Candidate] in
            guard let lastChange = lastChange(in: project), refusal(ofProject: project, lastChange: lastChange, inUse: inUse, home: home, now: now) == nil else { return [] }
            let name = project.path == scope.path ? scope.lastPathComponent : String(project.path.dropFirst(scope.path.count + 1))
            return found.compactMap { url in
                var info = stat()
                guard lstat(url.path, &info) == 0, protection.protectedComponent(of: url, below: scope) == nil,
                      CandidateCheck.protectedEntry(in: url, rule: rule) == nil, trackedRefusal(url, home: home) == nil else { return nil }
                let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                if !exclusions.rules.isEmpty, volume.map({ exclusions.covers(url, volumeID: $0) }) ?? true { return nil }
                let size = sizer.size(url)
                var found = catalog.candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete,
                                              lastUsed: lastChange, profile: name)
                // Named with its project, so a review or result line says which `node_modules` it was.
                found.itemName = url.lastPathComponent + " in " + project.lastPathComponent
                return found.found(under: scope)
            }
        }
    }

    /// Why a project's build folder is kept now (SPEC section 4), checked at the scan and again just before acting: it is no
    /// longer beside its marker, the project is open in an app or tool, it changed in the last `recentDays`, git has
    /// uncommitted changes to its tracked files, or git tracks the build folder itself. Nil when it may go.
    static func refusal(for buildFolder: URL, inUse: any InUseChecking, home: URL, now: Date = Date()) -> CheckRefusal? {
        let project = buildFolder.deletingLastPathComponent()
        guard buildFolders(in: project).contains(where: { $0.path == buildFolder.path }) else { return .changed }
        guard let lastChange = lastChange(in: project) else { return .projectUnchecked }
        return refusal(ofProject: project, lastChange: lastChange, inUse: inUse, home: home, now: now) ?? trackedRefusal(buildFolder, home: home)
    }

    /// The project-wide reasons: open, recently changed, or uncommitted changes to tracked files.
    private static func refusal(ofProject project: URL, lastChange: Date, inUse: any InUseChecking, home: URL, now: Date) -> CheckRefusal? {
        // Any process working in the project counts: its editor, a build tool, a shell or a running build.
        guard let used = inUse.inUse([project], by: .anyApp) else { return .projectUnchecked }
        if !used.isEmpty { return .projectOpen }
        if lastChange > now.addingTimeInterval(-Double(recentDays) * 86_400) { return .recentlyEdited }
        guard GitCheckout.encloses(project.appendingPathComponent(".git"), upTo: nil, home: home) else { return nil }
        guard let changes = git(project, ["status", "--porcelain", "--untracked-files=no", "--ignore-submodules=dirty", "--no-renames"]) else { return .projectUnchecked }
        return changes.isEmpty ? nil : .uncommittedChanges
    }

    /// A build folder git tracks files in (a committed `dist`) is the project's own content, so it is kept.
    private static func trackedRefusal(_ buildFolder: URL, home: URL) -> CheckRefusal? {
        let project = buildFolder.deletingLastPathComponent()
        guard GitCheckout.encloses(project.appendingPathComponent(".git"), upTo: nil, home: home) else { return nil }
        guard let tracked = git(project, ["ls-files", "--", buildFolder.lastPathComponent]) else { return .projectUnchecked }
        return tracked.isEmpty ? nil : .trackedByGit
    }

    /// Git's trimmed output, read-only and bounded like every workspace read (`WorkspaceGit`); nil when git is missing or fails.
    private static func git(_ project: URL, _ arguments: [String]) -> String? {
        guard let git = WorkspaceGit.installed(),
              let result = try? BoundedTool.capture(executable: git, arguments: WorkspaceGit.baseArguments(project) + arguments, timeout: WorkspaceGit.timeout,
                                                    outputLimit: 1_024, environment: WorkspaceGit.environment), result.status == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// When anything in the project last changed: the newest file outside its build folders and git's data. Nil when
    /// the project is too big to date or can't be read, so it is kept.
    static func lastChange(in project: URL) -> Date? {
        var newest = Date.distantPast, seen = 0, complete = true
        var skipped = Set<String>()
        let opened = FileTree.walk(project) { entry in
            let kind = Int32(entry.pointee.fts_info)
            let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
            switch kind {
            case FTS_DNR, FTS_ERR, FTS_NS: complete = false; return .stop
            case FTS_D:
                if skipped.contains(url.path) || url.lastPathComponent == ".git" { return .skip }
                skipped.formUnion(buildFolders(in: url).map(\.path))
                return .continue
            case FTS_DP: return .continue
            default: break
            }
            seen += 1
            if seen > datingLimit { complete = false; return .stop }
            guard url.lastPathComponent != ".DS_Store", let info = entry.pointee.fts_statp?.pointee else { return .continue }
            let time = info.st_mtimespec
            newest = max(newest, Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9))
            return .continue
        }
        return opened && complete ? newest : nil
    }
}
