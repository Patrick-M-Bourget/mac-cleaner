import Foundation
import Darwin
import CryptoKit
import MachO

public enum XcodeOwnerActivity: String, Codable, Sendable { case closed, running, unknown }
public struct XcodeOwnerObservation: Sendable {
    public let activity: XcodeOwnerActivity
    public let reason: String?
    public init(activity: XcodeOwnerActivity, reason: String? = nil) { self.activity = activity; self.reason = reason }
}
public struct XcodeProjectAssociation: Sendable {
    public let projectURL: URL
    public let derivedDataURL: URL
    public let intermediateRootURL: URL
    public let metadataURL: URL
    public let projectMetadataURLs: [URL]
    var observedMetadataFingerprint: XcodeFingerprint?
    public init(projectURL: URL, derivedDataURL: URL, intermediateRootURL: URL, metadataURL: URL, projectMetadataURLs: [URL] = []) {
        self.projectURL = projectURL; self.derivedDataURL = derivedDataURL
        self.intermediateRootURL = intermediateRootURL; self.metadataURL = metadataURL; self.projectMetadataURLs = projectMetadataURLs
    }
}
public struct XcodeUnavailableProject: Sendable {
    public let derivedDataURL: URL
    public let reason: String
    public init(derivedDataURL: URL, reason: String) { self.derivedDataURL = derivedDataURL; self.reason = reason }
}
public struct XcodeProjectMapping: Sendable {
    public let associations: [XcodeProjectAssociation]
    public let unavailable: [XcodeUnavailableProject]
    public init(associations: [XcodeProjectAssociation], unavailable: [XcodeUnavailableProject] = []) { self.associations = associations; self.unavailable = unavailable }
}
/// Native and disposable adapters verify installation, mapping and owner observations.
/// No caller-provided URL or activity boolean confers production mutation authority.
public protocol XcodeBuildEnvironment: Sendable {
    func validateInstallation() throws
    func standardDerivedDataURL() throws -> URL
    func ownerObservation() throws -> XcodeOwnerObservation
    func projects(in root: URL) throws -> XcodeProjectMapping
    func now() -> Date
}
public struct XcodeArtifact: Identifiable, Codable, Sendable {
    public let id: String
    public let projectURL: URL
    public let url: URL
    public let relativePath: String
    public let logicalBytes: Int64
    public let observedAt: Date
}
public struct XcodeProjectFinding: Sendable {
    public let projectURL: URL
    public let artifacts: [XcodeArtifact]
    public let unavailableReason: String?
}
public struct XcodeInspection: Sendable {
    public let projects: [XcodeProjectFinding]
    public let owner: XcodeOwnerObservation
    public let unavailableProjects: [XcodeUnavailableProject]
    public let unavailableReason: String?
    public let observedAt: Date
}
public struct XcodeArtifactApproval: Sendable {
    public let id: UUID
    public let artifacts: [XcodeArtifact]
    public let approvedAt: Date
    let sessionID: UUID
    let generation: UUID
    let authorities: [XcodeArtifactAuthority]
}
public struct XcodeIntermediateFailure: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
struct XcodeFingerprint: Codable, Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let uid: UInt32
    let mode: UInt16
    let links: UInt16
    let size: Int64
    let modified: Int64
    let modifiedNanos: Int64
    let changed: Int64
    let changedNanos: Int64
    init(_ s: stat) {
        device = s.st_dev; inode = s.st_ino; uid = s.st_uid; mode = s.st_mode; links = s.st_nlink; size = s.st_size
        modified = Int64(s.st_mtimespec.tv_sec); modifiedNanos = Int64(s.st_mtimespec.tv_nsec)
        changed = Int64(s.st_ctimespec.tv_sec); changedNanos = Int64(s.st_ctimespec.tv_nsec)
    }
}
struct XcodePathIdentity: Sendable { let url: URL; let fingerprint: XcodeFingerprint }
struct XcodeArtifactAuthority: Sendable {
    let artifact: XcodeArtifact
    let root: URL
    let chain: [XcodePathIdentity]
    let proofs: [XcodePathIdentity]
    let leaf: XcodeFingerprint
}
public actor XcodeIntermediates {
    let environment: any XcodeBuildEnvironment
    let journalURL: URL
    let sessionID = UUID()
    var generation = UUID()
    var authorities: [String: XcodeArtifactAuthority] = [:]
    var executing = false
    public init(environment: any XcodeBuildEnvironment, journalURL: URL) { self.environment = environment; self.journalURL = journalURL }
    public func inspectStandardDerivedData() -> XcodeInspection {
        let now = environment.now()
        guard !executing else { return .init(projects: [], owner: .init(activity: .unknown), unavailableProjects: [], unavailableReason: "Cleanup is in progress.", observedAt: now) }
        generation = UUID(); authorities = [:]
        do {
            try environment.validateInstallation()
            let root = try environment.standardDerivedDataURL()
            _ = try xcodeChain(root)
            let mapping = try environment.projects(in: root)
            let associations = mapping.associations
            guard associations.count <= 1_000 else { throw XcodeIntermediateFailure("Project inventory exceeds the supported limit.") }
            var findings: [XcodeProjectFinding] = []
            for association in associations {
                do {
                    let artifacts = try inspect(association, root: root, at: now)
                    findings.append(.init(projectURL: association.projectURL, artifacts: artifacts, unavailableReason: nil))
                } catch { findings.append(.init(projectURL: association.projectURL, artifacts: [], unavailableReason: String(describing: error))) }
            }
            let owner: XcodeOwnerObservation
            do { owner = try environment.ownerObservation() } catch { owner = .init(activity: .unknown, reason: "Build activity could not be verified.") }
            return .init(projects: findings, owner: owner, unavailableProjects: mapping.unavailable, unavailableReason: nil, observedAt: now)
        } catch { return .init(projects: [], owner: .init(activity: .unknown), unavailableProjects: [], unavailableReason: String(describing: error), observedAt: now) }
    }
    public func approve(artifactIDs: Set<String>) throws -> XcodeArtifactApproval {
        guard !executing, !artifactIDs.isEmpty, artifactIDs.isSubset(of: Set(authorities.keys)), try environment.ownerObservation().activity == .closed else { throw XcodeIntermediateFailure("Close Xcode and build tools, then recheck the selected artifacts.") }
        try environment.validateInstallation()
        let targets = artifactIDs.compactMap { authorities[$0] }.sorted { $0.artifact.id < $1.artifact.id }
        for target in targets { try validateXcodeScope(target); try validateXcodeApprovalLeaf(target) }
        return .init(id: UUID(), artifacts: targets.map(\.artifact), approvedAt: environment.now(), sessionID: sessionID, generation: generation, authorities: targets)
    }
    private func inspect(_ association: XcodeProjectAssociation, root: URL, at date: Date) throws -> [XcodeArtifact] {
        let expected = association.derivedDataURL.appendingPathComponent("Build/Intermediates.noindex")
        guard association.derivedDataURL.deletingLastPathComponent().path == root.path, association.intermediateRootURL.path == expected.path,
              association.metadataURL.deletingLastPathComponent().path == association.derivedDataURL.path else { throw XcodeIntermediateFailure("Project build layout is unsupported.") }
        let proofs = try ([association.metadataURL, association.projectURL] + association.projectMetadataURLs).map { try xcodeProof($0) }
        if let observed = association.observedMetadataFingerprint {
            guard proofs.first?.fingerprint == observed else { throw XcodeIntermediateFailure("Project mapping metadata changed after observation.") }
        }
        let rootDevice = try xcodeProof(root).fingerprint.device
        let intermediateChain = try xcodeChain(expected)
        guard intermediateChain.filter({ $0.url.path == root.path || $0.url.path.hasPrefix(root.path + "/") }).allSatisfy({ $0.fingerprint.device == rootDevice }) else { throw XcodeIntermediateFailure("Cross-volume build scopes are unsupported.") }
        var enumerationFailed = false
        guard let walker = FileManager.default.enumerator(at: expected, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw XcodeIntermediateFailure("Build inventory is unavailable.") }
        var result: [XcodeArtifact] = []; var pending: [String: XcodeArtifactAuthority] = [:]; var count = 0
        while let url = walker.nextObject() as? URL {
            count += 1; guard count <= 100_000 else { throw XcodeIntermediateFailure("Build inventory exceeds the supported limit.") }
            var s = stat(); guard lstat(url.path, &s) == 0 else { throw XcodeIntermediateFailure("Build inventory changed.") }
            if s.st_mode & S_IFMT == S_IFLNK { walker.skipDescendants(); continue }
            let relative = String(url.path.dropFirst(expected.path.count + 1)); let parts = relative.split(separator: "/").map(String.init)
            if parts.contains(where: { ["SourcePackages", "Index.noindex", "ModuleCache.noindex"].contains($0) || ["dSYM", "xcarchive", "app", "framework", "bundle"].contains(URL(fileURLWithPath: $0).pathExtension) }) { walker.skipDescendants(); continue }
            guard s.st_mode & S_IFMT == S_IFREG, url.pathExtension == "o", parts.count == 6,
                  parts[0].hasSuffix(".build"), parts[2].hasSuffix(".build"), parts[3] == "Objects-normal", parts[4] == "arm64" else { continue }
            guard s.st_dev == rootDevice, s.st_uid == getuid(), s.st_nlink == 1, s.st_flags & UInt32(SF_DATALESS | UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else { continue }
            let chain = try xcodeChain(url.deletingLastPathComponent())
            let leaf = XcodeFingerprint(s)
            guard try xcodeIsQualifiedObject(url, expected: leaf) else { continue }
            let key = url.path + "|" + String(describing: leaf)
            let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            let artifact = XcodeArtifact(id: id, projectURL: association.projectURL, url: url, relativePath: String(url.path.dropFirst(root.path.count + 1)), logicalBytes: s.st_size, observedAt: date)
            pending[id] = .init(artifact: artifact, root: root, chain: chain, proofs: proofs, leaf: leaf)
            result.append(artifact)
        }
        guard !enumerationFailed else { throw XcodeIntermediateFailure("Build inventory is incomplete.") }
        for (id, authority) in pending { authorities[id] = authority }
        return result
    }
}
func xcodeProof(_ url: URL) throws -> XcodePathIdentity {
    try xcodeLocalLocation(url)
    _ = try xcodeChain(url.deletingLastPathComponent())
    var s = stat(); guard lstat(url.path, &s) == 0, s.st_uid == getuid(), s.st_mode & S_IFMT != S_IFLNK else { throw XcodeIntermediateFailure("Project proof is unavailable.") }
    return .init(url: url, fingerprint: .init(s))
}
func xcodeChain(_ url: URL) throws -> [XcodePathIdentity] {
    try xcodeLocalLocation(url)
    guard url.isFileURL, !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { throw XcodeIntermediateFailure("Noncanonical build location.") }
    var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC); guard fd >= 0 else { throw XcodeIntermediateFailure("Build location is unavailable.") }
    defer { close(fd) }
    var path = URL(fileURLWithPath: "/"); var chain: [XcodePathIdentity] = []
    for part in url.pathComponents.dropFirst() {
        let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw XcodeIntermediateFailure("Build directory is inaccessible or linked: \(path.appendingPathComponent(part).path), errno \(errno).") }
        close(fd); fd = next; path.appendPathComponent(part)
        var s = stat(); guard fstat(fd, &s) == 0, s.st_flags & UInt32(SF_DATALESS) == 0 else { throw XcodeIntermediateFailure("Build directory changed.") }
        chain.append(.init(url: path, fingerprint: .init(s)))
    }
    guard chain.last?.fingerprint.uid == getuid(), chain.last!.fingerprint.mode & 0o022 == 0 else { throw XcodeIntermediateFailure("Build root ownership is unsupported.") }
    return chain
}

