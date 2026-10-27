import Foundation

/// Which available-space figure a reading is: for important usage, or the plain fallback.
public enum CapacityMetric: String, Codable, Sendable { case important, available }

/// The volume's available space at one moment.
public struct CapacitySample: Sendable {
    public let available: Int64?
    public let total: Int64?
    public let volumeID: String?
    public let metric: CapacityMetric
    public let date: Date
    public init(available: Int64?, total: Int64?, volumeID: String?, metric: CapacityMetric, date: Date) {
        self.available = available; self.total = total; self.volumeID = volumeID; self.metric = metric; self.date = date
    }
    /// Reads the volume holding `url`, preferring available space for important usage.
    public static func read(_ url: URL) -> CapacitySample? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey]) else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage
        return CapacitySample(available: important ?? values.volumeAvailableCapacity.map(Int64.init), total: values.volumeTotalCapacity.map(Int64.init),
                              volumeID: values.volumeUUIDString, metric: important == nil ? .available : .important, date: Date())
    }
}
