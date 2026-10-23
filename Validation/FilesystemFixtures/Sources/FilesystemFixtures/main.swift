import Darwin
import Foundation
import StillCore

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "FilesystemFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
private func metadata(_ url: URL) throws -> stat {
    var value = stat()
    try require(lstat(url.path, &value) == 0, "Missing owned fixture metadata")
    return value
}

private func scanEvidence(_ result: ScanResult) -> [String: Any] {
    ["scopePath": result.scope.path, "scopeURL": result.scope.absoluteString,
     "isComplete": result.isComplete, "logicalBytes": result.logicalBytes,
     "allocatedBytes": result.allocatedBytes as Any? ?? NSNull(),
     "totalLogicalBytes": result.totalLogicalBytes as Any? ?? NSNull(),
     "issues": result.issues.map { ["path": $0.url.path, "reason": $0.reason.rawValue] },
     "observations": result.observations.map { row -> [String: Any] in
         ["path": row.url.path, "url": row.url.absoluteString, "resourceID": row.resourceID,
          "kind": row.kind.rawValue, "logicalBytes": row.logicalBytes as Any? ?? NSNull(),
          "allocatedBytes": row.allocatedBytes as Any? ?? NSNull(), "locality": row.previewAvailability.rawValue]
     }]
}

private func matchesOwnedFixture(_ observation: FileObservation, _ expected: URL, _ native: stat) -> Bool {
    // Foundation can return /private/var observations for an explicit /var scope.
    // Compare both canonical paths and the exact native device/inode, never just a basename.
    observation.kind == .file
        && observation.url.resolvingSymlinksInPath().standardizedFileURL == expected.resolvingSymlinksInPath().standardizedFileURL
        && observation.resourceID == "\(native.st_dev):\(native.st_ino)"
}

private func nativeEvidence(_ info: stat) -> [String: Any] {
    ["device": info.st_dev, "inode": info.st_ino, "logicalBytes": info.st_size,
     "flags": info.st_flags, "allocatedBlocksBytes": Int64(info.st_blocks) * 512]
}

