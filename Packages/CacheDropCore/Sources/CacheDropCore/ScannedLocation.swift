import Foundation

/// A row of Overview's Scanned locations group (#345): one per scanned location, under the recommended categories, with the
/// location's name, the size its scan found and an Explore link. A location that can't be reached keeps its recovery row
/// near the top of Overview instead (#223, #231). The caller formats sizes with Overview's own byte formatter (#232).
public struct ScannedLocation: Equatable, Sendable {
    public let scope: URL
    public let name: String
    /// Built-in Downloads (#342): marked "Built in", never picked, with no Remove.
    public let isBuiltIn: Bool
    /// What the scan found on disk (allocated, as Explore storage's "On disk"; a sparse image counts what it uses, #376);
    /// nil until the location is scanned.
    public let bytes: Int64?
    /// False when the scan left something out, so `bytes` is a lower bound.
    public let complete: Bool
    /// What kept the scan from reading everything, with `action` as its fix (#358); nil when nothing did.
    public let problem: String?
    public let action: Action?

    public enum Action: Equatable, Sendable { case grantFullDiskAccess, scanAgain }

    public init(scope: URL, scan: ScanResult?, isBuiltIn: Bool = false) {
        self.scope = scope.standardizedFileURL
        name = scope.lastPathComponent
        self.isBuiltIn = isBuiltIn
        bytes = scan.map { $0.totalAllocatedBytes ?? $0.allocatedBytes ?? 0 }
        complete = scan?.totalAllocatedBytes != nil
        let issues = scan?.issues ?? []
        func count(_ reasons: Set<ScanIssue.Reason>) -> Int { Set(issues.filter { reasons.contains($0.reason) }.map(\.url.standardizedFileURL)).count }
        let denied = count([.accessDenied, .accessRevoked])
        let unread = count([.readFailed, .metadataUnavailable, .locationUnavailable, .exclusionUnavailable])
        let stopped = count([.timeLimit, .entryLimit, .issueLimit, .depthLimit, .directoryChanged]) > 0
        var parts: [String] = []
        if denied > 0 { parts.append(Self.count(denied, "folder") + " couldn’t be read") }
        if unread > 0 { parts.append(Self.count(unread, "item") + " couldn’t be read") }
        if stopped { parts.append("Scan stopped early") }
        problem = parts.isEmpty ? nil : parts.joined(separator: " · ")
        action = denied > 0 ? .grantFullDiskAccess : unread > 0 || stopped ? .scanAgain : nil
        // Left out on purpose or by design, so never a warning: the user's Exclusions, packages the scan lists without opening
        // (`hasUnmeasuredContents`: their contents aren't counted), special files and other volumes.
        let observations = scan?.observations ?? []
        let packages = observations.filter { $0.kind == .package }.count
        let special = observations.filter { $0.kind == .other }.count
        let volumes = count([.differentVolume])
        var notes: [String] = []
        if let excluded = scan?.excludedEntryCount, excluded > 0 { notes.append("\(excluded) excluded") }
        if packages > 0 { notes.append(Self.count(packages, "package") + " not measured") }
        if special > 0 { notes.append(Self.count(special, "special file") + " not measured") }
        if volumes > 0 { notes.append("\(volumes) on another volume") }
        self.notes = notes.isEmpty ? nil : notes.joined(separator: " · ")
    }
    /// What the scan left out on purpose (#358): neutral, with no action.
    public let notes: String?
    private static func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)" + (value == 1 ? "" : "s") }

    /// "12 MB", "At least 12 MB" when the scan left something out, or "Not scanned".
    public func value(_ format: (Int64) -> String) -> String {
        guard let bytes else { return "Not scanned" }
        return complete ? format(bytes) : "At least " + format(bytes)
    }
}
