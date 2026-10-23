import Foundation

/// A scope refresh retains its original choices until complete metadata can revalidate them.
public struct RefreshRequest: Sendable {
    public let id: UUID
    public let scope: URL
    public let targets: [PlannedTarget]
    public let startedAt: Date
}
public struct RefreshOutcome: Sendable {
    fileprivate let request: RefreshRequest
    fileprivate let replacements: [String: PlannedTarget]
    fileprivate let complete: Bool
    fileprivate var missing: Set<String> = []
}
public struct RefreshNotice: Sendable, Identifiable {
    public var id: String { target.id }
    public let target: PlannedTarget
    public let message: String
}
public enum RefreshStatus: Sendable { case ready, refreshing, required }
public struct RefreshChoices: Sendable {
    private var active: [URL: UUID] = [:]
    private var pending: [String: UUID] = [:]
    public private(set) var notices: [RefreshNotice] = []
    public init() {}
    public func status(_ id: String) -> RefreshStatus {
        guard let token = pending[id] else { return .ready }
        return active.values.contains(token) ? .refreshing : .required
    }
    public func requiresRefresh(_ id: String) -> Bool { pending[id] != nil }
    public func canReview(_ draft: PlanDraft) -> Bool {
        !draft.selected.isEmpty && !draft.selected.contains { requiresRefresh($0.id) }
    }
    public mutating func begin(scope: URL, draft: inout PlanDraft) -> RefreshRequest {
        let scope = scope.standardizedFileURL
        let targets = draft.selected.filter { $0.url.standardizedFileURL.pathComponents.starts(with: scope.pathComponents) }
        let request = RefreshRequest(id: UUID(), scope: scope, targets: targets, startedAt: Date())
        active[scope] = request.id
        for target in targets { pending[target.id] = request.id }
        notices.removeAll { $0.target.url.standardizedFileURL.pathComponents.starts(with: scope.pathComponents) }
        return request
    }
    /// Cancellation leaves evidence visible and pending. A cancelled result can never restore readiness.
    public mutating func cancel(_ request: RefreshRequest) {
        guard active[request.scope] == request.id else { return }
        active[request.scope] = nil
    }
    public mutating func finish(_ outcome: RefreshOutcome, draft: inout PlanDraft) {
        let request = outcome.request
        guard active[request.scope] == request.id else { return }
        active[request.scope] = nil
        guard outcome.complete else { return }
        let currentTargets = Dictionary(draft.selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for original in request.targets where pending[original.id] == request.id {
            pending[original.id] = nil
            guard let current = currentTargets[original.id],
                  current.observedAt == original.observedAt else { continue }
            if let replacement = outcome.replacements[original.id] {
                draft.replaceAfterRefresh(original, with: replacement)
            } else {
                draft.remove(original.id)
                notices.append(RefreshNotice(target: original, message: outcome.missing.contains(original.id) ? "File was removed or replaced. Its previous selection was cleared." : "File changed or is no longer eligible. Review it again before selecting it."))
            }
        }
    }
}
/// Serial actor keeps blocking candidate checks off the UI executor; no per-file task fan-out.
public actor RefreshValidator {
    public init() {}
    public func validate(_ request: RefreshRequest, against scan: ScanResult) -> RefreshOutcome {
        guard scan.scope.standardizedFileURL == request.scope, scan.observedAt >= request.startedAt, scan.isComplete else {
            return RefreshOutcome(request: request, replacements: [:], complete: false)
        }
        var replacements: [String: PlannedTarget] = [:]
        let observations = Dictionary(scan.observations.map { ($0.url.path + "|" + $0.resourceID + "|moveToTrash", $0) }, uniquingKeysWith: { first, _ in first })
        for original in request.targets {
            guard !Task.isCancelled else { return RefreshOutcome(request: request, replacements: [:], complete: false) }
            guard let item = observations[original.id],
                  let fresh = try? PlanDraft.candidate(item, in: scan, downloads: original.downloadsRoot),
                  fresh.logicalBytes == original.logicalBytes,
                  fresh.modifiedSeconds == original.modifiedSeconds,
                  fresh.modifiedNanoseconds == original.modifiedNanoseconds else { continue }
            replacements[original.id] = fresh
        }
        return RefreshOutcome(request: request, replacements: replacements, complete: true, missing: Set(request.targets.filter { observations[$0.id] == nil }.map(\.id)))
    }
}
