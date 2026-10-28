import Foundation

/// How the Applications page orders and filters its Apps, Plug-ins and leftover groups (#295): one Sort and one search for
/// all three. Searching only hides rows; it never changes what is ticked. Kept for the session, never across launches.
public struct ApplicationsListing: Sendable, Equatable {
    public enum Order: String, Sendable, CaseIterable, Identifiable {
        /// Largest first, the Decision 51 default.
        case size = "Size"
        /// As Finder sorts names: case and accents don't matter, and numbers read as numbers.
        case name = "Name"
        public var id: String { rawValue }
    }
    public var order: Order
    /// What the search field holds; blank matches every row.
    public var search: String
    public init(order: Order = .size, search: String = "") { self.order = order; self.search = search }

    /// Whether something is being searched for.
    public var isSearching: Bool { !query.isEmpty }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Whether a row of this name and maker is shown: either contains the search, ignoring case and accents.
    public func matches(name: String, maker: String?) -> Bool {
        let query = query
        return query.isEmpty || name.localizedStandardContains(query) || maker?.localizedStandardContains(query) == true
    }

    /// Whether a leftover is shown: by the removed app it is grouped under, its own name, or its maker.
    public func matches(_ leftover: Candidate) -> Bool {
        let name = leftover.itemName ?? leftover.url.lastPathComponent
        return matches(name: leftover.appName ?? name, maker: leftover.leftover?.owner.name) || matches(name: name, maker: nil)
    }

    /// The `items` the search matches, in this order.
    public func arranged<T>(_ items: [T], name: (T) -> String, maker: (T) -> String?, bytes: (T) -> Int64) -> [T] {
        let items = items.filter { matches(name: name($0), maker: maker($0)) }
        func byName(_ left: T, _ right: T) -> Bool { name(left).localizedStandardCompare(name(right)) == .orderedAscending }
        switch order {
        case .name: return items.sorted(by: byName)
        case .size: return items.sorted { bytes($0) != bytes($1) ? bytes($0) > bytes($1) : byName($0, $1) }
        }
    }
}
