import Foundation
import StillCore

/// Capacity-only metadata shared by presentation and optional alerts; never enumerates files.
struct StartupVolumeCapacity: Sendable {
    let available: Int64?
    let total: Int64?
    let volumeID: String?
    let metric: String
    let observedAt: Date
    static func read() -> Self {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey])
        let important = values?.volumeAvailableCapacityForImportantUsage
        return Self(available: important ?? values?.volumeAvailableCapacity.map(Int64.init), total: values?.volumeTotalCapacity.map(Int64.init), volumeID: values?.volumeUUIDString, metric: important == nil ? "available" : "important", observedAt: Date())
    }
}

@MainActor final class NativeCapacityRefreshSystem: CapacityRefreshSystem {
    var now: Date { Date() }
    func readStartupCapacity(_ completed: @escaping @MainActor @Sendable (StartupCapacityReading) -> Void) {
        Task {
            let sample = await Task.detached(priority: .utility) { StartupVolumeCapacity.read() }.value
            completed(StartupCapacityReading(available: sample.available, total: sample.total, volumeID: sample.volumeID, metric: sample.metric, observedAt: sample.observedAt))
        }
    }
    func deadline(after seconds: TimeInterval, _ expired: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        let task = Task {
            do { try await Task.sleep(for: .seconds(seconds)); expired() }
            catch { /* Completed metadata reads cancel their one-shot deadline. */ }
        }
        return { task.cancel() }
    }
}

extension CapacityRefreshController {
    var observationText: String {
        guard let reading else { return isRefreshing ? "Checking capacity…" : "Capacity unavailable" }
        let prefix = failed ? "Last observed " : "Observed "
        let metric = reading.metric == "important" ? "Available for important usage" : "Available capacity fallback"
        return prefix + reading.observedAt.formatted() + " · " + metric
    }
    var statusText: String {
        if isRefreshing { return reading == nil ? "Checking capacity…" : "Refreshing…" }
        return failed ? "Couldn’t refresh capacity" : ""
    }
}
