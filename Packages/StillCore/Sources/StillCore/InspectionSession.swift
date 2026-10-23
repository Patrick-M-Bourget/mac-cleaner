import Foundation

public struct ScopeReport: Sendable {
    public let current: ScanResult
    public let lastComplete: ScanResult?
    public var requiresRecheck: Bool { !current.isComplete }
}

/// Independently selected locations retain their own observations and recovery status.
public actor InspectionSession {
    private let scanner: FolderScanner
    private var saved: [URL: ScopeReport] = [:]
    public init(scanner: FolderScanner = FolderScanner()) { self.scanner = scanner }
    public func inspect(_ scope: URL) async throws -> ScopeReport {
        let current = try await scanner.scan(scope)
        let report = ScopeReport(current: current, lastComplete: current.isComplete ? current : saved[scope]?.lastComplete)
        saved[scope] = report
        return report
    }
    public func reports() -> [ScopeReport] { saved.values.sorted { $0.current.scope.path < $1.current.scope.path } }
}
