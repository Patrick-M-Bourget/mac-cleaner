import Foundation
import Darwin

/// Configuration only. Kind is a presentation hint, never permission to clean a path.
public struct RememberedScope: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable { case downloads, inspection }
    public let id: UUID
    public let path: String
    public var isIncluded: Bool
    public let kind: Kind
    fileprivate let bookmark: Data
}

public enum ScopeRegistryError: Error { case unknownScope, excluded, chooseAgain, unavailable, invalidStorage }

/// Keeps a resolved grant alive only for an explicit scan. Does not enumerate or open file contents.
public final class ScopeAccessLease {
    public let url: URL
    private var accessing: Bool
    fileprivate init(url: URL, accessing: Bool) { self.url = url; self.accessing = accessing }
    public func close() { if accessing { url.stopAccessingSecurityScopedResource(); accessing = false } }
    deinit { close() }
}

/// Bounded app-local configuration; no observations, selection, execution or recovery authority.
public struct ScopeRegistry: Sendable {
    private struct Archive: Codable { let version: Int; let scopes: [RememberedScope] }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func list() throws -> [RememberedScope] { try transaction { try read() } }
    @discardableResult public func remember(url: URL, kind: RememberedScope.Kind) throws -> RememberedScope {
        guard url.isFileURL else { throw ScopeRegistryError.unavailable }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        // Check the selected entry before resolving ancestor aliases. A root symlink
        // must not silently become a different remembered scan scope.
        try checkDirectory(url)
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        try checkDirectory(canonical)
        let bookmark = try canonical.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return try transaction {
            var scopes = try read()
            let previous = scopes.first { $0.path == canonical.path }
            let scope = RememberedScope(id: previous?.id ?? UUID(), path: canonical.path, isIncluded: true, kind: kind, bookmark: bookmark)
            if let index = scopes.firstIndex(where: { $0.id == scope.id }) { scopes[index] = scope } else { scopes.append(scope) }
            try write(scopes)
            return scope
        }
    }
    public func setIncluded(_ included: Bool, id: UUID) throws {
        try transaction {
            var scopes = try read()
            guard let index = scopes.firstIndex(where: { $0.id == id }) else { throw ScopeRegistryError.unknownScope }
            scopes[index].isIncluded = included
            try write(scopes)
        }
    }
    public func forget(_ id: UUID) throws { try transaction { try write(read().filter { $0.id != id }) } }
    public func reset() throws { try transaction { try write([]) } }
    public func resolveForScan(id: UUID) throws -> ScopeAccessLease {
        guard let scope = try list().first(where: { $0.id == id }) else { throw ScopeRegistryError.unknownScope }
        guard scope.isIncluded else { throw ScopeRegistryError.excluded }
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: scope.bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw ScopeRegistryError.chooseAgain }
        guard !stale, url.standardizedFileURL.path == scope.path else { throw ScopeRegistryError.chooseAgain }
        let started = url.startAccessingSecurityScopedResource()
        do { try checkDirectory(url) }
        catch { if started { url.stopAccessingSecurityScopedResource() }; throw error }
        return ScopeAccessLease(url: url, accessing: started)
    }
    private func checkDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, access(url.path, R_OK | X_OK) == 0 else { throw ScopeRegistryError.unavailable }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            guard errno == ENOENT else { throw ScopeRegistryError.invalidStorage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(), directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().path else { throw ScopeRegistryError.invalidStorage }
        let fd = open(directory.appendingPathComponent(".scopes-lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ScopeRegistryError.invalidStorage }
        defer { _ = flock(fd, LOCK_UN); close(fd) }
        var lockInfo = stat()
        guard fstat(fd, &lockInfo) == 0, lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_uid == geteuid(), flock(fd, LOCK_EX) == 0 else { throw ScopeRegistryError.invalidStorage }
        return try body()
    }
    private func read() throws -> [RememberedScope] {
        let file = directory.appendingPathComponent("scopes-v1.json")
        var info = stat()
        if lstat(file.path, &info) != 0 { if errno == ENOENT { return [] }; throw ScopeRegistryError.invalidStorage }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_size <= 4_000_000 else { throw ScopeRegistryError.invalidStorage }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
        guard archive.version == 1, archive.scopes.count <= 100, Set(archive.scopes.map(\.id)).count == archive.scopes.count,
              Set(archive.scopes.map(\.path)).count == archive.scopes.count,
              archive.scopes.allSatisfy({ $0.path.hasPrefix("/") && $0.path.utf8.count <= 8192 && !$0.bookmark.isEmpty && $0.bookmark.count <= 32000 }) else { throw ScopeRegistryError.invalidStorage }
        return archive.scopes
    }
    private func write(_ scopes: [RememberedScope]) throws {
        guard scopes.count <= 100 else { throw ScopeRegistryError.invalidStorage }
        let data = try JSONEncoder().encode(Archive(version: 1, scopes: scopes))
        guard data.count <= 4_000_000 else { throw ScopeRegistryError.invalidStorage }
        let file = directory.appendingPathComponent("scopes-v1.json")
        var info = stat()
        if lstat(file.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { throw ScopeRegistryError.invalidStorage }
        } else if errno != ENOENT { throw ScopeRegistryError.invalidStorage }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
