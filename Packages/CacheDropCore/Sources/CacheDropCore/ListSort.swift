import Foundation

/// A list's sort as its sortable column header sets it (#352, #373): by Name or by the size column (Applications' Size,
/// Explore storage's On disk), either way round. Kept for the session, never across launches.
public struct ListSort: Sendable, Equatable {
    /// A sortable column; its raw value ends its header's accessibility identifier (`<identifier>-name`, `-size`).
    public enum Column: String, Sendable, Equatable { case name, size }
    public var column: Column
    /// A to Z, or smallest first.
    public var ascending: Bool
    /// Size, largest first: the default (Decision 51).
    public init(column: Column = .size, ascending: Bool = false) { self.column = column; self.ascending = ascending }

    /// Clicking a column's header: the active column flips; another becomes active, names A to Z and sizes largest first.
    public mutating func select(_ clicked: Column) {
        if clicked == column { ascending.toggle() } else { self = ListSort(column: clicked, ascending: clicked == .name) }
    }

    /// What the order reads as on the active column's header.
    public var directionText: String {
        switch column {
        case .name: ascending ? "A to Z" : "Z to A"
        case .size: ascending ? "Smallest first" : "Largest first"
        }
    }

    /// `items` in this order. Names sort as Finder does: case and accents don't matter, and numbers read as numbers. Rows
    /// of one size go by name, A to Z. Each row's name and size is read once.
    public func ordered<T>(_ items: [T], name: (T) -> String, bytes: (T) -> Int64) -> [T] {
        let keyed = items.map { (item: $0, name: name($0), bytes: column == .size ? bytes($0) : 0) }
        return keyed.sorted { left, right in
            if column == .size, left.bytes != right.bytes { return ascending ? left.bytes < right.bytes : left.bytes > right.bytes }
            let order = left.name.localizedStandardCompare(right.name)
            return column == .name && !ascending ? order == .orderedDescending : order == .orderedAscending
        }.map(\.item)
    }
}
