import Foundation

public enum AlertDeliveryResult: Sendable { case accepted, failed, staleSuccess, staleFailure }
/// Reset or opting out invalidates an awaiting notification completion, including its failure path.
@MainActor public final class AlertDeliveryGate {
    private var generation = UUID()
    public init() {}
    public func invalidate() { generation = UUID() }
    /// The controller remains responsible for whether a new submission is eligible.
    public func setEnabled(_ enabled: Bool) { if !enabled { invalidate() } }
    public func submit(_ operation: @MainActor () async throws -> Void) async -> AlertDeliveryResult {
        let captured = generation
        do {
            try await operation()
            return captured == generation ? .accepted : .staleSuccess
        } catch { return captured == generation ? .failed : .staleFailure }
    }
}