/// Invoked only by run.py after its ephemeral-runner and owned-image checks.
@main struct FilesystemFixtures {
    static func main() async throws {
        let args = CommandLine.arguments
        try require(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
            && ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted", "Hosted ephemeral CI only")
        try require(args.count == 6 && ["mounted", "unmounted"].contains(args[1]), "Expected phase, root, mounted device, parent device, report")
        let root = URL(fileURLWithPath: args[2], isDirectory: true).standardizedFileURL
        try require(root.lastPathComponent.hasPrefix("StillFilesystemFixtures-"), "Owned fixture root required")
        let mount = root.appendingPathComponent("mount", isDirectory: true)
        let scope = mount.appendingPathComponent("scope", isDirectory: true)
        let mountedDevice = Int32(args[3]), parentDevice = Int32(args[4])
        try require(mountedDevice != nil && parentDevice != nil && mountedDevice != parentDevice, "Distinct native devices required")
        var report: [String: Any] = ["phase": args[1], "hostOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "mountedDevice": mountedDevice!, "parentDevice": parentDevice!]
        let reportURL = URL(fileURLWithPath: args[5])
        // Persist synthetic-only evidence before a semantic assertion can terminate the process.
        // A diagnostic write failure itself must fail rather than discard the runtime evidence.
        func persist() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: reportURL, options: .atomic)
        }
        try persist()
        if args[1] == "mounted" {
            let actualRoot = try metadata(root), actualMount = try metadata(mount), actualScope = try metadata(scope)
            try require(actualRoot.st_dev == parentDevice && actualMount.st_dev == mountedDevice && actualScope.st_dev == mountedDevice,
                        "Volume identities changed before scan")
            let boundary = try await FolderScanner().scan(root)
            report["boundaryScan"] = scanEvidence(boundary)
            try persist()
            let explicit = try await FolderScanner().scan(scope)
            report["explicitScan"] = scanEvidence(explicit)
            let sentinel = scope.appendingPathComponent("sentinel.txt")
            let compressed = scope.appendingPathComponent("compressed.txt")
            let info = try metadata(compressed)
            let sentinelInfo = try metadata(sentinel)
            report["sentinelNative"] = nativeEvidence(sentinelInfo)
            report["compressedNative"] = nativeEvidence(info)
            report["expectedSentinelPath"] = sentinel.path
            report["expectedSentinelURL"] = sentinel.absoluteString
            report["expectedCompressedURL"] = compressed.absoluteString
            report["sentinelURLMatches"] = explicit.observations.map { $0.url == sentinel }
            report["sentinelCanonicalIdentityMatches"] = explicit.observations.map { matchesOwnedFixture($0, sentinel, sentinelInfo) }
            let compressedRow = explicit.observations.first { matchesOwnedFixture($0, compressed, info) }
            report["checks"] = [
                "boundaryReported": boundary.issues.contains { $0.reason == .differentVolume && $0.url.standardizedFileURL == mount },
                "noMountedDescendants": !boundary.observations.contains { $0.url.path.hasPrefix(mount.path + "/") },
                "boundaryTotalsUnknown": !boundary.isComplete && boundary.totalLogicalBytes == nil,
                "explicitScopeComplete": explicit.isComplete,
                "knownSentinelObserved": explicit.observations.contains { matchesOwnedFixture($0, sentinel, sentinelInfo) && $0.logicalBytes == 17 },
                "knownCompressedLogicalLength": compressedRow?.logicalBytes == 1_048_576,
                "positiveCompression": info.st_flags & UInt32(UF_COMPRESSED) != 0,
                "knownSmallerCompressedAllocation": compressedRow?.allocatedBytes.map { $0 < 1_048_576 } ?? false,
                "mountedIdentityRetained": try metadata(scope).st_dev == mountedDevice
            ]
            try persist()
            try require(boundary.issues.contains { $0.reason == .differentVolume && $0.url.standardizedFileURL == mount },
                        "Parent scan must report the genuine mounted-volume boundary")
            try require(!boundary.observations.contains { $0.url.path.hasPrefix(mount.path + "/") },
                        "Parent scan crossed the mounted volume")
            try require(!boundary.isComplete && boundary.totalLogicalBytes == nil, "Boundary must not produce complete totals")
            try require(explicit.isComplete && explicit.observations.contains { matchesOwnedFixture($0, sentinel, sentinelInfo) && $0.logicalBytes == 17 },
                        "Explicit mounted scope must observe the owned 17-byte sentinel")
            let row = explicit.observations.first { matchesOwnedFixture($0, compressed, info) }
            try require(row?.logicalBytes == 1_048_576, "Logical size must preserve the owned 1 MiB file")
            let flagged = info.st_flags & UInt32(UF_COMPRESSED) != 0
            let allocated = row?.allocatedBytes
            report["boundary"] = "passed"
            report["explicitMountedScope"] = "passed"
            report["compressedFlag"] = flagged
            report["compressedLogicalBytes"] = row?.logicalBytes
            report["compressedAllocatedBytes"] = allocated as Any? ?? NSNull()
            report["nativeCompressedBlocksBytes"] = Int64(info.st_blocks) * 512
            if flagged {
                try require(allocated != nil && allocated! < 1_048_576, "Flagged compressed fixture must have known smaller allocation")
                report["compression"] = "passed-positive-native-compression"
            } else {
                report["compression"] = "unsupported-no-UF_COMPRESSED; qualification-remains-open"
            }
            try require(try metadata(scope).st_dev == mountedDevice, "Volume disappeared during scan")
        } else {
            try require(!FileManager.default.fileExists(atPath: scope.path), "Owned mounted scope must disappear after detach")
            let missing = try await FolderScanner().scan(scope)
            report["disconnectedScan"] = scanEvidence(missing)
            try persist()
            try require(missing.observations.isEmpty && missing.issues.contains { $0.reason == .locationUnavailable }
                && missing.totalLogicalBytes == nil, "Disconnected scope must be unavailable with unknown total")
            report["disconnectedScope"] = "passed"
        }
        try persist()
    }
}
