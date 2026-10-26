import Foundation
import Darwin
import CryptoKit

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
    public init(projectURL: URL, derivedDataURL: URL, intermediateRootURL: URL, metadataURL: URL) {
        self.projectURL = projectURL; self.derivedDataURL = derivedDataURL
        self.intermediateRootURL = intermediateRootURL; self.metadataURL = metadataURL
    }
}
/// Native and disposable adapters verify installation, mapping and owner observations.
/// No caller-provided URL or activity boolean confers production mutation authority.
public protocol XcodeBuildEnvironment: Sendable {
    func validateInstallation() throws
    func standardDerivedDataURL() throws -> URL
    func ownerObservation() throws -> XcodeOwnerObservation
    func projects(in root: URL) throws -> [XcodeProjectAssociation]
    func now() -> Date
}
public struct XcodeArtifact: Identifiable, Codable, Sendable {
    public let id: String
    public let projectURL: URL
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
        guard !executing else { return .init(projects: [], owner: .init(activity: .unknown), unavailableReason: "Cleanup is in progress.", observedAt: now) }
        generation = UUID(); authorities = [:]
        do {
            try environment.validateInstallation()
            let root = try environment.standardDerivedDataURL()
            _ = try xcodeChain(root)
            let associations = try environment.projects(in: root)
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
            return .init(projects: findings, owner: owner, unavailableReason: nil, observedAt: now)
        } catch { return .init(projects: [], owner: .init(activity: .unknown), unavailableReason: String(describing: error), observedAt: now) }
    }
    public func approve(artifactIDs: Set<String>) throws -> XcodeArtifactApproval {
        guard !executing, !artifactIDs.isEmpty, artifactIDs.isSubset(of: Set(authorities.keys)), try environment.ownerObservation().activity == .closed else { throw XcodeIntermediateFailure("Close Xcode and build tools, then recheck the selected artifacts.") }
        try environment.validateInstallation()
        let targets = artifactIDs.compactMap { authorities[$0] }.sorted { $0.artifact.id < $1.artifact.id }
        return .init(id: UUID(), artifacts: targets.map(\.artifact), approvedAt: environment.now(), sessionID: sessionID, generation: generation, authorities: targets)
    }
    private func inspect(_ association: XcodeProjectAssociation, root: URL, at date: Date) throws -> [XcodeArtifact] {
        let expected = association.derivedDataURL.appendingPathComponent("Build/Intermediates.noindex")
        guard association.derivedDataURL.deletingLastPathComponent() == root, association.intermediateRootURL == expected,
              association.metadataURL.deletingLastPathComponent() == association.derivedDataURL else { throw XcodeIntermediateFailure("Project build layout is unsupported.") }
        let proofs = try [association.metadataURL, association.projectURL].map { try xcodeProof($0) }
        _ = try xcodeChain(expected)
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
                  parts[0].hasSuffix(".build"), parts[2].hasSuffix(".build"), parts[3] == "Objects-normal" else { continue }
            guard s.st_uid == getuid(), s.st_nlink == 1, s.st_flags & UInt32(SF_DATALESS | UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else { continue }
            let chain = try xcodeChain(url.deletingLastPathComponent())
            let leaf = XcodeFingerprint(s)
            let key = url.path + "|" + String(describing: leaf)
            let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            let artifact = XcodeArtifact(id: id, projectURL: association.projectURL, relativePath: String(url.path.dropFirst(root.path.count + 1)), logicalBytes: s.st_size, observedAt: date)
            pending[id] = .init(artifact: artifact, root: root, chain: chain, proofs: proofs, leaf: leaf)
            result.append(artifact)
        }
        guard !enumerationFailed else { throw XcodeIntermediateFailure("Build inventory is incomplete.") }
        for (id, authority) in pending { authorities[id] = authority }
        return result
    }
}
func xcodeProof(_ url: URL) throws -> XcodePathIdentity {
    _ = try xcodeChain(url.deletingLastPathComponent())
    var s = stat(); guard lstat(url.path, &s) == 0, s.st_uid == getuid(), s.st_mode & S_IFMT != S_IFLNK else { throw XcodeIntermediateFailure("Project proof is unavailable.") }
    return .init(url: url, fingerprint: .init(s))
}
func xcodeChain(_ url: URL) throws -> [XcodePathIdentity] {
    guard url.isFileURL, !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { throw XcodeIntermediateFailure("Noncanonical build location.") }
    var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC); guard fd >= 0 else { throw XcodeIntermediateFailure("Build location is unavailable.") }
    defer { close(fd) }
    var path = URL(fileURLWithPath: "/"); var chain: [XcodePathIdentity] = []
    for part in url.pathComponents.dropFirst() {
        let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw XcodeIntermediateFailure("Build directory is inaccessible or linked: \(path.appendingPathComponent(part).path), errno \(errno).") }
        close(fd); fd = next; path.appendPathComponent(part)
        var s = stat(); guard fstat(fd, &s) == 0 else { throw XcodeIntermediateFailure("Build directory changed.") }
        chain.append(.init(url: path, fingerprint: .init(s)))
    }
    guard chain.last?.fingerprint.uid == getuid() else { throw XcodeIntermediateFailure("Build root ownership is unsupported.") }
    return chain
}
