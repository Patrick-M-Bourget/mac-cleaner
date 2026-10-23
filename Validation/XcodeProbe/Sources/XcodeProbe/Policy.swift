import Foundation
public enum XcodePolicy {
    public static func guidance(version: String, ownerInactive: Bool?) -> String? {
        guard version == "27.1" else { return "Unvalidated Xcode version" }
        return ownerInactive == true ? nil : "Owner active or unknown"
    }
}

/// Disposable-only harness. No API accepts a real cleanup root.
public final class DisposableXcodeProbe {
    public let root: URL
    private let fm = FileManager.default
    public init() throws {
        let candidate = fm.temporaryDirectory.appendingPathComponent("still-xcode-probe-" + UUID().uuidString)
        try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
        root = candidate.resolvingSymlinksInPath()
    }
    deinit { try? fm.removeItem(at: root) }
    public func seed(_ path: String, text: String = "sentinel") throws {
        let url = try fixtureURL(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    public func contents(_ path: String) throws -> String { try String(contentsOf: fixtureURL(path), encoding: .utf8) }
    public func exists(_ path: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(path).path) }
    public func link(_ path: String, to destination: String) throws {
        let url = try fixtureURL(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: url.path, withDestinationPath: root.appendingPathComponent(destination).path)
    }
    public struct Approval {
        fileprivate let root: URL
        fileprivate let fingerprints: [String: String]
    }
    public func approve(version: String, ownerInactive: Bool?) throws -> Approval {
        guard XcodePolicy.guidance(version: version, ownerInactive: ownerInactive) == nil else { throw ProbeError.guidance }
        var targets: [String: String] = [:]
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { throw ProbeError.guidance }
        for case let url as URL in entries {
            guard let index = url.pathComponents.firstIndex(of: root.lastPathComponent) else { throw ProbeError.guidance }
            let path = url.pathComponents.dropFirst(index + 1).joined(separator: "/")
            if eligible(path), let signature = try? fingerprint(path) { targets[path] = signature }
        }
        return Approval(root: root, fingerprints: targets)
    }
    public struct Outcome: Equatable {
        public let removed: [String]
        public let skipped: [String]
        public let notStarted: [String]
    }
    private var consumed = Set<UUID>()
    public struct Run {
        fileprivate let id: UUID
        fileprivate let approval: Approval
    }
    public func prepare(_ approval: Approval) -> Run { Run(id: UUID(), approval: approval) }
    public func execute(_ run: Run, ownerInactive: Bool?, stopAfter: Int = .max) throws -> Outcome {
        guard run.approval.root == root, ownerInactive == true, !consumed.contains(run.id) else { throw ProbeError.guidance }
        consumed.insert(run.id)
        var removed: [String] = [], skipped: [String] = [], notStarted: [String] = []
        for path in run.approval.fingerprints.keys.sorted() {
            guard removed.count + skipped.count < stopAfter else { notStarted.append(path); continue }
            guard (try? fingerprint(path)) == run.approval.fingerprints[path] else { skipped.append(path); continue }
            // Fixture only: this path-based operation is NOT a production race-safe executor.
            do { try fm.removeItem(at: fixtureURL(path)); removed.append(path) }
            catch { skipped.append(path) }
        }
        return Outcome(removed: removed, skipped: skipped, notStarted: notStarted)
    }
    private func eligible(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[0] == "DerivedData", parts[1].hasPrefix("Probe-"),
              parts[2] == "Build", parts[3] == "Intermediates.noindex", path.hasSuffix(".o") else { return false }
        return !parts.contains { $0.hasSuffix(".dSYM") || $0.hasSuffix(".xcarchive") || $0.hasSuffix(".app") || $0 == "SourcePackages" || $0 == "Sources" }
    }
    private func fingerprint(_ path: String) throws -> String {
        let url = try fixtureURL(path)
        let a = try fm.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeRegular else { throw ProbeError.guidance }
        return "\(a[.systemNumber]!)|\(a[.systemFileNumber]!)|\(a[.size]!)|\((a[.modificationDate] as! Date).timeIntervalSince1970)|\((a[.creationDate] as! Date).timeIntervalSince1970)"
    }
    private func fixtureURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw ProbeError.guidance }
        var current = root
        for part in parts {
            current.appendPathComponent(String(part))
            if let a = try? fm.attributesOfItem(atPath: current.path), a[.type] as? FileAttributeType == .typeSymbolicLink { throw ProbeError.guidance }
        }
        return current
    }
    public enum ProbeError: Error { case guidance }
}
