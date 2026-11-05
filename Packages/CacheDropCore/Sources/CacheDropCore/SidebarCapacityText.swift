import Foundation

/// The sidebar's storage text (#353): one short `line` ("312 GB free of 1 TB", the owner's choice) and the full
/// `description` for its accessibility label and tooltip, in full, with "free" (#764, Decision 92 rule 1). Decimal units, as Finder.
public struct SidebarCapacityText: Sendable, Equatable {
    public let line: String
    public let description: String
    public init(available: Int64?, total: Int64?) {
        guard let available, available >= 0 else {
            line = "Free space unknown"; description = line; return
        }
        if let total = Self.validTotal(available: available, total: total) {
            line = "\(SizeFormatter.text(available)) free of \(SizeFormatter.text(total))"
            description = line
        } else {
            line = "\(SizeFormatter.text(available)) free"
            description = "\(SizeFormatter.text(available)) free · Disk size unknown"
        }
    }
    /// The total, when it and the available space are a consistent whole-disk reading.
    public static func validTotal(available: Int64?, total: Int64?) -> Int64? {
        guard let available, let total, total > 0, available >= 0, available <= total else { return nil }
        return total
    }
}
