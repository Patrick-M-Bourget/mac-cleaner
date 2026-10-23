import Foundation

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
