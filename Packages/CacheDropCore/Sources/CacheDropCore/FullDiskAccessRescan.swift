import Foundation

/// Decides when CacheDrop rescans by itself (#124): when it becomes active and Full Disk Access has changed
/// from not granted to granted since the last scan, so "needs Full Disk Access" lines go away without Scan again.
public struct FullDiskAccessRescan: Sendable {
    /// What the last scan's probe saw, or what the last activation saw since. Nil before the first scan.
    public private(set) var lastStatus: FullDiskAccessStatus?
    public init() {}
    /// A scan probed `status`.
    public mutating func scanned(_ status: FullDiskAccessStatus) { lastStatus = status }
    /// CacheDrop became active: probes now and says whether to rescan. True once per change from not granted to granted.
    public mutating func activated(probing detector: any FullDiskAccessDetecting) -> Bool {
        let now = detector.status()
        defer { lastStatus = now }
        return lastStatus == .notGranted && now == .granted
    }
}