/// Metadata only: never opens a placeholder's contents or requests materialization.
func xcodeLocalLocation(_ url: URL) throws {
    guard url.isFileURL, !url.path.contains("/Library/CloudStorage/"), !url.path.contains("/Library/Mobile Documents/") else { throw XcodeIntermediateFailure("Cloud/provider build locations are unsupported.") }
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK, info.st_flags & UInt32(SF_DATALESS) == 0 else { throw XcodeIntermediateFailure("Build metadata is unavailable, linked or a placeholder.") }
    let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey])
    guard values.volumeIsLocal == true, values.isUbiquitousItem != true, !FileManager.default.isUbiquitousItem(at: url) else { throw XcodeIntermediateFailure("Build cleanup requires a local non-cloud location.") }
    var final = stat()
    guard lstat(url.path, &final) == 0, XcodeFingerprint(final) == XcodeFingerprint(info) else { throw XcodeIntermediateFailure("Build metadata changed during inspection.") }
}

/// Candidate arm64 MH_OBJECT recipe from the SDK loader.h/machine.h. Native
/// qualification must observe this same format before an installed adapter enables it.
private func xcodeIsQualifiedObject(_ url: URL, expected: XcodeFingerprint) throws -> Bool {
    try xcodeLocalLocation(url)
    let fd = try xcodeOpenObject(url)
    guard fd >= 0 else { throw XcodeIntermediateFailure("Object metadata could not be verified.") }
    defer { close(fd) }
    var opened = stat()
    guard fstat(fd, &opened) == 0, XcodeFingerprint(opened) == expected else { throw XcodeIntermediateFailure("Object identity changed.") }
    let header = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: 32) ?? Data()
    var final = stat()
    guard fstat(fd, &final) == 0, XcodeFingerprint(final) == expected else { throw XcodeIntermediateFailure("Object changed during format observation.") }
    guard header.count == 32 else { return false }
    let bytes = Array(header)
    func word(_ index: Int) -> UInt32 {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }
    return word(0) == MH_MAGIC_64 && word(4) == UInt32(CPU_TYPE_ARM64) && word(8) == UInt32(CPU_SUBTYPE_ARM64_ALL)
        && word(12) == UInt32(MH_OBJECT) && word(16) > 0 && word(16) <= 1024
        && word(20) >= word(16) * 8 && word(20) <= 1_048_576 && Int64(word(20)) + 32 <= expected.size
}

private func xcodeOpenObject(_ url: URL) throws -> Int32 {
    var parent = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard parent >= 0 else { throw XcodeIntermediateFailure("Object ancestry is unavailable.") }
    defer { close(parent) }
    for part in url.deletingLastPathComponent().pathComponents.dropFirst() {
        let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw XcodeIntermediateFailure("Object ancestry changed or is linked.") }
        close(parent); parent = next
    }
    return openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
}
