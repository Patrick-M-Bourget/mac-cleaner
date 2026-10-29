import Foundation
import Darwin

/// What discovery does when a tool that names its own folder isn't found or doesn't say where it is.
public enum UnansweredLocation: Sendable, Hashable {
    /// Nothing is offered and the folder is never touched: uv's cache is changed only through uv (Decision 44).
    case notOffered
    /// The rule's default locations are offered instead, and the plan says so (#170): npm, pip, pnpm and Homebrew.
    case defaultLocations
}

/// How a tool is asked where it keeps its data, as in `uv cache dir` (Decision 44). Discovery asks the tool, and the folder it
/// names is the candidate instead of the rule's locations. A tool that doesn't answer within `timeout`, fails or names no
/// usable folder is handled by `whenUnanswered`.
public struct LocationQuery: Sendable, Hashable {
    /// The arguments that make the tool print the folder.
    public let arguments: [String]
    public let timeout: TimeInterval
    /// What discovery does when the tool isn't found or doesn't say where its folder is.
    public let whenUnanswered: UnansweredLocation
    /// The folder inside the one the tool names that is the candidate, as `_cacache` inside `npm config get cache`.
    public let reportedSubfolder: String?
    /// Entries the tool's docs say its cache holds (pip's `http-v2`, Homebrew's `downloads`). When set, a folder the tool names
    /// that a rule deletes is offered only when it holds at least one of them as a folder (#205).
    public let cacheMarkers: Set<String>?
    /// The config file that can set the folder, read (never run) when the tool isn't in a known location (#201).
    public let configuredIn: CacheConfig?
    public init(_ arguments: [String], timeout: TimeInterval = 5, whenUnanswered: UnansweredLocation = .notOffered, reportedSubfolder: String? = nil,
                cacheMarkers: Set<String>? = nil, configuredIn: CacheConfig? = nil) {
        self.arguments = arguments; self.timeout = timeout; self.whenUnanswered = whenUnanswered
        self.reportedSubfolder = reportedSubfolder; self.cacheMarkers = cacheMarkers; self.configuredIn = configuredIn
    }
}

/// A tool's own config file that can set where its cache is (#201). CacheDrop never runs a tool from a version manager
/// (nvm, fnm, Volta, pyenv, asdf, mise); when the tool isn't in a known location, this file is read instead, as text only.
/// Only the user's own file is read: a project's, a global one or an environment variable can set the folder too, and
/// then the usual folder is offered with a note that says so.
public enum CacheConfig: Sendable, Hashable {
    /// `cache=` in `~/.npmrc` (https://docs.npmjs.com/cli/configuring-npm/npmrc, https://docs.npmjs.com/cli/using-npm/config#cache).
    case npmrc
    /// `cache-dir` in the `[global]` section of the user's pip.conf (https://pip.pypa.io/en/stable/topics/configuration/).
    case pipConf

    /// What the user's config file sets, if it sets anything.
    struct Setting: Equatable {
        /// The file, as shown (`~/.npmrc`).
        let file: String
        /// The folder it names; nil when the value can't be followed without running something (`${VAR}`, a relative path).
        let folder: URL?
    }

    /// The file this config is read from under `home`. pip reads `~/Library/Application Support/pip` when that folder exists,
    /// else `~/.config/pip` (pip's `utils/appdirs.py`, `_macos_user_config_dir`).
    func file(home: URL) -> String {
        switch self {
        case .npmrc: return ".npmrc"
        case .pipConf: return Catalog.isFolder(home.appendingPathComponent("Library/Application Support/pip")) ? "Library/Application Support/pip/pip.conf" : ".config/pip/pip.conf"
        }
    }

    /// Reads the setting from the user's file under `home`. Nil when the file is missing, unreadable, too large or doesn't set it.
    func setting(home: URL) -> Setting? {
        let relative = file(home: home), url = home.appendingPathComponent(relative)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size < 256_000,
              let text = try? String(contentsOf: url, encoding: .utf8), let value = value(in: text) else { return nil }
        return Setting(file: "~/" + relative, folder: Self.folder(value, home: home))
    }

