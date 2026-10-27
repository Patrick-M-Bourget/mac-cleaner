import Foundation
import Darwin

/// What discovery does when a tool that names its own folder isn't found or doesn't say where it is.
public enum UnansweredLocation: Sendable, Hashable {
    /// Nothing is offered and the folder is never touched: uv's cache is changed only through uv (Decision 44).
    case notOffered
    /// The rule's default locations are offered instead, and the plan says so (#170): npm, pip, pnpm and Homebrew.
    case defaultLocations
}

/// Where a rule whose tool names its folder looks, after asking (`Catalog.reportedLocation`).
enum ReportedLocation: Equatable {
    /// A folder the tool named that isn't one of the rule's defaults. The item says where it came from (#206).
    case folder(URL)
    /// The rule's own locations: the tool named one of them or a folder inside one (no note), or it didn't answer and the rule
    /// falls back (a note, shown only when something is offered there).
    case defaults(CatalogNote?)
    /// Nothing is offered. `notMeasured` when the rule's size is unknown rather than nothing.
    case notOffered(CatalogNote, notMeasured: Bool)
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
    static func locationQueryNotice(_ tool: ToolCommand, query: [String]) -> String {
        let name = tool.executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return "\(name) didn’t say where its cache is (`\(([name] + query).joined(separator: " "))`), so it isn’t offered."
    }

    /// Asks `asker`, installed at `toolURL` (nil when it isn't in one of its known locations), where `rule`'s folder is.
    /// Only the asker's own known executables are ever run. A named folder must pass the same scope checks as any other
    /// candidate; one that is missing, outside `base`, or holds more than the tool's cache is never offered, whatever the rule.
    func reportedLocation(of rule: CleanupRule, asking asker: ToolCommand, at toolURL: URL?, base: URL) -> ReportedLocation {
        guard let query = asker.locationQuery else { return .defaults(nil) }
        let name = rule.owner?.name ?? asker.executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? rule.title
        let command = "`" + ([asker.executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""] + query).joined(separator: " ") + "`"
        func unanswered(_ reason: String) -> ReportedLocation {
            switch asker.whenLocationUnanswered {
            case .notOffered: return .notOffered(CatalogNote(ruleID: rule.id, text: Self.locationQueryNotice(asker, query: query)), notMeasured: true)
            case .defaultLocations: return .defaults(CatalogNote(ruleID: rule.id, text: reason))
            }
        }
        guard let toolURL else { return unanswered("\(name) wasn’t found, so its usual folder is offered.") }
        guard case .success(let named) = Self.reportedFolder(by: toolURL, query: query, timeout: asker.locationQueryTimeout) else {
            return unanswered("\(name) didn’t say where its cache is (\(command)), so its usual folder is offered.")
        }
        let folder = asker.reportedSubfolder.map { named.appendingPathComponent($0) } ?? named
        // A folder inside a usual location is that location: `pnpm store path` names `~/Library/pnpm/store/v10` (#206).
        let namedPath = folder.standardizedFileURL.path
        if rule.locations.contains(where: { location in
            let usual = base.appendingPathComponent(location).standardizedFileURL.path
            return !location.contains("*") && (namedPath == usual || namedPath.hasPrefix(usual + "/"))
        }) { return .defaults(nil) }
        let shown = Self.tildePath(folder, base: base)
        func refused(_ why: String) -> ReportedLocation { .notOffered(CatalogNote(ruleID: rule.id, text: "\(name) names \(shown) as its cache (\(command)), \(why), so it isn’t offered."), notMeasured: false) }
        var info = stat()
        guard lstat(folder.path, &info) == 0 else { return refused("but there’s no folder there") }
        guard ScopeContainment.contains(folder, in: base) else { return refused("which is outside your home folder") }
        if holdsMoreThanACache(folder, base: base, besides: rule) { return refused("which holds more than its cache") }
        // A folder the rule deletes must look like the tool's cache: a tool set to a project folder would otherwise take it (#205).
        if rule.deletesItems {
            if let userFolder = Self.userContentFolder(holding: folder, base: base) { return refused("which is inside your \(userFolder) folder") }
            if let markers = asker.cacheMarkers, !markers.contains(where: { Self.isFolder(folder.appendingPathComponent($0)) }) {
                return refused("which doesn’t look like its cache")
            }
        }
        return .folder(folder)
    }

    /// What a tool-asked item shows as its folder's source when the tool named it (#206).
    static func namedBy(_ asker: ToolCommand) -> String? {
        asker.locationQuery.map { "Named by `" + ([asker.executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""] + $0).joined(separator: " ") + "`" }
    }

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
