import Foundation

public enum DiagnosticsArchitecture: String, Encodable, Sendable { case arm64, x86_64, unknown }
public enum DiagnosticsScanStatus: String, Encodable, Sendable { case notInspected, scanning, complete, partial }
public enum DiagnosticsCleanupStatus: String, Encodable, Sendable { case idle, running, complete, partial, unknown }
public enum DiagnosticsRecoveryStatus: String, Encodable, Sendable { case notLoaded, clear, requiresReview, unavailable }
public enum DiagnosticsCode: String, Encodable, Sendable { case scanIncomplete, outcomeUnknown, journalUnavailable }

/// Immutable, explicitly reviewed allowlist. No source records, raw errors or paths are accepted.
public struct DiagnosticsReview: Sendable {
    public let payload: Data
    public var text: String { String(decoding: payload, as: UTF8.self) }
    public init(appVersion: String?, build: String?, system: OperatingSystemVersion, architecture: DiagnosticsArchitecture,
                scopeCount: Int, observedCount: Int, selectedCount: Int, scan: DiagnosticsScanStatus,
                cleanup: DiagnosticsCleanupStatus, recovery: DiagnosticsRecoveryStatus, errors: Set<DiagnosticsCode>) throws {
        func version(_ value: String?) -> String {
            guard let value, value.count <= 32, value.range(of: "^[0-9]+(?:\\.[0-9]+){0,3}$", options: .regularExpression) != nil else { return "Unknown" }
            return value
        }
        struct Payload: Encodable {
            let schema = 1
            let appVersion: String, build: String, systemVersion: String
            let architecture: DiagnosticsArchitecture
            let scopeCount: Int, observedCount: Int, selectedCount: Int
            let scan: DiagnosticsScanStatus
            let cleanup: DiagnosticsCleanupStatus
            let recovery: DiagnosticsRecoveryStatus
            let errors: [DiagnosticsCode]
        }
        let value = Payload(appVersion: version(appVersion), build: version(build), systemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)", architecture: architecture,
                            scopeCount: max(0, scopeCount), observedCount: max(0, observedCount), selectedCount: max(0, selectedCount), scan: scan, cleanup: cleanup, recovery: recovery, errors: errors.sorted { $0.rawValue < $1.rawValue })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        payload = try encoder.encode(value)
    }
}

public enum DiagnosticsSaveOutcome: Sendable { case notSaved, cancelled, failed, saved }
/// The approved payload survives cancellation and write failure; saving never reads recovery records.
public struct DiagnosticsExport: Sendable {
    public let review: DiagnosticsReview
    public private(set) var outcome: DiagnosticsSaveOutcome = .notSaved
    private let protectedDirectory: URL?
    public init(review: DiagnosticsReview, protectedDirectory: URL?) { self.review = review; self.protectedDirectory = protectedDirectory }
    @discardableResult public mutating func save(to destination: URL?) -> DiagnosticsSaveOutcome {
        guard let destination else { outcome = .cancelled; return outcome }
        guard destination.isFileURL, let protectedDirectory, protectedDirectory.isFileURL else { outcome = .failed; return outcome }
        let roots = [protectedDirectory.standardizedFileURL, protectedDirectory.resolvingSymlinksInPath().standardizedFileURL]
        let destinations = [destination.standardizedFileURL, destination.resolvingSymlinksInPath().standardizedFileURL]
        guard !destinations.contains(where: { candidate in roots.contains { candidate.pathComponents.starts(with: $0.pathComponents) } }) else { outcome = .failed; return outcome }
        do { try review.payload.write(to: destination, options: .atomic); outcome = .saved }
        catch { outcome = .failed }
        return outcome
    }
}
