import Foundation

/// The sidebar's storage text (#353): one short `line` ("312 GB free of 1 TB", the owner's choice) and the full
/// `description` ("312 GB available of 1 TB") for its accessibility label and tooltip. Decimal units, as Finder.
public struct SidebarCapacityText: Sendable, Equatable {
    public let line: String
    public let description: String
    public init(available: Int64?, total: Int64?) {
        func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
        guard let available, available >= 0 else {
            line = "Free space unavailable"; description = line; return
        }
        if let total = Self.validTotal(available: available, total: total) {
            line = "\(bytes(available)) free of \(bytes(total))"
            description = "\(bytes(available)) available of \(bytes(total))"
        } else {
            line = "\(bytes(available)) available"
            description = line + " · Total capacity unavailable"
        }
    }
    /// The total, when it and the available space are a consistent whole-disk reading.
    public static func validTotal(available: Int64?, total: Int64?) -> Int64? {
        guard let available, let total, total > 0, available >= 0, available <= total else { return nil }
        return total
    }
}
