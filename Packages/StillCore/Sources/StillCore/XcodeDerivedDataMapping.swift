import Foundation
import Darwin

/// Observed Xcode26.6/17F113 standard unique-project layout, not a public plist schema.
/// This resolver supplies metadata evidence only; installation/owner/exact-file approval
/// remain separate requirements before mutation.
enum XcodeDerivedDataMapping {
    static func projects(in root: URL) throws -> XcodeProjectMapping {
        try directory(root)
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard children.count <= 1_000 else { throw XcodeIntermediateFailure("DerivedData inventory exceeds the supported limit.") }
        let shared = Set(["ModuleCache.noindex", "Index.noindex", "CompilationCache.noindex", "SDKStatCaches.noindex", "SymbolCache.noindex"])
        var associations: [XcodeProjectAssociation] = []
        var unavailable: [XcodeUnavailableProject] = []
        for child in children.sorted(by: { $0.path < $1.path }) {
            if shared.contains(child.lastPathComponent) { continue }
            var info = stat()
            guard lstat(child.path, &info) == 0 else {
                unavailable.append(.init(derivedDataURL: child, reason: "Project directory changed during inspection.")); continue
            }
            if info.st_mode & S_IFMT == S_IFREG { continue }
            do { associations.append(try association(child)) }
            catch { unavailable.append(.init(derivedDataURL: child, reason: String(describing: error))) }
        }
        // A project mapped by multiple folders is ambiguous rather than silently combined.
        let counts = Dictionary(grouping: associations, by: { $0.projectURL.path }).mapValues(\.count)
        let verified = associations.filter { association in
            if counts[association.projectURL.path] == 1 { return true }
            unavailable.append(.init(derivedDataURL: association.derivedDataURL, reason: "Multiple DerivedData folders claim this project. Recheck its build locations."))
            return false
        }
        return .init(associations: verified, unavailable: unavailable)
    }

    private static func association(_ derived: URL) throws -> XcodeProjectAssociation {
        try directory(derived)
        let metadata = derived.appendingPathComponent("info.plist")
        let (bytes, observedIdentity) = try readMetadata(metadata)
        guard let dictionary = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as? [String: Any],
              Set(dictionary.keys) == Set(["WorkspacePath", "LastAccessedDate"]),
              dictionary["LastAccessedDate"] is Date,
              let path = dictionary["WorkspacePath"] as? String,
              path.hasPrefix("/"), !path.contains("\0") else {
            throw XcodeIntermediateFailure("Project association metadata is missing or has an unsupported schema.")
        }
        let project = URL(fileURLWithPath: path)
        guard project.path == path, !project.pathComponents.contains(".."), !project.pathComponents.contains("."), project.pathExtension == "xcodeproj" else {
            throw XcodeIntermediateFailure("This project/workspace association has not been qualified.")
        }
        try directory(project)
        let projectMetadata = project.appendingPathComponent("project.pbxproj")
        _ = try regular(projectMetadata, maximumSize: 32 * 1_024 * 1_024)
        let intermediate = derived.appendingPathComponent("Build/Intermediates.noindex", isDirectory: true)
        try directory(intermediate)
        var result = XcodeProjectAssociation(projectURL: project, derivedDataURL: derived, intermediateRootURL: intermediate,
                                              metadataURL: metadata, projectMetadataURLs: [projectMetadata])
        result.observedMetadataFingerprint = observedIdentity
        return result
    }

    private static func local(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .isUbiquitousItemKey])
        guard values.volumeIsLocal == true, !FileManager.default.isUbiquitousItem(at: url), values.isUbiquitousItem != true else {
            throw XcodeIntermediateFailure("Cloud, nonlocal or unknown project locations are unsupported.")
        }
    }
    private static func directory(_ url: URL) throws {
        guard url.isFileURL else { throw XcodeIntermediateFailure("Project location must be a file URL.") }
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            cursor.appendPathComponent(component)
            var ancestor = stat()
            guard lstat(cursor.path, &ancestor) == 0, ancestor.st_mode & S_IFMT == S_IFDIR,
                  ancestor.st_flags & UInt32(SF_DATALESS) == 0 else {
                throw XcodeIntermediateFailure("Project ancestry is unavailable, linked or not downloaded locally.")
            }
        }
        try local(url)
        let chain = try xcodeChain(url)
        guard let last = chain.last, last.fingerprint.uid == getuid() else {
            throw XcodeIntermediateFailure("Project directory ownership is unsupported.")
        }
        var s = stat()
        guard lstat(url.path, &s) == 0, s.st_flags & UInt32(SF_DATALESS) == 0 else {
            throw XcodeIntermediateFailure("Project directory is unavailable or not downloaded locally.")
        }
        try local(url)
    }
    private static func regular(_ url: URL, maximumSize: Int64) throws -> stat {
        try directory(url.deletingLastPathComponent())
        var s = stat()
        guard lstat(url.path, &s) == 0, s.st_mode & S_IFMT == S_IFREG, s.st_uid == getuid(),
              s.st_nlink == 1, s.st_size > 0, s.st_size <= maximumSize,
              s.st_flags & UInt32(SF_DATALESS) == 0 else {
            throw XcodeIntermediateFailure("Project metadata is unavailable, linked or unsupported.")
        }
        try local(url)
        return s
    }
    private static func readMetadata(_ url: URL) throws -> (Data, XcodeFingerprint) {
        let expected = XcodeFingerprint(try regular(url, maximumSize: 65_536))
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw XcodeIntermediateFailure("Project metadata could not be opened without following links.") }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, XcodeFingerprint(opened) == expected else {
            throw XcodeIntermediateFailure("Project metadata changed during inspection.")
        }
        var bytes = [UInt8](repeating: 0, count: Int(expected.size))
        var offset = 0
        while offset < bytes.count {
            let amount = bytes.withUnsafeMutableBytes { buffer in
                read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            }
            guard amount > 0 else { throw XcodeIntermediateFailure("Project metadata read was incomplete.") }
            offset += amount
        }
        var after = stat(); var named = stat()
        guard fstat(fd, &after) == 0, lstat(url.path, &named) == 0,
              XcodeFingerprint(after) == expected, XcodeFingerprint(named) == expected else {
            throw XcodeIntermediateFailure("Project metadata changed during inspection.")
        }
        return (Data(bytes), expected)
    }
}
