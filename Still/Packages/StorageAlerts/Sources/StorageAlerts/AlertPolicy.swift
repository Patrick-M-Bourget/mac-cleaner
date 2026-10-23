import Foundation
public struct AlertPolicy: Sendable {
    public enum Authorization: Sendable { case allowed, denied, unknown }
    public var enabled = false
    public var thresholdBytes: Int64 = 40_000_000_000
    private var lowEpisode = false
    private var lastSample: Date?
    public init() {}
    public mutating func shouldSample(at date: Date, authorization: Authorization) -> Bool {
        guard enabled, authorization == .allowed else { return false }
        if let lastSample, date.timeIntervalSince(lastSample) < 60 { return false }
        lastSample = date; return true
    }
    public mutating func submissionFailed() { lowEpisode = false }
    public static func validThreshold(_ value: Int64, total: Int64?) -> Bool {
        guard let total else { return false }
        return value >= 1_000_000_000 && value < total
    }
    public mutating func observe(available: Int64?, total: Int64?) -> Bool {
        guard enabled, let available, let total, available >= 0, available <= total,
              Self.validThreshold(thresholdBytes, total: total) else { return false }
        if available >= min(total, thresholdBytes + min(total - thresholdBytes, 5_000_000_000)) { lowEpisode = false }
        guard available < thresholdBytes, !lowEpisode else { return false }
        lowEpisode = true; return true
    }
}
