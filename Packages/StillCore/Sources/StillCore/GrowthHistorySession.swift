import Foundation
import Observation

/// Metadata/persistence observation boundary; no content reads or scan initiation.
public protocol GrowthObservationRecording: Sendable {
    func begin(scope: URL) async throws -> GrowthScanToken
    func begin(scope: URL, exclusionFingerprint: String) async throws -> GrowthScanToken
    func complete(_ scan: ScanResult, token: GrowthScanToken) async throws -> GrowthComparison
}

public extension GrowthObservationRecording {
    func begin(scope: URL, exclusionFingerprint: String) async throws -> GrowthScanToken { try await begin(scope: scope) }
}

/// The actual presentation policy shared by native UI and controlled public-journey tests.
@MainActor @Observable public final class GrowthHistorySession {
    public private(set) var comparison: GrowthComparison?
    public private(set) var snapshots: [GrowthSnapshot] = []
    public private(set) var error: String?
    private let store: GrowthHistoryStore
    private let recorder: any GrowthObservationRecording
    private var active: UUID?
    private var attempt = UUID()
    private var presentationVersion = 0
    public init(store: GrowthHistoryStore, recorder: (any GrowthObservationRecording)? = nil) {
        self.store = store; self.recorder = recorder ?? GrowthScanRecorder(store: store)
    }
    public func load(now: Date = Date()) async {
        let request = attempt, version = presentationVersion
        let selected = comparison?.current?.id
        let unknownObservation = comparison?.state == .unknown && comparison?.current == nil && error == nil
        do {
            let result: GrowthComparison?
            if unknownObservation { result = comparison }
            else if let selected { result = try await store.comparison(id: selected, now: now) }
            else { result = try await store.latest(now: now) }
            let values = try await store.snapshots(now: now)
            guard attempt == request, presentationVersion == version, !Task.isCancelled else { return }
            comparison = result; snapshots = values; error = nil; presentationVersion += 1
        } catch {
            guard attempt == request, presentationVersion == version, !Task.isCancelled else { return }
            comparison = .unknown; self.error = "Comparison history is unavailable. No growth can be inferred from missing observations."; presentationVersion += 1
        }
    }
    public func begin(_ scope: URL, exclusionFingerprint: String = "none") async -> GrowthScanToken? {
        let request = UUID(); attempt = request; active = nil
        do {
            let token = try await recorder.begin(scope: scope, exclusionFingerprint: exclusionFingerprint)
            guard attempt == request, !Task.isCancelled else { return nil }
            active = token.id; return token
        } catch {
            guard attempt == request, !Task.isCancelled else { return nil }
            self.error = "Scope or volume identity could not be verified. This scan cannot establish a comparison baseline."; presentationVersion += 1
            return nil
        }
    }
    public func complete(_ scan: ScanResult, token: GrowthScanToken?) async {
        guard let token, active == token.id, !Task.isCancelled else { return }
        do {
            let result = try await recorder.complete(scan, token: token)
            guard active == token.id, !Task.isCancelled else { return }
            let values = try await store.snapshots()
            guard active == token.id, !Task.isCancelled else { return }
            var displayed = result.state == .unknown ? comparison : result
            if result.state == .unknown, let selected = comparison?.current?.id {
                displayed = try await store.comparison(id: selected)
            }
            guard active == token.id, !Task.isCancelled else { return }
            active = nil; comparison = displayed
            snapshots = values; error = nil; presentationVersion += 1
        } catch {
            guard active == token.id, !Task.isCancelled else { return }
            active = nil; self.error = "This observation could not be saved. No new baseline was recorded; current scan results remain usable."; presentationVersion += 1
        }
    }
    public func invalidateCoverage() async throws {
        cancelled()
        try await store.invalidateCoverage()
    }
    public func clearCompletedHistory() async throws {
        let request = UUID(); attempt = request; active = nil
        try await store.clearCompletedHistory()
        let result = try await store.latest()
        guard attempt == request, !Task.isCancelled else { return }
        snapshots = []; comparison = result; error = nil; presentationVersion += 1
    }
    public func resetHistory() async throws {
        let request = UUID(); attempt = request; active = nil
        try await store.resetHistory()
        let result = try await store.latest()
        guard attempt == request, !Task.isCancelled else { return }
        snapshots = []; comparison = result; error = nil; presentationVersion += 1
    }
    public func cancelled() { attempt = UUID(); active = nil; error = nil; presentationVersion += 1 }
    public func select(_ id: UUID, now: Date = Date()) async {
        let request = attempt, version = presentationVersion
        do {
            let result = try await store.comparison(id: id, now: now)
            guard attempt == request, presentationVersion == version, !Task.isCancelled else { return }
            comparison = result; error = nil; presentationVersion += 1
        } catch {
            guard attempt == request, presentationVersion == version, !Task.isCancelled else { return }
            comparison = .unknown; self.error = "The selected comparison is unavailable."; presentationVersion += 1
        }
    }
}
