import Foundation

/// How the Applications page orders and filters its Apps, Plug-ins and leftover groups (#295): one sort, set by the list's
/// sortable column header (#352), and one search for all three. Searching only hides rows; it never changes what is
/// ticked. Kept for the session, never across launches.
public struct ApplicationsListing: Sendable, Equatable {
    /// The sortable column header's choice (#352): Size, largest first, by default (Decision 51).
    public var sort: ListSort
    /// What the search field holds; blank matches every row.
    public var search: String
    public init(sort: ListSort = ListSort(), search: String = "") { self.sort = sort; self.search = search }

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
        ordered(items.filter { matches(name: name($0), maker: maker($0)) }, name: name, bytes: bytes)
    }
    /// `items` in this order, none left out: for rows already matched another way, such as leftovers.
    public func ordered<T>(_ items: [T], name: (T) -> String, bytes: (T) -> Int64) -> [T] { sort.ordered(items, name: name, bytes: bytes) }
}
