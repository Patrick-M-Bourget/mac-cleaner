import Darwin
import Foundation
import CacheDropCore

/// Capacity-only metadata shared by presentation and optional alerts; never enumerates files.
struct StartupVolumeCapacity: Sendable {
    let available: Int64?
    let total: Int64?
    let volumeID: String?
    let metric: String
    let observedAt: Date
    /// The startup volume's name as Finder shows it, e.g. "Macintosh HD". Metadata only.
    static let name: String? = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName
    static func read() -> Self {
        #if DEBUG
        if let fixture = fixture { return fixture }
        #endif
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey])
        let important = values?.volumeAvailableCapacityForImportantUsage
        return Self(available: important ?? values?.volumeAvailableCapacity.map(Int64.init), total: values?.volumeTotalCapacity.map(Int64.init), volumeID: values?.volumeUUIDString, metric: important == nil ? "available" : "important", observedAt: Date())
    }
}

#if DEBUG
extension StartupVolumeCapacity {
    /// A disposable test run can read a fixture disk (`CACHEDROP_TEST_CAPACITY` = "available,total" in bytes), so a fixture
    /// home's few kilobytes fill a visible part of the meter (#164). Never set outside tests.
    static var fixture: Self? {
        guard LocalStateLocation.isDisposableTest, let value = ProcessInfo.processInfo.environment["CACHEDROP_TEST_CAPACITY"] else { return nil }
        let parts = value.split(separator: ",").compactMap { Int64($0) }
        guard parts.count == 2 else { return nil }
        return Self(available: parts[0], total: parts[1], volumeID: "fixture", metric: "important", observedAt: Date())
    }
}
#endif

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
        guard let reading else { return isRefreshing ? "Startup-volume capacity" : "Capacity unavailable" }
        let prefix = failed ? "Last observed " : "Observed "
        let metric = reading.metric == "important" ? "Available for important usage" : "Available capacity fallback"
        return prefix + reading.observedAt.formatted() + " · " + metric
    }
    var sidebarObservationText: String {
        guard let reading else { return "Not yet observed" }
        return (failed ? "Last observed " : "Observed ") + reading.observedAt.formatted(date: .omitted, time: .shortened)
    }
    var statusText: String {
        if isRefreshing { return reading == nil ? "Checking capacity…" : "Refreshing…" }
        return failed ? "Couldn’t refresh capacity" : ""
    }
}
