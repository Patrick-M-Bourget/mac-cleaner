import Foundation
import Darwin
import CryptoKit

public struct ProtectedItemsRule: Codable, Sendable, Identifiable, Equatable {
    /// Raw values are stored in Protected items and in Storage trends' fingerprint of them (#448): a renamed case keeps its string.
    public enum Boundary: String, Codable, Sendable { case file = "file", folder = "folder" }
    public let id: UUID
    public let path: String
    public let volumeID: String
    public let boundary: Boundary
    /// Stored in Protected items (#448): a renamed property keeps its key here; a new field needs its key here and in the fixture.
    private enum CodingKeys: String, CodingKey { case id = "id", path = "path", volumeID = "volumeID", boundary = "boundary" }
    public static func capture(_ url: URL) throws -> ProtectedItemsRule {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var info = stat()
        guard lstat(resolved.path, &info) == 0, [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT),
              let volume = try resolved.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else { throw CocoaError(.fileReadNoPermission) }
        return ProtectedItemsRule(id: UUID(), path: resolved.path, volumeID: volume, boundary: info.st_mode & S_IFMT == S_IFDIR ? .folder : .file)
    }
}
public struct ProtectedItemsPolicy: Sendable {
    public let rules: [ProtectedItemsRule]
    public init(rules: [ProtectedItemsRule] = []) { self.rules = rules }
    public var fingerprint: String {
        guard !rules.isEmpty else { return "none" }
        let normalized = Set(rules.map { [ $0.volumeID, $0.boundary.rawValue, $0.path ] }).sorted { $0.lexicographicallyPrecedes($1) }
        // Length framing preserves arbitrary legal filename separators and newlines.
        let encoded = Data(normalized.flatMap { $0 }.map { "\($0.utf8.count):" + $0 }.joined().utf8)
        return "path-volume-v1:" + SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }
    /// Lexical component match only; callers supply the canonical scoped path, never follow descendants.
    public func matches(_ url: URL, volumeID: String) -> Bool {
        let parts = url.standardizedFileURL.pathComponents
        return rules.contains { rule in
            guard rule.volumeID == volumeID else { return false }
            let expected = URL(fileURLWithPath: rule.path).pathComponents
            return rule.boundary == .folder ? parts.starts(with: expected) : parts == expected
        }
    }
    /// SPEC section 2: an item is off limits when it is excluded, sits inside an excluded folder, or holds an exclusion.
    /// Discovery leaves such items out, and the check just before acting refuses them.
    public func covers(_ url: URL, volumeID: String) -> Bool {
        if matches(url, volumeID: volumeID) { return true }
        let parts = url.standardizedFileURL.pathComponents
        return rules.contains { $0.volumeID == volumeID && URL(fileURLWithPath: $0.path).pathComponents.starts(with: parts) }
    }
}
/// This store owns one bounded settings file; it has no plan or cleanup/journal authority.
public actor ProtectedItemsStore {
    private struct Archive: Codable {
        let version: Int; let rules: [ProtectedItemsRule]
        private enum CodingKeys: String, CodingKey { case version = "version", rules = "rules" }
    }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func policy() throws -> ProtectedItemsPolicy { try transaction { try read() } }
    public func add(_ rule: ProtectedItemsRule) throws {
        try transaction {
            var rules = try read().rules
            guard !rules.contains(where: { $0.path == rule.path && $0.volumeID == rule.volumeID && $0.boundary == rule.boundary }) else { return }
            guard rules.count < 100 else { throw CocoaError(.fileWriteOutOfSpace) }
            rules.append(rule); try write(rules)
        }
    }
    public func remove(_ id: UUID) throws { try transaction { try write(read().rules.filter { $0.id != id }) } }
    public func reset() throws { try transaction { try write([]) } }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            guard errno == ENOENT else { throw CocoaError(.fileReadNoPermission) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else { throw CocoaError(.fileReadNoPermission) }
        let descriptor = open(directory.appendingPathComponent(".rules-lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        return try body()
    }
    private func read() throws -> ProtectedItemsPolicy { try Self.policy(readingOnly: directory) }
    /// The saved rules without the lock or creating anything, for a read-only report (#319): a missing file means none.
    public static func policy(readingOnly directory: URL) throws -> ProtectedItemsPolicy {
        let file = directory.appendingPathComponent("rules-v1.json")
        var info = stat()
        if lstat(file.path, &info) != 0 {
            if errno == ENOENT { return ProtectedItemsPolicy() }; throw CocoaError(.fileReadNoPermission)
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_size <= 1_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
        guard archive.version == 1, archive.rules.count <= 100, Set(archive.rules.map(\.id)).count == archive.rules.count,
              archive.rules.allSatisfy({ $0.path.hasPrefix("/") && $0.path.utf8.count <= 8192 && !$0.volumeID.isEmpty && $0.volumeID.utf8.count <= 512 }) else { throw CocoaError(.fileReadCorruptFile) }
        return ProtectedItemsPolicy(rules: archive.rules)
    }
    private func write(_ rules: [ProtectedItemsRule]) throws {
        let data = try JSONEncoder().encode(Archive(version: 1, rules: rules))
        guard data.count <= 1_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        let file = directory.appendingPathComponent("rules-v1.json")
        var previous = stat()
        if lstat(file.path, &previous) == 0 {
            guard previous.st_mode & S_IFMT == S_IFREG, previous.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
        } else if errno != ENOENT { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
