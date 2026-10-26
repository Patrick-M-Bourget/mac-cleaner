import Foundation
import Darwin

public enum XcodeArtifactStatus: String, Codable, Sendable { case succeeded, failed, skipped, cancelled, notStarted, unknown }
public enum XcodeRunDisposition: String, Codable, Sendable { case completed, cancelled, safetyStopped, recoveryRequired, rejected }
public struct XcodeArtifactOutcome: Codable, Sendable {
    public let artifact: XcodeArtifact
    public internal(set) var status: XcodeArtifactStatus
    public internal(set) var removedBytes: Int64
    public internal(set) var reason: String?
    let approvedIdentity: XcodeFingerprint
}
public struct XcodeRun: Identifiable, Codable, Sendable {
    public let id: UUID
    public internal(set) var artifacts: [XcodeArtifactOutcome]
    public internal(set) var disposition: XcodeRunDisposition
    public internal(set) var stopReason: String?
    public internal(set) var unresolved: Bool
    public let approvedAt: Date
    public let observedAt: Date
}
public struct XcodeProgress: Sendable {
    public let resolved: Int
    public let total: Int
    public let last: XcodeArtifactOutcome
}
private enum XcodeLeafChanged: Error { case changed }

/// Holds an exact parent descriptor; no recursive removal or fresh enumeration at execution.
private final class XcodeOpenArtifact {
    var parent: Int32 = -1
    let authority: XcodeArtifactAuthority
    init(_ authority: XcodeArtifactAuthority) throws {
        self.authority = authority
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw XcodeIntermediateFailure("Build ancestry is unavailable.") }
        do {
            for item in authority.chain {
                let next = openat(fd, item.url.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw XcodeIntermediateFailure("Build ancestry changed or became inaccessible.") }
                close(fd); fd = next
                var info = stat()
                guard fstat(fd, &info) == 0, xcodeSameDirectory(XcodeFingerprint(info), item.fingerprint) else { throw XcodeIntermediateFailure("Build directory identity changed.") }
            }
            parent = fd
        } catch { close(fd); throw error }
    }
    deinit { if parent >= 0 { close(parent) } }
    func validateLeaf() throws {
        var info = stat()
        let name = URL(fileURLWithPath: authority.artifact.relativePath).lastPathComponent
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              XcodeFingerprint(info) == authority.leaf,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_uid == getuid(),
              info.st_flags & UInt32(SF_DATALESS | UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else { throw XcodeLeafChanged.changed }
    }
    func remove() throws {
        try validateLeaf()
        let name = URL(fileURLWithPath: authority.artifact.relativePath).lastPathComponent
        guard unlinkat(parent, name, 0) == 0 else { throw XcodeIntermediateFailure("The approved intermediate could not be removed.") }
    }
}
func xcodeSameDirectory(_ lhs: XcodeFingerprint, _ rhs: XcodeFingerprint) -> Bool {
    lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.uid == rhs.uid && lhs.mode == rhs.mode
}

