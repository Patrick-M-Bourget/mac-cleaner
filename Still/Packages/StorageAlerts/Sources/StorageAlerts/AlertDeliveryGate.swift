import Foundation

public enum AlertDeliveryResult: Sendable { case accepted, failed, staleSuccess, staleFailure }
/// A reset invalidates an awaiting notification service completion, including its failure path.
@MainActor public final class AlertDeliveryGate {
    private var generation = UUID()
    public init() {}
    public func invalidate() { generation = UUID() }
    public func submit(_ operation: @MainActor () async throws -> Void) async -> AlertDeliveryResult {
        let captured = generation
        do {
            try await operation()
            return captured == generation ? .accepted : .staleSuccess
        } catch { return captured == generation ? .failed : .staleFailure }
    }
}
