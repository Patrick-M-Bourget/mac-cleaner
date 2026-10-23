import Foundation

@MainActor public protocol HistoryMaintenanceLifecycle: AnyObject {
    var operationActive: Bool { get }
    var maintenanceActive: Bool { get set }
}
/// Coordinates mutating retention/compaction with the same lifecycle used by cleanup and Quit.
@MainActor public enum HistoryLoadCoordinator {
    public static func load<Value: Sendable>(lifecycle: any HistoryMaintenanceLifecycle,
                                             perform: @Sendable (Bool) async throws -> Value) async rethrows -> Value {
        let mayMaintain = !lifecycle.maintenanceActive && !lifecycle.operationActive
        if mayMaintain { lifecycle.maintenanceActive = true }
        defer { if mayMaintain { lifecycle.maintenanceActive = false } }
        return try await perform(mayMaintain)
    }
}