extension XcodeIntermediates {
    public func execute(_ approval: XcodeArtifactApproval, cancellation: CleanupCancellation,
                        progress: @Sendable (XcodeProgress) async -> Void = { _ in }) async -> XcodeRun {
        var run = XcodeRun(id: approval.id, artifacts: approval.authorities.map { .init(artifact: $0.artifact, status: .notStarted, removedBytes: 0, reason: nil, approvedIdentity: $0.leaf) }, disposition: .rejected, stopReason: nil, unresolved: false, approvedAt: approval.approvedAt, observedAt: environment.now())
        guard !executing, approval.sessionID == sessionID, approval.generation == generation else { run.stopReason = "Approval is stale or belongs to another session."; return run }
        executing = true; generation = UUID()
        defer { executing = false }
        var archive: [XcodeRun] = []
        var lease: XcodeJournalLease?
        do {
            lease = try XcodeJournalLease(journalURL)
            archive = try records()
            guard !archive.contains(where: { $0.id == approval.id || $0.unresolved }) else { throw XcodeIntermediateFailure("This operation is consumed or unresolved cleanup requires review.") }
            run.disposition = .recoveryRequired; run.unresolved = true
            archive.append(run)
            try persistXcode(archive)
        } catch { run.stopReason = String(describing: error); run.disposition = .rejected; return run }
        defer { withExtendedLifetime(lease) {} }
        for (index, authority) in approval.authorities.enumerated() {
            if cancellation.isCancelled {
                run.disposition = .cancelled; run.stopReason = "Stopped by the user."
                for rest in index..<run.artifacts.count { run.artifacts[rest].status = .cancelled; run.artifacts[rest].reason = run.stopReason }
                break
            }
            do { try validateXcodeScope(authority) } catch {
                run.disposition = .safetyStopped; run.stopReason = String(describing: error)
                for rest in index..<run.artifacts.count { run.artifacts[rest].reason = run.stopReason }
                break
            }
            let opened: XcodeOpenArtifact
            do { opened = try XcodeOpenArtifact(authority) } catch {
                run.disposition = .safetyStopped; run.stopReason = String(describing: error)
                for rest in index..<run.artifacts.count { run.artifacts[rest].reason = run.stopReason }
                break
            }
            do { try opened.validateLeaf() } catch {
                run.artifacts[index].status = .skipped; run.artifacts[index].reason = "The exact approved artifact changed or disappeared."
                do { archive[archive.count - 1] = run; try persistXcode(archive) } catch { run.stopReason = "Cleanup outcome could not be recorded."; run.disposition = .recoveryRequired; return run }
                await progress(.init(resolved: index + 1, total: run.artifacts.count, last: run.artifacts[index])); continue
            }
            run.artifacts[index].status = .unknown
            do { archive[archive.count - 1] = run; try persistXcode(archive) } catch { run.artifacts[index].status = .notStarted; run.stopReason = "Cleanup intent could not be recorded. Nothing further was started."; run.disposition = .recoveryRequired; return run }
            // Check Stop and scope again after durable intent, immediately before the exact leaf action.
            if cancellation.isCancelled {
                run.artifacts[index].status = .cancelled
                run.disposition = .cancelled; run.stopReason = "Stopped by the user."
                for rest in index..<run.artifacts.count { run.artifacts[rest].status = .cancelled; run.artifacts[rest].reason = run.stopReason }
                break
            }
            do { try validateXcodeScope(authority) } catch {
                run.artifacts[index].status = .notStarted; run.disposition = .safetyStopped; run.stopReason = String(describing: error)
                for rest in index..<run.artifacts.count { run.artifacts[rest].reason = run.stopReason }
                break
            }
            do {
                try opened.remove(); run.artifacts[index].status = .succeeded
                run.artifacts[index].removedBytes = authority.artifact.logicalBytes
            } catch is XcodeLeafChanged {
                run.artifacts[index].status = .skipped; run.artifacts[index].reason = "The exact approved artifact changed or disappeared."
            } catch {
                run.artifacts[index].status = .failed; run.artifacts[index].reason = String(describing: error)
            }
            do { archive[archive.count - 1] = run; try persistXcode(archive) } catch { run.artifacts[index].status = .unknown; run.artifacts[index].removedBytes = 0; run.stopReason = "Cleanup outcome could not be recorded."; run.disposition = .recoveryRequired; return run }
            await progress(.init(resolved: index + 1, total: run.artifacts.count, last: run.artifacts[index]))
        }
        if run.disposition == .recoveryRequired { run.disposition = .completed }
        run.unresolved = false
        do { archive[archive.count - 1] = run; try persistXcode(archive) } catch { run.unresolved = true; run.disposition = .recoveryRequired; run.stopReason = "Final cleanup outcomes could not be recorded." }
        return run
    }
    func validateXcodeApprovalLeaf(_ authority: XcodeArtifactAuthority) throws { try XcodeOpenArtifact(authority).validateLeaf() }
    func validateXcodeScope(_ authority: XcodeArtifactAuthority) throws {
        try environment.validateInstallation()
        guard try environment.standardDerivedDataURL().path == authority.root.path else { throw XcodeIntermediateFailure("DerivedData scope changed.") }
        let owner = try environment.ownerObservation()
        guard owner.activity == .closed else { throw XcodeIntermediateFailure(owner.reason ?? "Xcode or a build owner is running or could not be checked.") }
        for proof in authority.proofs {
            let current = try xcodeProof(proof.url)
            guard current.fingerprint == proof.fingerprint else { throw XcodeIntermediateFailure("Project association evidence changed.") }
        }
        let current = try xcodeChain(authority.chain.last!.url)
        guard current.count == authority.chain.count, zip(current, authority.chain).allSatisfy({ xcodeSameDirectory($0.fingerprint, $1.fingerprint) }) else { throw XcodeIntermediateFailure("Build directory scope changed.") }
    }
}