    /// The raw value: the last one set, as both npm's `ini` parser and pip's `configparser` keep the last.
    func value(in text: String) -> String? {
        var section = "", found: String?
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).lowercased(); continue }
            let separators: Set<Character> = self == .npmrc ? ["="] : ["=", ":"]
            guard let split = line.firstIndex(where: separators.contains) else { continue }
            let key = line[..<split].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
            switch self {
            case .npmrc:
                guard section.isEmpty, key == "cache" else { continue }
                if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" { value = String(value.dropFirst().dropLast()) }
            case .pipConf:
                // pip reads `cache_dir` and `--cache-dir` as `cache-dir`.
                let name = key.replacingOccurrences(of: "_", with: "-")
                guard section == "global", name == "cache-dir" || name == "--cache-dir" else { continue }
                // A value continued on the next, indented line isn't one folder.
                if index + 1 < lines.count, let next = lines[index + 1].first, next == " " || next == "\t",
                   !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty { value = "" }
            }
            found = value
        }
        return found
    }

    /// An absolute folder from a value, with a leading `~` as the home folder (npm's and pip's path options expand it).
    /// Anything else, such as `${NPM_CACHE}` or a path relative to wherever the tool runs, can't be followed.
    static func folder(_ value: String, home: URL) -> URL? {
        let path = value == "~" ? home.path : value.hasPrefix("~/") ? home.path + value.dropFirst() : value
        guard path.hasPrefix("/"), !path.contains("$"), !path.contains("\n"),
              path.dropFirst().split(separator: "/", omittingEmptySubsequences: true).allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Why a folder a tool names, or its config sets, can't be its cache (#205), checked at the scan and again just before acting.
enum NotACache: Equatable {
    case outsideHome, holdsMore, insideUserFolder(String), unlikeCache
    /// The clause in the plan's note, as in "…, which is inside your Documents folder, so it isn’t offered."
    var clause: String {
        switch self {
        case .outsideHome: "which is outside your home folder"
        case .holdsMore: "which holds more than its cache"
        case .insideUserFolder(let folder): "which is inside your \(folder) folder"
        case .unlikeCache: "which doesn’t look like its cache"
        }
    }
    /// Why the check keeps it, naming the tool.
    func reason(_ name: String) -> String {
        switch self {
        case .outsideHome: "It is outside your home folder, so it is kept."
        case .holdsMore: "It holds more than \(name)’s cache, so it is kept."
        case .insideUserFolder(let folder): "It is inside your \(folder) folder, so it is kept."
        case .unlikeCache: "It doesn’t look like \(name)’s cache, so it is kept."
        }
    }
}

/// A tool that is only asked where a rule's folder is (`npm config get cache`, #170): the executables to try and the question.
public struct LocationTool: Sendable, Hashable {
    /// Absolute paths to try in order; the first installed one is asked.
    public let executables: [String]
    public let query: LocationQuery
    public init(executables: [String], query: LocationQuery) { self.executables = executables; self.query = query }
    /// The tool's name, as in `npm`.
    public var name: String { executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "" }
    /// The question as shown in the plan, as in `npm config get cache` (in backticks).
    var commandLine: String { "`" + ([name] + query.arguments).joined(separator: " ") + "`" }
    /// Only for finding the installed executable with discovery's `locateTool`; never run as a cleanup command.
    var lookup: ToolCommand { ToolCommand(executables: executables, arguments: [], timeout: 0) }
}

/// Where a rule whose tool names its folder looks, after asking (`Catalog.reportedLocation`).
enum ReportedLocation: Equatable {
    /// A folder the tool named, or its config set, that isn't one of the rule's defaults. The item says where it came from (#206).
    case folder(URL, source: String)
    /// The rule's own locations: the tool named one of them or a folder inside one (no note, `source` says who), or it didn't
    /// answer and the rule falls back (a note, shown only when something is offered there).
    case defaults(CatalogNote?, source: String? = nil)
    /// Nothing is offered. `notMeasured` when the rule's size is unknown rather than nothing.
    case notOffered(CatalogNote, notMeasured: Bool, named: URL? = nil)

    /// The folder the tool named or its config set, offered or not, whose siblings may hold an interrupted clean's leftovers (#202).
    var named: URL? {
        switch self {
        case .folder(let folder, _): folder
        case .notOffered(_, _, let named): named
        case .defaults: nil
        }
    }
}

/// A tool that says where it keeps its data (`uv cache dir`, Decision 44; `npm config get cache`, #170), so CacheDrop never guesses the folder.
extension Catalog {
    /// The folder the tool prints for `query`: one absolute path with no `.` or `..` parts. Anything else is a failure,
    /// and so is a tool that fails or doesn't answer within `timeout`. Run like the cleanup command, with the tool's folder on PATH
    /// and no shell, so no shell startup file runs.
    static func reportedFolder(by tool: URL, query: [String], timeout: TimeInterval) -> Result<URL, ToolPreviewError> {
        var environment = BoundedTool.defaultEnvironment
        environment["PATH"] = tool.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        let output: String
        do { output = try BoundedTool.run(executable: tool, arguments: query, timeout: timeout, outputLimit: 4096, environment: environment) }
        catch let error as ToolPreviewError { return .failure(error) }
        catch { return .failure(.failed) }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), path != "/", !path.contains("\n"),
              path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return .failure(.invalidOutput) }
        return .success(URL(fileURLWithPath: path))
    }

    /// Why a rule whose tool names its folder offers nothing: the tool didn't say where it is. Never a size of 0.
    static func locationQueryNotice(_ tool: LocationTool) -> String {
        "\(tool.name) didn’t say where its cache is, so it isn’t offered."
    }

    /// Asks `asker`, installed at `toolURL` (nil when it isn't in one of its known locations), where `rule`'s folder is.
    /// Only the asker's own known executables are ever run; without one, its config file is read instead (#201).
    /// A named or configured folder must pass the same scope checks as any other candidate; one that is missing,
    /// outside `base`, or holds more than the tool's cache is never offered, whatever the rule.
    func reportedLocation(of rule: CleanupRule, asking asker: LocationTool, at toolURL: URL?, base: URL) -> ReportedLocation {
        let query = asker.query, name = rule.owner?.name ?? asker.name
        func unanswered(_ reason: String) -> ReportedLocation {
            switch query.whenUnanswered {
            case .notOffered: return .notOffered(CatalogNote(ruleID: rule.id, text: Self.locationQueryNotice(asker)), notMeasured: true)
            case .defaultLocations: return .defaults(CatalogNote(ruleID: rule.id, text: reason))
            }
        }
        let named: URL, source: String, says: (String) -> String
        if let toolURL {
            guard case .success(let folder) = Self.reportedFolder(by: toolURL, query: query.arguments, timeout: query.timeout) else {
                return unanswered("\(name) didn’t say where its cache is, so its default folder is shown.")
            }
            named = folder; source = Self.namedBy(name); says = { "\(name) names \($0) as its cache" }
        } else if let setting = query.configuredIn?.setting(home: base) {
            guard let folder = setting.folder else {
                return .notOffered(CatalogNote(ruleID: rule.id, text: "\(setting.file) sets \(name)’s cache in a way CacheDrop can’t follow, so it isn’t offered."), notMeasured: true)
            }
            named = folder; source = "Set in " + setting.file; says = { "\(setting.file) sets \($0) as \(name)’s cache" }
        } else {
            return unanswered("CacheDrop couldn’t find \(name), so its default cache folder is shown.")
        }
        let folder = query.reportedSubfolder.map { named.appendingPathComponent($0) } ?? named
        // A folder inside a usual location is that location: `pnpm store path` names `~/Library/pnpm/store/v10` (#206).
        if isUsualLocation(folder, of: rule, base: base) { return .defaults(nil, source: source) }
        let shown = Self.tildePath(folder, base: base)
        func refused(_ why: String) -> ReportedLocation {
            .notOffered(CatalogNote(ruleID: rule.id, text: "\(says(shown)), \(why), so it isn’t offered."), notMeasured: false, named: folder)
        }
        var info = stat()
        guard lstat(folder.path, &info) == 0 else { return refused("but there’s no folder there") }
        if let problem = notACache(folder, of: rule, markers: query.cacheMarkers, base: base) { return refused(problem.clause) }
        return .folder(folder, source: source)
    }

    /// Whether `folder` is one of `rule`'s own locations or inside one.
    func isUsualLocation(_ folder: URL, of rule: CleanupRule, base: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        return rule.locations.contains { location in
            let usual = base.appendingPathComponent(location).standardizedFileURL.path
            return !location.contains("*") && (path == usual || path.hasPrefix(usual + "/"))
        }
    }

    /// #205's write-scope checks for a folder a tool named or its config set: inside `base`, no more than the tool's cache,
    /// and, for a rule that deletes it, never inside a folder for the user's own files and holding an entry the tool's docs describe.
    func notACache(_ folder: URL, of rule: CleanupRule, markers: Set<String>?, base: URL) -> NotACache? {
        guard ScopeContainment.contains(folder, in: base) else { return .outsideHome }
        if holdsMoreThanACache(folder, base: base, besides: rule) { return .holdsMore }
        // A folder the rule deletes must look like the tool's cache: a tool set to a project folder would otherwise take it (#205).
        if rule.deletesItems {
            if let userFolder = Self.userContentFolder(holding: folder, base: base) { return .insideUserFolder(userFolder) }
            if let markers, !markers.contains(where: { Self.isFolder(folder.appendingPathComponent($0)) }) { return .unlikeCache }
        }
        return nil
    }

    /// The check just before acting runs the write-scope checks again on an item outside the rule's usual locations,
    /// which a tool named or its config set (#201, #205), and on a leftover next to such a folder (#202). A leftover isn't asked
    /// for the tool's markers, which a half-deleted cache may have lost, and one next to a usual location is that location's.
    /// A leftover may be a file, since discovery offers those too (#262). Nil for every other item.
    func notACacheRefusal(_ candidate: Candidate, rule: CleanupRule, base: URL) -> CheckRefusal? {
        let parent = candidate.url.deletingLastPathComponent().standardizedFileURL.path
        guard let asker = rule.locationAsker?.tool, candidate.isDirectory || candidate.isLeftover, !isUsualLocation(candidate.url, of: rule, base: base),
              !candidate.isLeftover || !leftoverFolders(of: rule, in: base).contains(where: { $0.standardizedFileURL.path == parent }),
              let problem = notACache(candidate.url, of: rule, markers: candidate.isLeftover ? nil : asker.query.cacheMarkers, base: base) else { return nil }
        return .notACache(problem.reason(rule.owner?.name ?? asker.name))
    }

    /// What a tool-asked item shows as its folder's source when the tool named it (#206).
    static func namedBy(_ name: String) -> String { "Location from " + name }

    /// Home folders a tool's cache never is, whatever it says: deleting one would take the user's own files.
    static let homeFoldersNeverACache: Set<String> = ["Applications", "Desktop", "Developer", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public"]

    /// Home folders for the user's own files: a cache CacheDrop deletes is never anywhere inside one (#205).
    static let userContentFolders: Set<String> = ["Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"]

    /// The standard folder for the user's own files that `folder` is inside, at any depth; nil when it's in none.
    static func userContentFolder(holding folder: URL, base: URL) -> String? {
        let parts = folder.standardizedFileURL.pathComponents.dropFirst(base.standardizedFileURL.pathComponents.count)
        return parts.first.flatMap { userContentFolders.contains($0) ? $0 : nil }
    }

    /// Whether `url` is a real folder, not a link to one.
    static func isFolder(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// Whether a folder a tool named is the home folder itself, one of its standard folders, or holds another rule's location
    /// (a cache set to `~/Library/Caches`), so cleaning it would take more than the tool's cache.
    func holdsMoreThanACache(_ folder: URL, base: URL, besides rule: CleanupRule) -> Bool {
        let parts = Array(folder.standardizedFileURL.pathComponents.dropFirst(base.standardizedFileURL.pathComponents.count))
        if parts.isEmpty || (parts.count == 1 && Self.homeFoldersNeverACache.contains(parts[0])) { return true }
        return rules.contains { other in
            other.id != rule.id && other.base == rule.base && other.locations.contains { location in
                let pattern = location.split(separator: "/").map(String.init)
                guard pattern.count > parts.count else { return false }
                return zip(pattern, parts).allSatisfy { fnmatch($0, $1, 0) == 0 }
            }
        }
    }

    /// `path` with the home folder shown as `~`.
    static func tildePath(_ url: URL, base: URL) -> String {
        let path = url.standardizedFileURL.path, home = base.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
